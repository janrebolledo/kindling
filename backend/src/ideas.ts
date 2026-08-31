import type { SupabaseClient } from '@supabase/supabase-js';
import type { AIClient } from './clients';
import { isDistanceBasedActivity, lookupActivityDetails, type ActivityDetails } from './activity';
import { lookupPlace, getPlaceDetails, type GoogleMapsCredentials } from './places';
import { logError } from './log';
import type { ExtractedItem, ExtractionResult } from './utils/parseScreenshot';
import type { DraftCollectionItem, Idea, MapsPlace } from './types';

export type LinkedVia = 'place_id' | 'insert' | 'conflict';

export type ProcessResult =
  | { status: 'linked'; via: LinkedVia; draft: DraftCollectionItem }
  | { status: 'dropped'; reason: string; venue: string | null };

function cleanSearchPart(value: string | null | undefined): string {
  return value?.replace(/\s+/g, ' ').trim() ?? '';
}

/**
 * OCR-derived context is useful for ranking, but it is not always searchable
 * as a single phrase. For example, a map card can expose a mall name
 * without the city, or include a noisy address fragment. Keep the full query
 * first, then relax only the context so a real venue is not dropped outright.
 */
export function buildPlaceQueries(item: ExtractedItem): string[] {
  const venue = cleanSearchPart(item.venue);
  const location = cleanSearchPart(item.location);
  const address = cleanSearchPart(item.address);
  const candidates = [
    [venue, location, address],
    [venue, address],
    [venue, location],
    [venue],
  ].map((parts) => parts.filter(Boolean).join(' ').trim());

  return [...new Set(candidates)].filter(Boolean);
}

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
  if (error) {
    logError('ideas.lookup_failed', error, { place_id: placeId });
    return null;
  }
  return data;
}

async function getOrCreateIdeaForPlace(
  supabase: SupabaseClient,
  googleMaps: GoogleMapsCredentials,
  place: MapsPlace,
  image: string | null,
  item: ExtractedItem,
  ai: AIClient,
): Promise<{ idea: Idea; via: LinkedVia } | null> {
  const placeId = place.id!;
  const existing = await findIdeaByPlaceId(supabase, placeId);
  if (existing) {
    if (isDistanceBasedActivity(item)) {
      const needsLookup = existing.distance_miles == null
        || (existing.completion_time == null && existing.duration == null);
      const details = needsLookup ? await lookupActivityDetails(ai, item) : null;
      const completionTime = details?.completion_time ?? existing.completion_time ?? existing.duration;
      const updates: Partial<ActivityDetails> & { duration?: string | null } = {};
      if (existing.distance_miles == null && details?.distance_miles != null) {
        updates.distance_miles = details.distance_miles;
      }
      if (existing.completion_time == null && completionTime != null) {
        updates.completion_time = completionTime;
      }
      if (existing.duration == null && completionTime != null) {
        updates.duration = completionTime;
      }
      if (Object.values(updates).some((value) => value != null)) {
        const { data: updated, error: updateError } = await supabase
          .from('ideas')
          .update(updates)
          .eq('id', existing.id)
          .select()
          .single();
        if (updated) return { idea: updated, via: 'place_id' };
        if (updateError) {
          logError('ideas.activity_details_update_failed', updateError, {
            idea_id: existing.id,
          });
        }
      }
    }
    return { idea: existing, via: 'place_id' };
  }

  const [activityDetails, placeDetails] = await Promise.all([
    lookupActivityDetails(ai, item),
    getPlaceDetails(placeId, googleMaps, supabase),
  ]);

  const newIdea = {
    // `item.venue` comes from the user's screenshot extraction, not Apple
    // Maps. Keep it as the app-owned display title now that venue is not a
    // persisted provider field.
    name: item.name ?? item.venue,
    type: item.tag,
    description: item.description ?? null,
    media_url: placeDetails?.photoUrl ?? image,
    location_type: item.activity_type ?? null,
    location_emoji: item.activity_emoji ?? null,
    // Keep the legacy field populated while newer clients use the canonical
    // activity fields. This also makes metrics visible to older app builds.
    duration: activityDetails?.completion_time ?? null,
    distance_miles: activityDetails?.distance_miles ?? null,
    completion_time: activityDetails?.completion_time ?? null,
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
  if (uploadError || inserted == null) {
    if (uploadError) {
      logError('ideas.insert_failed', uploadError, {
        place_id: placeId,
        has_activity_details: activityDetails != null,
      });
    }
    return null;
  }
  return { idea: inserted, via: 'insert' };
}

export async function processEntry(
  supabase: SupabaseClient,
  googleMaps: GoogleMapsCredentials,
  ai: AIClient,
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
  let mapsData: Awaited<ReturnType<typeof lookupPlace>> = null;
  for (const query of buildPlaceQueries(item)) {
    mapsData = await lookupPlace(query, googleMaps, {
      entry_id: id,
      venue,
    });
    if (mapsData?.place.id) break;
  }

  if (mapsData?.place.id) {
    const created = await getOrCreateIdeaForPlace(
      supabase,
      googleMaps,
      mapsData.place,
      mapsData.image,
      item,
      ai,
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
    reason: 'google_places_miss',
    venue,
  };
}
