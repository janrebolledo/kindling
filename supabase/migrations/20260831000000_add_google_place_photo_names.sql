alter table public.google_places
  add column if not exists photo_names text[] not null default '{}';

notify pgrst, 'reload schema';
