import { createPrivateKey, createSign } from 'node:crypto';
import type { MapsPlace } from './types';
import { log, logError } from './log';

export type PlacesLookup = {
  place: MapsPlace;
  image: string | null;
};

type AppleMapsCredentials = {
  APPLE_MAPS_TEAM_ID: string;
  APPLE_MAPS_KEY_ID: string;
  APPLE_MAPS_PRIVATE_KEY: string;
};

type ApplePlace = {
  id?: string;
};

type AppleSearchResponse = {
  results?: ApplePlace[];
};

type AppleTokenResponse = {
  accessToken?: string;
  expiresInSeconds?: number;
};

export type PlacesLookupContext = {
  entry_id?: string;
  venue?: string | null;
};

let cachedToken: { value: string; expiresAt: number } | null = null;
let tokenRequest: Promise<string> | null = null;

function responseContentType(response: Response): string | null {
  return response.headers.get('content-type');
}

async function responseBodyPreview(response: Response): Promise<string | null> {
  try {
    const body = await response.text();
    if (!body) return null;
    return body.replace(/\s+/g, ' ').slice(0, 500);
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

function base64url(value: Uint8Array | string): string {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function readDerLength(bytes: Uint8Array, offset: number): {
  length: number;
  nextOffset: number;
} {
  const first = bytes[offset];
  if (first < 0x80) return { length: first, nextOffset: offset + 1 };

  const byteCount = first & 0x7f;
  let length = 0;
  for (let index = 0; index < byteCount; index += 1) {
    length = (length << 8) | bytes[offset + 1 + index];
  }
  return { length, nextOffset: offset + 1 + byteCount };
}

function derToJoseSignature(der: Uint8Array): Uint8Array {
  let offset = 0;
  if (der[offset++] !== 0x30) throw new Error('ECDSA signature was not a DER sequence');
  const sequenceLength = readDerLength(der, offset);
  offset = sequenceLength.nextOffset;
  if (sequenceLength.length > der.length - offset) {
    throw new Error('ECDSA DER signature length was invalid');
  }

  if (der[offset++] !== 0x02) throw new Error('ECDSA signature was missing r');
  const rLength = readDerLength(der, offset);
  offset = rLength.nextOffset;
  const r = der.slice(offset, offset + rLength.length);
  offset += rLength.length;

  if (der[offset++] !== 0x02) throw new Error('ECDSA signature was missing s');
  const sLength = readDerLength(der, offset);
  offset = sLength.nextOffset;
  const s = der.slice(offset, offset + sLength.length);

  const jose = new Uint8Array(64);
  jose.set(r.slice(-32), 32 - Math.min(r.length, 32));
  jose.set(s.slice(-32), 64 - Math.min(s.length, 32));
  return jose;
}

async function createMapsAuthToken(credentials: AppleMapsCredentials): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({
    alg: 'ES256',
    kid: credentials.APPLE_MAPS_KEY_ID,
    typ: 'JWT',
  }));
  const payload = base64url(JSON.stringify({
    iss: credentials.APPLE_MAPS_TEAM_ID,
    iat: now,
    exp: now + 300,
    scope: 'server_api',
  }));
  const signingInput = `${header}.${payload}`;
  const signer = createSign('SHA256');
  signer.update(signingInput);
  signer.end();
  const derSignature = signer.sign(
    createPrivateKey(credentials.APPLE_MAPS_PRIVATE_KEY.replaceAll('\\n', '\n')),
  );
  return `${signingInput}.${base64url(derToJoseSignature(derSignature))}`;
}

async function getMapsAccessToken(credentials: AppleMapsCredentials): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 30_000) {
    log('apple_maps.token_cache_hit', {
      expires_in_ms: cachedToken.expiresAt - now,
    });
    return cachedToken.value;
  }

  if (tokenRequest) {
    log('apple_maps.token_request_joined');
    return tokenRequest;
  }

  tokenRequest = (async () => {
    const started = Date.now();
    log('apple_maps.token_request_start', {
      team_id: credentials.APPLE_MAPS_TEAM_ID,
      key_id: credentials.APPLE_MAPS_KEY_ID,
      team_id_configured: Boolean(credentials.APPLE_MAPS_TEAM_ID),
      key_id_configured: Boolean(credentials.APPLE_MAPS_KEY_ID),
      private_key_configured: Boolean(credentials.APPLE_MAPS_PRIVATE_KEY),
      private_key_chars: credentials.APPLE_MAPS_PRIVATE_KEY.length,
      private_key_has_pem_header: credentials.APPLE_MAPS_PRIVATE_KEY.includes(
        '-----BEGIN PRIVATE KEY-----',
      ),
      private_key_has_pem_footer: credentials.APPLE_MAPS_PRIVATE_KEY.includes(
        '-----END PRIVATE KEY-----',
      ),
      private_key_literal_newline_escapes:
        (credentials.APPLE_MAPS_PRIVATE_KEY.match(/\\n/g) ?? []).length,
      private_key_actual_newlines:
        (credentials.APPLE_MAPS_PRIVATE_KEY.match(/\n/g) ?? []).length,
    });

    try {
      const authToken = await createMapsAuthToken(credentials);
      log('apple_maps.auth_token_created', {
        jwt_part_lengths: authToken.split('.').map((part) => part.length),
        ms: Date.now() - started,
      });
      const response = await fetch('https://maps-api.apple.com/v1/token', {
        headers: {
          Authorization: `Bearer ${authToken}`,
          Accept: 'application/json',
          'User-Agent': 'kindling-api',
        },
      });
      if (!response.ok) {
        const bodyPreview = await responseBodyPreview(response);
        log('apple_maps.token_response', {
          status: response.status,
          status_text: response.statusText,
          content_type: responseContentType(response),
          body_preview: bodyPreview,
          ms: Date.now() - started,
        });
        throw new Error(
          `Apple Maps token request failed with ${response.status}`
          + (bodyPreview ? `: ${bodyPreview}` : ''),
        );
      }

      const token = (await response.json()) as AppleTokenResponse;
      log('apple_maps.token_response', {
        status: response.status,
        content_type: responseContentType(response),
        has_access_token: Boolean(token.accessToken),
        expires_in_seconds: token.expiresInSeconds ?? null,
        ms: Date.now() - started,
      });
      if (!token.accessToken) {
        throw new Error('Apple Maps token response was missing accessToken');
      }

      cachedToken = {
        value: token.accessToken,
        expiresAt: now + Math.max((token.expiresInSeconds ?? 0) - 30, 30) * 1000,
      };
      return token.accessToken;
    } catch (err) {
      logError('apple_maps.token_request_failed', err, {
        ms: Date.now() - started,
      });
      throw err;
    }
  })();

  try {
    return await tokenRequest;
  } finally {
    tokenRequest = null;
  }
}

function toMapsPlace(place: ApplePlace): MapsPlace | null {
  return place.id ? { id: place.id } : null;
}

export async function lookupPlace(
  query: string,
  credentials: AppleMapsCredentials,
  context: PlacesLookupContext = {},
): Promise<PlacesLookup | null> {
  const started = Date.now();
  const fingerprint = await queryFingerprint(query);
  const logContext = {
    ...context,
    query_fingerprint: fingerprint,
    query_length: query.length,
  };

  try {
    const token = await getMapsAccessToken(credentials);
    const url = new URL('https://maps-api.apple.com/v1/search');
    url.searchParams.set('q', query);
    url.searchParams.set('resultTypeFilter', 'poi');
    url.searchParams.set('lang', 'en-US');
    log('apple_maps.search_request', logContext);
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
        'User-Agent': 'kindling-api',
      },
    });
    if (!response.ok) {
      log('apple_maps.search_response', {
        ...logContext,
        status: response.status,
        status_text: response.statusText,
        content_type: responseContentType(response),
        body_preview: await responseBodyPreview(response),
        ms: Date.now() - started,
      });
      return null;
    }

    const data = (await response.json()) as AppleSearchResponse;
    const results = Array.isArray(data.results) ? data.results : [];
    const placesWithId = results.filter((result) => Boolean(result?.id)).length;
    log('apple_maps.search_response', {
      ...logContext,
      status: response.status,
      content_type: responseContentType(response),
      result_count: results.length,
      places_with_id: placesWithId,
      top_level_keys: Object.keys(data),
      first_result_keys: results[0] && typeof results[0] === 'object'
        ? Object.keys(results[0])
        : [],
      ms: Date.now() - started,
    });
    const place = results.map(toMapsPlace).find((result) => result != null) ?? null;
    if (place == null) {
      log('apple_maps.search_miss', {
        ...logContext,
        result_count: results.length,
        places_with_id: placesWithId,
        ms: Date.now() - started,
      });
    }
    return place ? { place, image: null } : null;
  } catch (err) {
    logError('apple_maps.search_failed', err, {
      ...logContext,
      ms: Date.now() - started,
    });
    return null;
  }
}
