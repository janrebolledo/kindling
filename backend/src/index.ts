import 'bun';
import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { cors } from 'hono/cors';
import { GoogleGenAI } from '@google/genai';
import { createClient } from '@supabase/supabase-js';
import {
  parseScreenshot,
  type ExtractedItem,
  type ExtractionResult,
} from './utils/parseScreenshot';
import { mapPriceLevelToInt } from './utils/mapPriceLevelToInt';

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

// The enriched, user-agnostic shape of a collection_item. The client caches
// these locally during onboarding and inserts them client-side at signup, where
// user_id and collection_id are attached. `ideas` carries the full idea row for
// display; highlights/highlights_sources are per-screenshot enrichment that
// belongs on the user's collection_item.
type Idea = {
  id: number;
  created_at: string;
  name: string | null;
  type: string | null;
  description: string | null;
  media_url: string | null;
  address: string | null;
  location: string | null;
  location_type: string | null;
  duration: string | null;
  pricing: number | null;
  date: string | null;
  time: string | null;
  venue: string | null;
  place_id: string | null;
  open_hours: string[] | null;
};

type DraftCollectionItem = {
  id: number;
  local_id: string;
  idea_id: number;
  highlights: string | null;
  highlights_sources: string[] | null;
  ideas: Idea;
};

type MapsPlace = {
  id?: string;
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

function toDraft(
  idea: Idea,
  localId: string,
  item: ExtractedItem,
): DraftCollectionItem {
  return {
    id: idea.id,
    local_id: localId,
    idea_id: idea.id,
    highlights: item.highlights,
    highlights_sources: item.highlights_sources,
    ideas: idea,
  };
}

function locationLabel(place: MapsPlace): string | null {
  const city =
    place.addressComponents?.find(
      (i) => i.types?.includes('locality') && i.types?.includes('political'),
    )?.longText ?? '';
  const state =
    place.addressComponents?.find(
      (i) =>
        i.types?.includes('administrative_area_level_1') &&
        i.types?.includes('political'),
    )?.longText ?? '';
  return `${city}${city && state ? ', ' : ''}${state}`.trim() || null;
}

async function findIdeaByPlaceId(placeId: string): Promise<Idea | null> {
  const { data, error } = await supabase
    .from('ideas')
    .select()
    .eq('place_id', placeId)
    .maybeSingle();
  if (error) {
    console.error('place_id lookup failed', error);
    return null;
  }
  return data;
}

async function getOrCreateIdeaForPlace(
  place: MapsPlace,
  image: string | null,
  item: ExtractedItem,
): Promise<Idea | null> {
  const placeId = place.id!;
  const existing = await findIdeaByPlaceId(placeId);
  if (existing) return existing;

  const location = locationLabel(place);
  const venue = place.displayName?.text ?? item.venue;
  const address = place.formattedAddress ?? null;

  const newIdea = {
    name: item.name,
    type: item.tag,
    description:
      place.generativeSummary?.overview?.text ?? item.description ?? null,
    media_url: image,
    address,
    location,
    location_type: item.activity_type,
    duration: null,
    pricing: mapPriceLevelToInt(place.priceLevel ?? 'PRICE_LEVEL_UNSPECIFIED'),
    date: item.date,
    time: item.time,
    venue,
    open_hours: place.currentOpeningHours?.weekdayDescriptions ?? null,
    place_id: placeId,
  };

  // `ideas.id` is a Postgres identity column, so let the database generate it
  // and return the inserted row. Never stream an idea we failed to persist,
  // otherwise the client's collection_items insert violates the idea_id
  // foreign key.
  const { data: inserted, error: uploadError } = await supabase
    .from('ideas')
    .insert([newIdea])
    .select()
    .single();

  if (uploadError?.code === '23505') {
    return findIdeaByPlaceId(placeId);
  }
  if (uploadError || inserted == null) {
    console.error('idea insert failed', uploadError);
    return null;
  }
  return inserted;
}

async function processEntry(
  entry: ExtractionResult,
): Promise<DraftCollectionItem | undefined> {
  const { id, data } = entry;
  if (data.status != 'success' || data.item?.venue == null) {
    return undefined;
  }
  const item = data.item;
  const venue = item.venue;
  const location = item.location ?? '';
  const address = item.address ?? '';
  const query = `${venue} ${location} ${address}`.trim();

  // Places is the identity; FTS is only a fallback when Places misses.
  const [supabaseResult, mapsData] = await Promise.all([
    supabase
      .from('ideas')
      .select()
      .textSearch('venue', venue, { type: 'websearch' }),
    getLocationDetails(query),
  ]);

  const place = mapsData?.data?.places?.[0] as MapsPlace | undefined;
  if (place?.id) {
    const idea = await getOrCreateIdeaForPlace(
      place,
      mapsData?.image ?? null,
      item,
    );
    if (idea == null) return undefined;
    return toDraft(idea, id, item);
  }

  const { data: matches, error } = supabaseResult;
  if (error) {
    console.error('venue textSearch failed', error);
  }
  if (matches && matches.length > 0) {
    return toDraft(matches[0], id, item);
  }

  return undefined;
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
          const status = entry.data.status;
          if (status === 'skipped' || status === 'sensitive') {
            await stream.writeSSE({
              data: JSON.stringify({ id: entry.id }),
              event: 'processed',
            });
            return;
          }

          const result = await processEntry(entry);
          if (result != null) {
            await stream.writeSSE({
              data: JSON.stringify(result),
              event: 'idea',
            });
            await stream.writeSSE({
              data: JSON.stringify({ id: entry.id }),
              event: 'processed',
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
