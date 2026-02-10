import 'bun';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { GoogleGenAI } from '@google/genai';
import { createClient } from '@supabase/supabase-js';
import { parseScreenshot } from './utils/parseScreenshot';
import { mapPriceLevelToInt } from './utils/mapPriceLevelToInt';
import { generateUniqueId } from './utils/generateUniqueId';

const supabase = createClient(
  'https://bfbaqyhyxergcpsyhzcc.supabase.co',
  Bun.env['SUPABASE_API_KEY']!,
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

  if (data.places == undefined) {
    return null;
  }

  if (data.places[0].photos == undefined) {
    return { data, image: null };
  }

  const image = (
    await fetch(
      `https://places.googleapis.com/v1/${data.places[0].photos[0].name}/media?key=${Bun.env['GOOGLE_MAPS_API_KEY']}&maxHeightPx=1600`,
      {
        method: 'GET',
        // @ts-ignore
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': Bun.env['GOOGLE_MAPS_API_KEY'],
        },
      },
    )
  ).url;

  return { data, image };
}

const app = new Hono();

app.use('*', cors());

// TODO: rename this endpoint to something better lol
app.post('/ideas', async (c) => {
  console.log('POST /ideas');
  const screenshots: [{ id: string; text: string }] = await c.req.json();
  const aiLocationData = await parseScreenshot(JSON.stringify(screenshots));

  // todo: implement edge workers, database/api racing, & streaming response
  const results = await Promise.all(
    aiLocationData.map(async (entry) => {
      const { id, data } = entry;
      if (
        data == null ||
        data.status != 'success' ||
        data.item == null ||
        data.item.venue == null
      ) {
        return;
      }
      console.log(data);

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
          error,
        };

      console.log('no matches found :( searching maps api');
      const mapsData = await getLocationDetails(
        `${data.item.venue ?? ''} ${data.item.location ?? ''} ${data.item.address ?? ''}`,
      );
      const mapsLocationData = mapsData?.data.places[0];

      const city = mapsLocationData.addressComponents.filter(
        (i: {
          longText: string;
          shortText: string;
          types: [string];
          languageCode: string;
        }) => i.types.includes('locality') && i.types.includes('political'),
      )[0].longText;
      const state = mapsLocationData.addressComponents.filter(
        (i: {
          longText: string;
          shortText: string;
          types: [string];
          languageCode: string;
        }) =>
          i.types.includes('administrative_area_level_1') &&
          i.types.includes('political'),
      )[0].longText;

      const newIdea = {
        id: generateUniqueId(),
        name: data.item.name ?? null,
        type: data.item.tag ?? null,
        description: mapsLocationData.generativeSummary
          ? mapsLocationData.generativeSummary.overview.text
          : data.item.description,
        media_url: mapsData?.image ?? null,
        address: mapsLocationData.formattedAddress,
        location: `${city}, ${state}`,
        location_type: data.item.activity_type ?? null,
        duration: null,
        pricing: mapPriceLevelToInt(mapsLocationData.priceLevel),
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

export default app;
