import type { SupabaseClient } from '@supabase/supabase-js';
import type { SharedIdea } from './types';

const SHARE_COLUMNS =
  'id, name, type, description, media_url, address, location, location_type, location_emoji, duration, venue, place_id, open_hours, created_at';

export async function getSharedIdea(
  supabase: SupabaseClient,
  id: number,
): Promise<SharedIdea | null> {
  const { data, error } = await supabase
    .from('ideas')
    .select(SHARE_COLUMNS)
    .eq('id', id)
    .maybeSingle();
  if (error || data == null) return null;
  return data;
}
