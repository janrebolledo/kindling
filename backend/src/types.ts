export type Idea = {
  id: number;
  created_at: string;
  name: string | null;
  type: string | null;
  description: string | null;
  media_url: string | null;
  location_type: string | null;
  location_emoji: string | null;
  duration: string | null;
  distance_miles: number | null;
  completion_time: string | null;
  date: string | null;
  time: string | null;
  place_id: string | null;
};

// The enriched, user-agnostic shape of a collection_item. The client caches
// these locally during onboarding and inserts them client-side at signup, where
// user_id and collection_id are attached. `ideas` carries the full idea row for
// display; highlights/highlights_sources are per-screenshot enrichment that
// belongs on the user's collection_item.
export type DraftCollectionItem = {
  id: number;
  local_id: string;
  idea_id: number;
  highlights: string | null;
  highlights_sources: string[] | null;
  ideas: Idea;
};

export type MapsPlace = {
  id?: string;
};

export type Screenshot = {
  id: string;
  text: string;
};

/** Public fields returned by GET /share/:id for the web funnel. */
export type SharedIdea = Pick<
  Idea,
  | 'id'
  | 'name'
  | 'type'
  | 'description'
  | 'media_url'
  | 'location_type'
  | 'location_emoji'
  | 'duration'
  | 'distance_miles'
  | 'completion_time'
  | 'place_id'
  | 'date'
  | 'time'
  | 'created_at'
>;
