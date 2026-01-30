import 'bun';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { GoogleGenAI } from '@google/genai';
import { createClient } from '@supabase/supabase-js';
import { parseScreenshot } from './utils/parseScreenshot';

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
          'places.id,places.displayName,places.formattedAddress,places.addressComponents,places.photos,places.generativeSummary,places.priceLevel',
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
  const aiLocationData = await parseScreenshot(JSON.stringify(screenshots));

  const results = await Promise.all(
    aiLocationData.map(async (entry) => {
      const { id, data } = entry;
      if (
        data.status != 'success' ||
        data.item == null ||
        data.item.venue == null
      ) {
        return;
      }

      const { data: matches, error } = await supabase
        .from('ideas')
        .select()
        .textSearch('venue', data.item.venue!, {
          type: 'websearch',
        });

      if (matches && matches.length > 0)
        return {
          id,
          data: matches[0],
          // error,
        };

      console.log('no matches found :( searching maps api');
      const mapsLocationData = await (
        await getLocationDetails(
          `${data.item.venue ?? ''} ${data.item.location ?? ''} ${data.item.address ?? ''}`,
        )
      ).places[0];

      // post this to supabase
      const newIdea = {
        // id: crypto.randomUUID(),
        // created_at: new Date().toISOString(),
        name: data.item.name ?? null,
        type: data.item.activity_type ?? null,
        // description: mapsLocationData.generativeSummary.overview.text,
        media_url: '', //figure this out pls
        address: mapsLocationData.formattedAddress,
        location: `${mapsLocationData.addressComponents[2].longText}, ${mapsLocationData.addressComponents[4].longText}`,
        location_type: '',
        duration: null,
        pricing: 0, // map the google 'inexpensive' tags to ints
        date: data.item.date ?? null,
        time: data.item.time ?? null,
        venue: mapsLocationData.displayName.text,
      };

      const { error: uploadError } = await supabase
        .from('ideas')
        .insert([newIdea]);

      return {
        id,
        data: newIdea,
        error: uploadError,
      };
    }),
  );

  return c.json(results.filter((i) => i != null));
});

app.get('/', async (c) => {
  return c.json([
    { response: 'helloooooo', id: 200 },
    { response: 'helloooooo', id: 202 },
  ]);
});

export default app;
