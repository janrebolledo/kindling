-- Durable Google Places cache so the Worker can reuse search and details
-- responses instead of re-hitting Places on every card, pin, and screenshot.
-- Google Maps Platform terms allow caching Places content for up to 30 days;
-- the API refreshes rows after that. Place IDs may be stored indefinitely.

create table if not exists public.google_places (
  place_id text primary key,
  name text,
  latitude double precision,
  longitude double precision,
  formatted_address text,
  weekday_descriptions text[] not null default '{}',
  open_now boolean,
  photo_name text,
  photo_attributions text[] not null default '{}',
  photo_attribution_uris text[] not null default '{}',
  google_maps_uri text,
  fetched_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.google_place_searches (
  query_fingerprint text primary key,
  place_id text,
  has_photo boolean not null default false,
  fetched_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.google_places enable row level security;
alter table public.google_place_searches enable row level security;

revoke all on table public.google_places from anon, authenticated;
revoke all on table public.google_place_searches from anon, authenticated;

notify pgrst, 'reload schema';
