alter table public.ideas
  add column if not exists place_provider text;

-- Existing place_id values were produced by Google Places. New ingestion uses
-- Apple Maps Place IDs, so keep the provider explicit instead of interpreting
-- every opaque identifier as if it came from the same namespace.
update public.ideas
set place_provider = 'google'
where place_id is not null
  and place_provider is null;

alter table public.ideas
  add constraint ideas_place_provider_check
  check (place_provider is null or place_provider in ('apple', 'google'));

comment on column public.ideas.place_provider is
  'Provider namespace for the opaque place_id: apple or google.';

notify pgrst, 'reload schema';
