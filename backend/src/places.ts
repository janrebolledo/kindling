import type { MapsPlace } from './types';

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

let cachedToken: { value: string; expiresAt: number } | null = null;
let tokenRequest: Promise<string> | null = null;

function base64url(value: Uint8Array | string): string {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function pemToDer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
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
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(credentials.APPLE_MAPS_PRIVATE_KEY.replaceAll('\\n', '\n')),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

async function getMapsAccessToken(credentials: AppleMapsCredentials): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 30_000) {
    return cachedToken.value;
  }

  if (tokenRequest) return tokenRequest;

  tokenRequest = (async () => {
    const authToken = await createMapsAuthToken(credentials);
    const response = await fetch('https://maps-api.apple.com/v1/token', {
      headers: { Authorization: `Bearer ${authToken}` },
    });
    if (!response.ok) {
      throw new Error(`Apple Maps token request failed with ${response.status}`);
    }

    const token = (await response.json()) as AppleTokenResponse;
    if (!token.accessToken) throw new Error('Apple Maps token response was missing accessToken');

    cachedToken = {
      value: token.accessToken,
      expiresAt: now + Math.max((token.expiresInSeconds ?? 0) - 30, 30) * 1000,
    };
    return token.accessToken;
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
): Promise<PlacesLookup | null> {
  try {
    const token = await getMapsAccessToken(credentials);
    const url = new URL('https://maps-api.apple.com/v1/search');
    url.searchParams.set('q', query);
    url.searchParams.set('resultTypeFilter', 'poi');
    url.searchParams.set('lang', 'en-US');
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!response.ok) return null;

    const data = (await response.json()) as AppleSearchResponse;
    const place = data.results?.map(toMapsPlace).find((result) => result != null) ?? null;
    return place ? { place, image: null } : null;
  } catch {
    return null;
  }
}
