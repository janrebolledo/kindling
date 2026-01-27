import 'bun';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { GoogleGenAI } from '@google/genai';
import { parseScreenshotPrompt } from './prompts';
import { encodeBase64 } from './utils/encodeBase64';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  'https://bfbaqyhyxergcpsyhzcc.supabase.co',
  'sb_publishable_Q3wc-o2JVqIYPQVw47306w_zpKAE0VI',
);

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

async function parseScreenshot(base64img: string) {
  console.log('req started');
  const ai = new GoogleGenAI({
    apiKey: Bun.env['GEMINI_API_KEY'],
  });
  const base64Data = base64img.replace(/^data:image\/\w+;base64,/, '');

  const result = await ai.models.generateContent({
    model: 'gemini-2.5-flash-lite-preview-09-2025',
    contents: [
      {
        role: 'user',
        parts: [
          {
            inlineData: {
              mimeType: 'image/png',
              data: base64Data,
            },
          },
          {
            text: parseScreenshotPrompt,
          },
        ],
      },
    ],
  });
  const data = JSON.parse(result.text || '[]');
  return data;
}

const app = new Hono();

app.use('*', cors());

app.post('/', async (c) => {
  const body = await c.req.parseBody();
  const file = body['file'];

  if (!file || !(file instanceof File)) {
    return c.json({ error: 'No file uploaded' }, 400);
  }

  console.log(file);

  const base64Img = await encodeBase64(file);

  const aiLocationData = await parseScreenshot(base64Img);

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
  // const locationData = await getLocationDetails('eucalyptus trail chino hills');
  // return c.json(locationData);
  return c.json([
    { response: 'helloooooo', id: 200 },
    { response: 'helloooooo', id: 202 },
  ]);
});

export default app;
