alter table public.ideas
  drop column if exists address,
  drop column if exists location,
  drop column if exists pricing,
  drop column if exists venue,
  drop column if exists open_hours;

notify pgrst, 'reload schema';
