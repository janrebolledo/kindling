import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { cors } from 'hono/cors';
import { cachedJSON } from './cache';
import { createAI, createSupabase } from './clients';
import { userFromBearerToken, wipeAccount } from './deleteAccount';
import { processEntry } from './ideas';
import { log, logError } from './log';
import { fetchPlacePhoto, getPlaceDetails } from './places';
import { getSharedIdea, recordShareOpen } from './share';
import type { Screenshot } from './types';
import { parseScreenshot } from './utils/parseScreenshot';
import type { ExtractionResult } from './utils/parseScreenshot';

type ItemLog = {
  status: string;
  reason?: string | null;
  venue?: string | null;
  via?: string;
  idea_id?: number;
  place_id?: string | null;
  error?: string;
};

type RouteRequest = {
  origin?: { latitude?: number; longitude?: number };
  destination?: { latitude?: number; longitude?: number };
  travelMode?: 'DRIVE' | 'WALK' | 'BICYCLE' | 'TRANSIT';
};

const app = new Hono<{ Bindings: CloudflareBindings }>();

app.use(
  '*',
  cors({
    origin: [
      'https://getkindl.ing',
      'http://localhost:4321',
      'http://127.0.0.1:4321',
    ],
  }),
);

app.get('/health', (c) => c.json({ ok: true }));

app.get('/places/:id', async (c) => {
  const place = await getPlaceDetails(c.req.param('id'), {
    GOOGLE_MAPS_API_KEY: c.env.GOOGLE_MAPS_API_KEY,
    PUBLIC_API_URL: c.env.PUBLIC_API_URL,
  });
  if (!place) return c.json({ error: 'Place not found' }, 404);
  c.header('Cache-Control', 'public, max-age=300, s-maxage=300');
  return c.json(place);
});

app.get('/places/:id/photo', async (c) => {
  const photo = await fetchPlacePhoto(c.req.param('id'), {
    GOOGLE_MAPS_API_KEY: c.env.GOOGLE_MAPS_API_KEY,
    PUBLIC_API_URL: c.env.PUBLIC_API_URL,
  });
  return photo ?? c.json({ error: 'Photo not found' }, 404);
});

app.post('/routes', async (c) => {
  const user = await userFromBearerToken(
    createSupabase(c.env),
    c.req.header('Authorization'),
  );
  if (user == null) return c.json({ error: 'Unauthorized' }, 401);

  const body = await c.req.json<RouteRequest>();
  const origin = body.origin;
  const destination = body.destination;
  if (
    origin?.latitude == null || origin.longitude == null
    || destination?.latitude == null || destination.longitude == null
  ) {
    return c.json({ error: 'Origin and destination are required' }, 400);
  }

  const travelMode = body.travelMode ?? 'DRIVE';
  let upstreamFailed = false;
  const route = await cachedJSON(
    'google-routes',
    JSON.stringify({ origin, destination, travelMode }),
    60,
    async () => {
      const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': c.env.GOOGLE_MAPS_API_KEY,
          'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters',
        },
        body: JSON.stringify({
          origin: { location: { latLng: origin } },
          destination: { location: { latLng: destination } },
          travelMode,
          ...(travelMode === 'DRIVE' ? { routingPreference: 'TRAFFIC_AWARE' } : {}),
        }),
      });

      if (!response.ok) {
        upstreamFailed = true;
        log('google_routes.request_failed', { status: response.status });
        return null;
      }

      const data = await response.json() as {
        routes?: Array<{ duration?: string; distanceMeters?: number }>;
      };
      return data.routes?.[0] ?? null;
    },
  );

  if (upstreamFailed) return c.json({ error: 'Route unavailable' }, 502);
  return route ? c.json(route) : c.json({ error: 'Route unavailable' }, 404);
});

app.get('/share/:id', async (c) => {
  const id = Number(c.req.param('id'));
  if (!Number.isInteger(id) || id <= 0) {
    return c.json({ error: 'Not found' }, 404);
  }

  let idea;
  try {
    idea = await getSharedIdea(createSupabase(c.env), id);
  } catch (err) {
    logError('share.fetch_failed', err, { idea_id: id });
    return c.json({ error: 'Failed to load idea' }, 500);
  }

  if (idea == null) {
    return c.json({ error: 'Not found' }, 404);
  }

  // Keep public share links in sync with the iOS detail view. Place data is
  // intentionally best-effort: an old/deleted Google place must not make an
  // otherwise valid share link disappear.
  let place = null;
  if (idea.place_id) {
    try {
      place = await getPlaceDetails(idea.place_id, {
        GOOGLE_MAPS_API_KEY: c.env.GOOGLE_MAPS_API_KEY,
        PUBLIC_API_URL: c.env.PUBLIC_API_URL,
      });
    } catch (err) {
      logError('share.place_fetch_failed', err, { idea_id: id, place_id: idea.place_id });
    }
  }

  try {
    await recordShareOpen(createSupabase(c.env), id);
  } catch (err) {
    // Analytics must never take down a public share page.
    logError('share.open_record_failed', err, { idea_id: id });
  }

  // The payload is public, but the request has an analytics side effect. Do
  // not let a browser or shared CDN cache suppress recordShareOpen calls.
  c.header('Cache-Control', 'private, no-store');
  return c.json({ ...idea, place });
});

app.delete('/account', async (c) => {
  const supabase = createSupabase(c.env);
  const user = await userFromBearerToken(
    supabase,
    c.req.header('Authorization'),
  );
  if (user == null) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const result = await wipeAccount(supabase, user.id);
  if (!result.ok) {
    logError('account.delete_failed', result.message, { user_id: user.id });
    return c.json({ error: 'Failed to delete account' }, 500);
  }

  return c.json({ ok: true });
});

async function streamExtractedIdeas(
  c: Parameters<typeof streamSSE>[0],
  extracted: ExtractionResult[],
  summary: {
    user_id: string | null;
    screenshots: number;
    ideas: number;
    inserted: number;
    reused: number;
    skipped: number;
    sensitive: number;
    dropped: number;
    failed: number;
    items: ItemLog[];
  },
  started: number,
) {
  const supabase = createSupabase(c.env);
  const googleMaps = {
    GOOGLE_MAPS_API_KEY: c.env.GOOGLE_MAPS_API_KEY,
    PUBLIC_API_URL: c.env.PUBLIC_API_URL,
  };
  const ai = createAI(c.env);

  return streamSSE(c, async (stream) => {
    await Promise.all(
      extracted.map(async (entry) => {
        try {
          const status = entry.data.status;
          if (status === 'skipped' || status === 'sensitive') {
            if (status === 'skipped') summary.skipped += 1;
            else summary.sensitive += 1;
            summary.items.push({
              status,
              reason: entry.data.reason,
              venue: entry.data.item?.venue ?? null,
            });
            await stream.writeSSE({
              data: JSON.stringify({ id: entry.id }),
              event: 'processed',
            });
            return;
          }

          const result = await processEntry(supabase, googleMaps, ai, entry);
          if (result.status === 'dropped') {
            summary.dropped += 1;
            summary.items.push({
              status: 'dropped',
              reason: result.reason,
              venue: result.venue,
            });
            return;
          }

          summary.ideas += 1;
          if (result.via === 'insert') summary.inserted += 1;
          else summary.reused += 1;
          summary.items.push({
            status: result.via === 'insert' ? 'inserted' : 'reused',
            via: result.via,
            idea_id: result.draft.idea_id,
            venue: result.draft.ideas.name,
            place_id: result.draft.ideas.place_id,
          });
          await stream.writeSSE({
            data: JSON.stringify(result.draft),
            event: 'idea',
          });
          await stream.writeSSE({
            data: JSON.stringify({ id: entry.id }),
            event: 'processed',
          });
        } catch (err) {
          summary.failed += 1;
          summary.items.push({
            status: 'failed',
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }),
    );

    log('ideas.done', { ...summary, ms: Date.now() - started });
    await stream.writeSSE({ event: 'done', data: '' });
    await stream.close();
  });
}

app.post('/ideas', async (c) => {
  const started = Date.now();
  const user_id = c.req.header('x-user-id') ?? null;
  const screenshots: Screenshot[] = await c.req.json();
  const summary = {
    user_id,
    screenshots: screenshots?.length ?? 0,
    ideas: 0,
    inserted: 0,
    reused: 0,
    skipped: 0,
    sensitive: 0,
    dropped: 0,
    failed: 0,
    items: [] as ItemLog[],
  };

  if (!screenshots || screenshots.length === 0) {
    log('ideas.done', { ...summary, ms: Date.now() - started });
    return c.json([], 200);
  }

  const ai = createAI(c.env);

  let extracted;
  try {
    extracted = await parseScreenshot(screenshots, ai);
  } catch (err) {
    logError('ideas.done', err, { ...summary, ms: Date.now() - started });
    throw err;
  }

  return streamExtractedIdeas(c, extracted, summary, started);
});

// Local inference keeps screenshot OCR on the device. The server receives only
// the structured extraction needed for Apple Maps enrichment and persistence.
app.post('/ideas/extracted', async (c) => {
  const started = Date.now();
  const user_id = c.req.header('x-user-id') ?? null;
  const extracted: ExtractionResult[] = await c.req.json();
  const summary = {
    user_id,
    screenshots: extracted?.length ?? 0,
    ideas: 0,
    inserted: 0,
    reused: 0,
    skipped: 0,
    sensitive: 0,
    dropped: 0,
    failed: 0,
    items: [] as ItemLog[],
  };

  if (!Array.isArray(extracted) || extracted.length === 0) {
    return c.json([], 200);
  }
  return streamExtractedIdeas(c, extracted, summary, started);
});

export default app;
