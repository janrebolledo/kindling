import 'bun';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { GoogleGenAI } from '@google/genai';
import { parseScreenshotPrompt } from './prompts';

// TODO: import user location data and try and query to what's closest to them
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

  // Convert file to ArrayBuffer then to base64
  const arrayBuffer = await file.arrayBuffer();
  const bytes = new Uint8Array(arrayBuffer);

  // Convert bytes to base64
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  const base64 = btoa(binary);

  // Create data URL with mime type
  const dataUrl = `data:${file.type};base64,${base64}`;
  const data = await parseScreenshot(dataUrl);

  const places = await getLocationDetails(
    `${data.item.name} ${data.item.location} ${data.item.address}`,
  );

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
