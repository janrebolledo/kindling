alter table public.google_places
  add column if not exists price_level text,
  add column if not exists price_level_fetched boolean not null default false;

notify pgrst, 'reload schema';
