import 'bun';
import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { cors } from 'hono/cors';
import { supabase } from './clients';
import { userFromBearerToken, wipeAccount } from './deleteAccount';
import { processEntry } from './ideas';
import { log, logError } from './log';
import type { Screenshot } from './types';
import { parseScreenshot } from './utils/parseScreenshot';

type ItemLog = {
  status: string;
  reason?: string | null;
  venue?: string | null;
  via?: string;
  idea_id?: number;
  place_id?: string | null;
  error?: string;
};

const app = new Hono();

app.use('*', cors());

app.delete('/account', async (c) => {
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

  let extracted;
  try {
    extracted = await parseScreenshot(screenshots);
  } catch (err) {
    logError('ideas.done', err, { ...summary, ms: Date.now() - started });
    throw err;
  }

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

          const result = await processEntry(entry);
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
            venue: result.draft.ideas.venue,
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
});

export default app;
