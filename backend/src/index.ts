import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { cors } from 'hono/cors';
import { createAI, createSupabase } from './clients';
import { userFromBearerToken, wipeAccount } from './deleteAccount';
import { processEntry } from './ideas';
import { log, logError } from './log';
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

  try {
    await recordShareOpen(createSupabase(c.env), id);
  } catch (err) {
    // Analytics must never take down a public share page.
    logError('share.open_record_failed', err, { idea_id: id });
  }

  c.header('Cache-Control', 'public, max-age=60');
  return c.json(idea);
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
  const appleMaps = {
    APPLE_MAPS_TEAM_ID: c.env.APPLE_MAPS_TEAM_ID,
    APPLE_MAPS_KEY_ID: c.env.APPLE_MAPS_KEY_ID,
    APPLE_MAPS_PRIVATE_KEY: c.env.APPLE_MAPS_PRIVATE_KEY,
  };

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

          const result = await processEntry(supabase, appleMaps, entry);
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
