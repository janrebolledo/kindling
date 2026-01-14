import 'bun';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import OpenAI from 'openai';
import { parseScreenshotPrompt } from './prompts';

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
    }
  );
  const data = await response.json();

  return data;
}

const openai = new OpenAI({
  apiKey: Bun.env['OPEN_API_KEY'],
});

async function parseScreenshot(base64img: String) {
  const response = await openai.responses.create({
    model: 'gpt-4.1-mini',
    input: [
      // @ts-ignore
      {
        role: 'user',
        content: [
          { type: 'input_text', text: parseScreenshotPrompt },
          {
            type: 'input_image',
            image_url: base64img,
          },
        ],
      },
    ],
  });
  const data = JSON.parse(response.output_text);
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
    `${data.item.name} ${data.item.location} ${data.item.address}`
  );

  return c.json({ data, places });
});

export default app;
