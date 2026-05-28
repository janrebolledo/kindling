import 'bun';
import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
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
        'places.id,places.displayName,places.formattedAddress,places.addressComponents,places.photos,places.generativeSummary,places.priceLevel,places.currentOpeningHours',
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

app.use('*', async (c, next) => {
  const start = Date.now();
  await next();
  const ms = Date.now() - start;
  console.log(`${c.req.method} ${c.req.path} ${ms}ms`);
});

type IdeaResult = {
  id: number;
  local_id: string;
  ideas: Record<string, unknown>;
  error?: unknown;
};

async function processEntry(entry: {
  id: string;
  data: unknown;
}): Promise<IdeaResult | undefined> {
  const { id, data } = entry;
  if (
    data == null ||
    (data as { status?: string }).status != 'success' ||
    (data as { item?: { venue?: string } }).item == null ||
    (data as { item?: { venue?: string } }).item!.venue == null
  ) {
    return undefined;
  }
  const item = (data as { item: Record<string, unknown> }).item;
  const venue = (item.venue ?? '') as string;
  const location = (item.location ?? '') as string;
  const address = (item.address ?? '') as string;
  const query = `${venue} ${location} ${address}`.trim();

  // Database/API racing: run Supabase and Maps in parallel
  const [supabaseResult, mapsData] = await Promise.all([
    supabase
      .from('ideas')
      .select()
      .textSearch('venue', venue, { type: 'websearch' }),
    getLocationDetails(query),
  ]);

  const { data: matches, error } = supabaseResult;
  if (matches && matches.length > 0) {
    const existing = matches[0] as Record<string, unknown>;
    // Backfill open_hours on cached records that predate the column
    if (existing.open_hours == null && mapsData?.data?.places?.[0]) {
      const hours =
        (mapsData.data.places[0] as { currentOpeningHours?: { weekdayDescriptions?: string[] } })
          .currentOpeningHours?.weekdayDescriptions ?? null;
      if (hours) {
        await supabase.from('ideas').update({ open_hours: hours }).eq('id', existing.id);
        existing.open_hours = hours;
      }
    }
    return {
      id: matches[0].id,
      local_id: id,
      ideas: existing,
      error,
    };
  }

  if (!mapsData?.data?.places?.[0]) {
    return undefined;
  }
  const mapsLocationData = mapsData.data.places[0] as {
    addressComponents: Array<{
      longText: string;
      types: string[];
    }>;
    generativeSummary?: { overview?: { text?: string } };
    formattedAddress?: string;
    priceLevel?: string;
    displayName?: { text?: string };
    currentOpeningHours?: { weekdayDescriptions?: string[] };
  };
  const cityComp = mapsLocationData.addressComponents?.find(
    (i) => i.types?.includes('locality') && i.types?.includes('political'),
  );
  const stateComp = mapsLocationData.addressComponents?.find(
    (i) =>
      i.types?.includes('administrative_area_level_1') &&
      i.types?.includes('political'),
  );
  const city = cityComp?.longText ?? '';
  const state = stateComp?.longText ?? '';

  const newIdea = {
    id: generateUniqueId(),
    name: (item.name as string | null) ?? null,
    type: (item.tag as string | null) ?? null,
    description:
      mapsLocationData.generativeSummary?.overview?.text ??
      (item.description as string | null) ??
      null,
    media_url: mapsData?.image ?? null,
    address: mapsLocationData.formattedAddress ?? null,
    location: `${city}${city && state ? ', ' : ''}${state}`.trim() || null,
    location_type: (item.activity_type as string | null) ?? null,
    duration: null,
    pricing: mapPriceLevelToInt(
      mapsLocationData.priceLevel ?? 'PRICE_LEVEL_UNSPECIFIED',
    ),
    date: (item.date as string | null) ?? null,
    time: (item.time as string | null) ?? null,
    venue: mapsLocationData.displayName?.text ?? (item.venue as string) ?? null,
    highlights: (item.highlights as string | null) ?? null,
    highlights_sources: (item.highlights_sources as string[] | null) ?? null,
    open_hours: mapsLocationData.currentOpeningHours?.weekdayDescriptions ?? null,
  };

  const { error: uploadError } = await supabase.from('ideas').insert([newIdea]);
  return {
    id: generateUniqueId(),
    local_id: id,
    ideas: newIdea as Record<string, unknown>,
    error: uploadError,
  };
}

// TODO: rename this endpoint to something better lol
app.post('/ideas', async (c) => {
  console.log('POST /ideas');
  const screenshots: [{ id: string; text: string }] = await c.req.json();
  if (!screenshots || screenshots.length === 0) return c.json([], 200);
  const aiLocationData = await parseScreenshot(JSON.stringify(screenshots));

  return streamSSE(c, async (stream) => {
    await Promise.all(
      aiLocationData.map(async (entry) => {
        try {
          const result = await processEntry(entry);
          if (result != null) {
            await stream.writeSSE({
              data: JSON.stringify(result),
              event: 'idea',
            });
          }
        } catch (err) {
          console.error('processEntry error', err);
        }
      }),
    );
    await stream.writeSSE({ event: 'done', data: '' });
    await stream.close();
  });
});

export default app;
