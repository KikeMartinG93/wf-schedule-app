-- WF Schedule · Supabase shift backups
-- Paste into the Supabase SQL editor once per project.
-- Then enable Email auth (Authentication → Providers → Email).
-- For sideload UX, turn off "Confirm email" under Email provider settings.

create table if not exists public.shifts (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  ukg_record_id text,
  date timestamptz not null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  job text not null,
  location text,
  kind text not null,
  pay_code text,
  notes text,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists shifts_user_start_time_idx
  on public.shifts (user_id, start_time);

alter table public.shifts enable row level security;

drop policy if exists "shifts_select_own" on public.shifts;
create policy "shifts_select_own"
  on public.shifts for select
  using (auth.uid() = user_id);

drop policy if exists "shifts_insert_own" on public.shifts;
create policy "shifts_insert_own"
  on public.shifts for insert
  with check (auth.uid() = user_id);

drop policy if exists "shifts_update_own" on public.shifts;
create policy "shifts_update_own"
  on public.shifts for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "shifts_delete_own" on public.shifts;
create policy "shifts_delete_own"
  on public.shifts for delete
  using (auth.uid() = user_id);

-- Upserts from the app use onConflict = user_id,id
grant select, insert, update, delete on public.shifts to authenticated;
