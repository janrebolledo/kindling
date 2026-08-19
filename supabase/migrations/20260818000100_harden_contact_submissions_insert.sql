drop policy if exists "Anyone can create contact submissions"
  on public.contact_submissions;

create policy "Anyone can create contact submissions"
  on public.contact_submissions
  for insert
  to anon, authenticated
  with check (
    status = 'new'
    and (
      (source = 'web' and user_id is null)
      or (source = 'ios' and user_id = (select auth.uid()))
    )
  );
