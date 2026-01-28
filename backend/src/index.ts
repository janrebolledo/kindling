import 'bun';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { GoogleGenAI } from '@google/genai';
import { parseScreenshotPrompt } from './prompts';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  'https://bfbaqyhyxergcpsyhzcc.supabase.co',
  'sb_publishable_Q3wc-o2JVqIYPQVw47306w_zpKAE0VI',
);

const ai = new GoogleGenAI({
  apiKey: Bun.env['GEMINI_API_KEY'],
});

async function getLocationDetails(textQuery: String) {
  const response = await fetch(
    'https://places.googleapis.com/v1/places:searchText?pageSize=1',
    {
      body: JSON.stringify({ textQuery }),
      method: 'POST',
      // @ts-ignore
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-FieldMask':
          'places.id,places.displayName,places.addressComponents,places.location,places.photos,places.generativeSummary,places.reviewSummary',
        'X-Goog-Api-Key': Bun.env['GOOGLE_MAPS_API_KEY'],
      },
    },
  );
  const data = await response.json();

  return data;
}

async function parseScreenshot(text: string) {
  console.log('req started');

  const response = await ai.models.generateContent({
    model: 'gemini-2.5-flash-lite-preview-09-2025',
    contents: parseScreenshotPrompt + text,
  });

  const data = JSON.parse(response.text || '[]');
  return data;
}

const app = new Hono();

app.use('*', cors());

// TODO: rename this endpoint to something better lol
app.post('/v2/places', async (c) => {
  const body = (await c.req.json()).entries;
  // TODO: make prompt better
  const aiLocationData = await parseScreenshot(body);

  console.log(aiLocationData);

  // TODO: make database searching more thorough
  // reform prompt data to match database
  const { data, error } = await supabase
    .from('ideas')
    .select()
    .textSearch('title', `${aiLocationData.item.location}`, {
      type: 'websearch',
    });

  if (data && data?.length > 0) {
    console.log(data);
    return c.json(data);
  }
  if (error) {
    console.log(error);
  }

  const places = await getLocationDetails(
    `${aiLocationData.item.name} ${aiLocationData.item.location} ${aiLocationData.item.address}`,
  );
  // save query to supabase

  console.log({ data, places });

  return c.json({ data, places });
});

app.get('/', async (c) => {
  return c.json([
    { response: 'helloooooo', id: 200 },
    { response: 'helloooooo', id: 202 },
  ]);
});

export default app;
