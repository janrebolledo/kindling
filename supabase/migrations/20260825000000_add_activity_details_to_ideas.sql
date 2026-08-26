alter table public.ideas
  add column if not exists distance_miles numeric,
  add column if not exists completion_time text;

alter table public.ideas
  drop constraint if exists ideas_distance_miles_nonnegative;

alter table public.ideas
  add constraint ideas_distance_miles_nonnegative
  check (distance_miles is null or distance_miles >= 0);

notify pgrst, 'reload schema';
