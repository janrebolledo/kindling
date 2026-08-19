-- Preserve the place title extracted from the user's screenshot in the
-- app-owned `name` field before removing the legacy provider-shaped column.
update public.ideas
set name = coalesce(nullif(name, ''), venue)
where venue is not null;

alter table public.ideas
  drop column if exists address,
  drop column if exists location,
  drop column if exists pricing,
  drop column if exists venue,
  drop column if exists open_hours;

notify pgrst, 'reload schema';
