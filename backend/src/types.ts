export type Idea = {
  id: number;
  created_at: string;
  name: string | null;
  type: string | null;
  description: string | null;
  media_url: string | null;
  address: string | null;
  location: string | null;
  location_type: string | null;
  location_emoji: string | null;
  duration: string | null;
  pricing: number | null;
  date: string | null;
  time: string | null;
  venue: string | null;
  place_id: string | null;
  open_hours: string[] | null;
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
  name?: string;
  formattedAddress?: string;
  structuredAddress?: {
    administrativeArea?: string;
    administrativeAreaCode?: string;
    locality?: string;
    postCode?: string;
    subLocality?: string;
    thoroughfare?: string;
    subThoroughfare?: string;
  };
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
  | 'address'
  | 'location'
  | 'location_type'
  | 'location_emoji'
  | 'duration'
  | 'venue'
  | 'place_id'
  | 'open_hours'
  | 'created_at'
>;
