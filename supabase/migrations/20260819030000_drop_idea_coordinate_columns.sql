-- Coordinates are resolved transiently through Google Places and are not persisted.
alter table public.ideas
  drop column if exists latitude,
  drop column if exists longitude;

notify pgrst, 'reload schema';
