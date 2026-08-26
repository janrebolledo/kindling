import type { MapsPlace } from './types';
import type { SupabaseClient } from '@supabase/supabase-js';
import { cachedJSON, cachedResponse } from './cache';
import { log, logError } from './log';

export type GoogleMapsCredentials = {
  GOOGLE_MAPS_API_KEY: string;
  PUBLIC_API_URL?: string;
};

export type PlacesLookup = {
  place: MapsPlace;
  image: string | null;
};

export type PlaceDetails = {
  id: string;
  name: string | null;
  latitude: number | null;
  longitude: number | null;
  formattedAddress: string | null;
  weekdayDescriptions: string[];
  openNow: boolean | null;
  photoUrl: string | null;
  photoAttributions: string[];
  photoAttributionUrls: Array<string | null>;
  googleMapsUri: string | null;
};

type GooglePlaceSearchResponse = {
  places?: Array<{
    id?: string;
    photos?: Array<{ name?: string }>;
  }>;
};

type GooglePlaceResponse = {
  id?: string;
  displayName?: { text?: string };
  location?: { latitude?: number; longitude?: number };
  formattedAddress?: string;
  regularOpeningHours?: { weekdayDescriptions?: string[] };
  currentOpeningHours?: {
    openNow?: boolean;
    weekdayDescriptions?: string[];
  };
  photos?: Array<{
    name?: string;
    authorAttributions?: Array<{ displayName?: string; uri?: string }>;
  }>;
  googleMapsUri?: string;
};

export type PlacesLookupContext = {
  entry_id?: string;
  venue?: string | null;
};

function publicAPIBaseURL(credentials: GoogleMapsCredentials): string {
  return (credentials.PUBLIC_API_URL ?? 'https://api.getkindl.ing').replace(/\/$/, '');
}

function googlePlaceId(placeId: string): string {
  return placeId.startsWith('places/') ? placeId.slice('places/'.length) : placeId;
}

export function photoURL(
  placeId: string,
  credentials: GoogleMapsCredentials,
): string {
  return `${publicAPIBaseURL(credentials)}/places/${encodeURIComponent(googlePlaceId(placeId))}/photo`;
}

function responseContentType(response: Response): string | null {
  return response.headers.get('content-type');
}

async function responseBodyPreview(response: Response): Promise<string | null> {
  try {
    const body = await response.text();
    return body ? body.replace(/\s+/g, ' ').slice(0, 500) : null;
  } catch {
    return null;
  }
}

async function queryFingerprint(query: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(query),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('').slice(0, 16);
}

function googleHeaders(
  credentials: GoogleMapsCredentials,
  fieldMask: string,
): Record<string, string> {
  return {
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': credentials.GOOGLE_MAPS_API_KEY,
    'X-Goog-FieldMask': fieldMask,
  };
}

export async function lookupPlace(
  query: string,
  credentials: GoogleMapsCredentials,
  context: PlacesLookupContext = {},
): Promise<PlacesLookup | null> {
  const started = Date.now();
  const fingerprint = await queryFingerprint(query);
  const logContext = { ...context, query_fingerprint: fingerprint, query_length: query.length };

  try {
    log('google_places.search_request', logContext);
    return await cachedJSON('google-places-search', fingerprint, 86400, async () => {
      const response = await fetch('https://places.googleapis.com/v1/places:searchText', {
        method: 'POST',
        headers: googleHeaders(credentials, 'places.id,places.photos'),
        body: JSON.stringify({ textQuery: query, maxResultCount: 1 }),
      });

      if (!response.ok) {
        log('google_places.search_response', {
          ...logContext,
          status: response.status,
          status_text: response.statusText,
          content_type: responseContentType(response),
          body_preview: await responseBodyPreview(response),
          ms: Date.now() - started,
        });
        return null;
      }

      const data = (await response.json()) as GooglePlaceSearchResponse;
      const result = data.places?.[0];
      const placeId = result?.id;
      log('google_places.search_response', {
        ...logContext,
        status: response.status,
        result_count: data.places?.length ?? 0,
        has_photo: Boolean(result?.photos?.[0]?.name),
        ms: Date.now() - started,
      });

      return placeId
        ? {
            place: { id: placeId },
            image: result?.photos?.[0]?.name ? photoURL(placeId, credentials) : null,
          }
        : null;
    });
  } catch (err) {
    logError('google_places.search_failed', err, { ...logContext, ms: Date.now() - started });
    return null;
  }
}

export async function getPlaceDetails(
  placeId: string,
  credentials: GoogleMapsCredentials,
  supabase: SupabaseClient,
): Promise<PlaceDetails | null> {
  const normalizedPlaceId = googlePlaceId(placeId);
  const { data: saved } = await supabase
    .from('google_places')
    .select()
    .eq('place_id', normalizedPlaceId)
    .maybeSingle();
  if (saved) {
    return {
      id: saved.place_id,
      name: saved.name,
      latitude: saved.latitude,
      longitude: saved.longitude,
      formattedAddress: saved.formatted_address,
      weekdayDescriptions: saved.weekday_descriptions ?? [],
      openNow: null,
      photoUrl: saved.photo_name ? photoURL(saved.place_id, credentials) : null,
      photoAttributions: saved.photo_attributions ?? [],
      photoAttributionUrls: saved.photo_attribution_uris ?? [],
      googleMapsUri: saved.google_maps_uri,
    };
  }

  const response = await fetch(
    `https://places.googleapis.com/v1/places/${encodeURIComponent(normalizedPlaceId)}`,
    {
      headers: googleHeaders(
        credentials,
        'id,displayName,location,formattedAddress,regularOpeningHours,currentOpeningHours,photos,googleMapsUri',
      ),
    },
  );

  if (!response.ok) return null;
  const place = (await response.json()) as GooglePlaceResponse;
  if (!place.id) return null;

  const details: PlaceDetails = {
    id: place.id,
    name: place.displayName?.text ?? null,
    latitude: place.location?.latitude ?? null,
    longitude: place.location?.longitude ?? null,
    formattedAddress: place.formattedAddress ?? null,
    weekdayDescriptions:
      place.regularOpeningHours?.weekdayDescriptions
      ?? place.currentOpeningHours?.weekdayDescriptions
      ?? [],
    openNow: place.currentOpeningHours?.openNow ?? null,
    photoUrl: place.photos?.[0]?.name ? photoURL(place.id, credentials) : null,
    photoAttributions: (place.photos?.[0]?.authorAttributions ?? [])
      .map((attribution) => attribution.displayName ?? attribution.uri ?? '')
      .filter(Boolean),
    photoAttributionUrls: (place.photos?.[0]?.authorAttributions ?? [])
      .map((attribution) => attribution.uri ?? null),
    googleMapsUri: place.googleMapsUri ?? null,
  };

  const { error } = await supabase.from('google_places').upsert(
    {
      place_id: googlePlaceId(place.id),
      name: details.name,
      latitude: details.latitude,
      longitude: details.longitude,
      formatted_address: details.formattedAddress,
      weekday_descriptions: details.weekdayDescriptions,
      photo_name: place.photos?.[0]?.name ?? null,
      photo_attributions: details.photoAttributions,
      photo_attribution_uris: details.photoAttributionUrls,
      google_maps_uri: details.googleMapsUri,
    },
    { onConflict: 'place_id', ignoreDuplicates: true },
  );
  if (error) logError('google_places.save_failed', error, { place_id: details.id });

  return details;
}

export async function fetchPlacePhoto(
  placeId: string,
  credentials: GoogleMapsCredentials,
): Promise<Response | null> {
  const normalizedPlaceId = googlePlaceId(placeId);
  return cachedResponse('google-place-photos', normalizedPlaceId, 86400, async () => {
    const response = await fetch(
      `https://places.googleapis.com/v1/places/${encodeURIComponent(normalizedPlaceId)}`,
      { headers: googleHeaders(credentials, 'photos') },
    );
    if (!response.ok) return null;

    const place = (await response.json()) as GooglePlaceResponse;
    const photoName = place.photos?.[0]?.name;
    if (!photoName) return null;

    const photoResponse = await fetch(
      `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=1200`,
      { headers: { 'X-Goog-Api-Key': credentials.GOOGLE_MAPS_API_KEY } },
    );
    if (!photoResponse.ok || !photoResponse.body) return null;

    const headers = new Headers();
    const contentType = photoResponse.headers.get('content-type');
    if (contentType) headers.set('Content-Type', contentType);
    headers.set('Cache-Control', 'public, max-age=86400, s-maxage=86400');
    return new Response(photoResponse.body, { status: 200, headers });
  });
}
