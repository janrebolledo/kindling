import type { SupabaseClient } from '@supabase/supabase-js';
import { cachedJSON } from './cache';
import type { SharedIdea } from './types';

const SHARE_COLUMNS =
  'id, name, type, description, media_url, location_type, location_emoji, duration, date, time, place_id, created_at';

// These columns are shared by the old and current ideas schemas. Keep this
// projection as a compatibility path while PostgREST refreshes after a
// migration, so a new optional field cannot take down existing share links.
const COMPATIBLE_SHARE_COLUMNS =
  'id, name, type, description, media_url, location_type, duration, place_id, created_at';

function isSchemaMismatch(error: { code?: string; message?: string }): boolean {
  return (
    error.code === '42703' ||
    error.code === 'PGRST204' ||
    /column .* does not exist|could not find the .* column .* in the schema cache/i.test(
      error.message ?? '',
    )
  );
}

export async function getSharedIdea(
  supabase: SupabaseClient,
  id: number,
): Promise<SharedIdea | null> {
  return cachedJSON('shared-ideas', String(id), 60, async () => {
    const result = await supabase
      .from('ideas')
      .select(SHARE_COLUMNS)
      .eq('id', id)
      .maybeSingle();

    if (result.error && isSchemaMismatch(result.error)) {
      const compatible = await supabase
        .from('ideas')
        .select(COMPATIBLE_SHARE_COLUMNS)
        .eq('id', id)
        .maybeSingle();

      if (compatible.error) throw compatible.error;
      if (compatible.data == null) return null;

      return {
        ...compatible.data,
        location_emoji: null,
        date: null,
        time: null,
      };
    }

    if (result.error) throw result.error;
    if (result.data == null) return null;
    return result.data;
  });
}

/** Records a public share-link open for every account that owns the idea. */
export async function recordShareOpen(
  supabase: SupabaseClient,
  ideaId: number,
): Promise<void> {
  const { data: owners, error: ownersError } = await supabase
    .from('collection_items')
    .select('user_id')
    .eq('idea_id', ideaId);

  if (ownersError) throw ownersError;

  const ownerIds = [...new Set((owners ?? []).map((row) => row.user_id))];
  if (ownerIds.length === 0) return;

  const { error: insertError } = await supabase
    .from('idea_share_opens')
    .insert(
      ownerIds.map((owner_user_id) => ({
        idea_id: ideaId,
        owner_user_id,
      })),
    );

  if (insertError) throw insertError;
}
