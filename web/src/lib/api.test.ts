import { describe, expect, test } from 'bun:test';
import { fetchSharedIdea } from './api';

describe('fetchSharedIdea', () => {
  test('rejects non-numeric ids without fetching', async () => {
    let called = false;
    const idea = await fetchSharedIdea('abc', {
      fetch: async () => {
        called = true;
        return new Response('nope');
      },
    });
    expect(idea).toBeNull();
    expect(called).toBe(false);
  });

  test('uses the bound API fetcher', async () => {
    const idea = await fetchSharedIdea('100', {
      fetch: async () =>
        Response.json({
          id: 100,
          name: null,
          type: 'food',
          description: 'coffee',
          media_url: null,
          address: null,
          location: 'Los Angeles',
          location_type: null,
          duration: null,
          venue: 'Ondo Coffee Co.',
          place_id: null,
          open_hours: null,
          created_at: '2026-01-01T00:00:00Z',
        }),
    });
    expect(idea?.venue).toBe('Ondo Coffee Co.');
    expect(idea?.id).toBe(100);
  });

  test('returns null when the bound API 404s', async () => {
    const idea = await fetchSharedIdea('1', {
      fetch: async () => new Response('{"error":"Not found"}', { status: 404 }),
    });
    expect(idea).toBeNull();
  });
});
