import type { SupabaseClient } from '@supabase/supabase-js';
import { lookupPlace } from './places';
import type { ExtractedItem, ExtractionResult } from './utils/parseScreenshot';
import type { DraftCollectionItem, Idea, MapsPlace } from './types';

export type LinkedVia = 'place_id' | 'insert' | 'conflict';

export type ProcessResult =
  | { status: 'linked'; via: LinkedVia; draft: DraftCollectionItem }
  | { status: 'dropped'; reason: string; venue: string | null };

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

async function findIdeaByPlaceId(
  supabase: SupabaseClient,
  placeId: string,
): Promise<Idea | null> {
  const { data, error } = await supabase
    .from('ideas')
    .select()
    .eq('place_id', placeId)
    .maybeSingle();
  if (error) return null;
  return data;
}

async function getOrCreateIdeaForPlace(
  supabase: SupabaseClient,
  place: MapsPlace,
  image: string | null,
  item: ExtractedItem,
): Promise<{ idea: Idea; via: LinkedVia } | null> {
  const placeId = place.id!;
  const existing = await findIdeaByPlaceId(supabase, placeId);
  if (existing) return { idea: existing, via: 'place_id' };

  const newIdea = {
    // `item.venue` comes from the user's screenshot extraction, not Apple
    // Maps. Keep it as the app-owned display title now that venue is not a
    // persisted provider field.
    name: item.name ?? item.venue,
    type: item.tag,
    description: item.description ?? null,
    media_url: image,
    location_type: item.activity_type ?? null,
    location_emoji: item.activity_emoji ?? null,
    duration: null,
    date: item.date,
    time: item.time,
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
    const winner = await findIdeaByPlaceId(supabase, placeId);
    return winner ? { idea: winner, via: 'conflict' } : null;
  }
  if (uploadError || inserted == null) return null;
  return { idea: inserted, via: 'insert' };
}

export async function processEntry(
  supabase: SupabaseClient,
  appleMaps: Parameters<typeof lookupPlace>[1],
  entry: ExtractionResult,
): Promise<ProcessResult> {
  const { id, data } = entry;
  if (data.status != 'success' || data.item?.venue == null) {
    return {
      status: 'dropped',
      reason: data.reason ?? 'unusable_extraction',
      venue: data.item?.venue ?? null,
    };
  }

  const item = data.item;
  // The guard above guarantees a venue for successful extraction results.
  const venue = item.venue!;
  const location = item.location ?? '';
  const address = item.address ?? '';
  const query = `${venue} ${location} ${address}`.trim();

  const mapsData = await lookupPlace(query, appleMaps, {
    entry_id: id,
    venue,
  });

  if (mapsData?.place.id) {
    const created = await getOrCreateIdeaForPlace(
      supabase,
      mapsData.place,
      mapsData.image,
      item,
    );
    if (created == null) {
      return { status: 'dropped', reason: 'insert_failed', venue };
    }
    return {
      status: 'linked',
      via: created.via,
      draft: toDraft(created.idea, id, item),
    };
  }

  return {
    status: 'dropped',
    reason: 'apple_maps_miss',
    venue,
  };
}
