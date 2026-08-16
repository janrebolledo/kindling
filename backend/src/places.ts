import type { MapsPlace } from './types';

export type PlacesLookup = {
  place: MapsPlace;
  image: string | null;
};

const FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.formattedAddress',
  'places.addressComponents',
  'places.photos',
  'places.generativeSummary',
  'places.priceLevel',
  'places.currentOpeningHours',
].join(',');

export async function lookupPlace(
  query: string,
  apiKey: string,
): Promise<PlacesLookup | null> {
  let response: Response;
  try {
    response = await fetch(
      'https://places.googleapis.com/v1/places:searchText?pageSize=1',
      {
        method: 'POST',
        body: JSON.stringify({ textQuery: query }),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-FieldMask': FIELD_MASK,
          'X-Goog-Api-Key': apiKey,
        },
      },
    );
  } catch {
    return null;
  }

  if (!response.ok) return null;

  const data = (await response.json()) as { places?: MapsPlace[] };
  const place = data.places?.[0];
  if (place == null) return null;

  const photoName = place.photos?.[0]?.name;
  let image: string | null = null;
  if (photoName) {
    try {
      const media = await fetch(
        `https://places.googleapis.com/v1/${photoName}/media?key=${apiKey}&maxHeightPx=1600`,
        { method: 'GET' },
      );
      image = media.url;
    } catch {
      image = null;
    }
  }

  return { place, image };
}
