const CACHE_KEY_ORIGIN = 'https://kindling-cache.invalid';

function cacheKey(namespace: string, key: string): Request {
  return new Request(
    `${CACHE_KEY_ORIGIN}/${namespace}/${encodeURIComponent(key)}`,
    { method: 'GET' },
  );
}

function cacheControl(maxAgeSeconds: number): string {
  return `public, max-age=${maxAgeSeconds}, s-maxage=${maxAgeSeconds}`;
}

/**
 * Reads or populates a JSON value in Cloudflare's edge cache.
 * Cache failures are intentionally non-fatal: the origin request remains the
 * source of truth if the cache is unavailable or contains malformed data.
 */
export async function cachedJSON<T>(
  namespace: string,
  key: string,
  maxAgeSeconds: number,
  load: () => Promise<T | null>,
): Promise<T | null> {
  const request = cacheKey(namespace, key);

  try {
    const cached = await caches.default.match(request);
    if (cached) {
      try {
        return await cached.json() as T;
      } catch {
        await caches.default.delete(request);
      }
    }
  } catch {
    // Continue to the origin when the cache is unavailable.
  }

  const value = await load();
  if (value == null) return null;

  try {
    await caches.default.put(
      request,
      new Response(JSON.stringify(value), {
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Cache-Control': cacheControl(maxAgeSeconds),
        },
      }),
    );
  } catch {
    // The response is still useful even if this cache write fails.
  }

  return value;
}

/** Reads or populates a streamed response in Cloudflare's edge cache. */
export async function cachedResponse(
  namespace: string,
  key: string,
  maxAgeSeconds: number,
  load: () => Promise<Response | null>,
): Promise<Response | null> {
  const request = cacheKey(namespace, key);

  try {
    const cached = await caches.default.match(request);
    if (cached) return cached;
  } catch {
    // Continue to the origin when the cache is unavailable.
  }

  const response = await load();
  if (response == null) return null;

  try {
    const cachedResponse = response.clone();
    cachedResponse.headers.set('Cache-Control', cacheControl(maxAgeSeconds));
    await caches.default.put(request, cachedResponse);
  } catch {
    // The response is still useful even if this cache write fails.
  }

  return response;
}
