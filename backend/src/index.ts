import 'bun';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { GoogleGenAI } from '@google/genai';
import { createClient } from '@supabase/supabase-js';
import { parseScreenshot, ExtractionResult } from './utils/parseScreenshot';

const supabase = createClient(
  'https://bfbaqyhyxergcpsyhzcc.supabase.co',
  'sb_publishable_Q3wc-o2JVqIYPQVw47306w_zpKAE0VI',
);

export const ai = new GoogleGenAI({
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

const app = new Hono();

app.use('*', cors());

// TODO: rename this endpoint to something better lol
app.post('/ideas', async (c) => {
  console.log('POST /ideas');
  const screenshots: [{ id: string; text: string }] = await c.req.json();
  // console.log(screenshots);
  const aiLocationData = await Promise.all(
    screenshots.map(async (screenshot: { id: string; text: string }) => {
      return {
        id: screenshot.id,
        data: await parseScreenshot(screenshot.text),
      };
    }),
  );
  const searchTerms = aiLocationData
    .map((location) => location.data.item.venue)
    .join(' OR ');
  console.log(aiLocationData);

  // TODO: make database searching more thorough
  // reform prompt data to match database
  const { data, error } = await supabase
    .from('ideas')
    .select()
    .textSearch('venue', searchTerms, {
      type: 'websearch',
    });

  if (data && data?.length > 0) {
    console.log(data);
    return c.json(data);
  }
  if (error) {
    console.log(error);
  }

  const places = {};

  // const places = await getLocationDetails(
  //   `${aiLocationData[0].item.name} ${aiLocationData[0].item.location} ${aiLocationData[0].item.address}`,
  // );
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
