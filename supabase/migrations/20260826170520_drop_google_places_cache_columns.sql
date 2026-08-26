-- Places are stored once when an idea is created, not as a TTL cache.
-- Drop leftover cache-shaped columns that the API no longer reads or writes.

alter table public.google_places
  drop column if exists open_now,
  drop column if exists fetched_at;

alter table public.google_place_searches
  drop column if exists has_photo,
  drop column if exists fetched_at;

notify pgrst, 'reload schema';
