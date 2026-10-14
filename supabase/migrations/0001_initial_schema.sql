-- STRYDE initial database schema
-- Apply this file in Supabase SQL Editor or through Supabase migrations.
-- Security model: all exposed tables use RLS; admin privileges are granted only
-- by a trusted project owner through the Supabase dashboard, never by clients.

create extension if not exists pgcrypto;

create type public.app_role as enum ('player', 'admin');
create type public.tournament_status as enum ('draft', 'upcoming', 'registration_open', 'in_progress', 'completed', 'cancelled');
create type public.registration_status as enum ('pending', 'confirmed', 'rejected', 'withdrawn');
create type public.match_status as enum ('scheduled', 'live', 'completed', 'cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 3 and 24),
  display_name text,
  avatar_url text,
  region text not null default 'NG',
  role public.app_role not null default 'player',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.squads (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 40),
  tag text not null unique check (char_length(tag) between 2 and 6),
  description text,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.squad_members (
  squad_id uuid not null references public.squads(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  member_role text not null default 'member' check (member_role in ('captain', 'member')),
  joined_at timestamptz not null default now(),
  primary key (squad_id, user_id)
);

create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 100),
  slug text not null unique,
  game text not null default 'Blood Strike',
  mode text not null default 'Squad',
  description text,
  rules text,
  region text not null default 'NG',
  status public.tournament_status not null default 'draft',
  format text not null default 'single_elimination',
  max_teams integer not null default 16 check (max_teams between 2 and 512),
  team_size integer not null default 4 check (team_size between 1 and 10),
  prize_currency text not null default 'NGN',
  prize_pool_minor bigint not null default 0 check (prize_pool_minor >= 0),
  registration_opens_at timestamptz,
  registration_closes_at timestamptz,
  starts_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (registration_closes_at is null or registration_opens_at is null or registration_closes_at > registration_opens_at)
);

create table public.registrations (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  squad_id uuid not null references public.squads(id) on delete restrict,
  captain_id uuid not null references public.profiles(id) on delete restrict,
  status public.registration_status not null default 'pending',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tournament_id, squad_id)
);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  round_number integer not null default 1 check (round_number > 0),
  match_number integer not null default 1 check (match_number > 0),
  scheduled_at timestamptz,
  status public.match_status not null default 'scheduled',
  room_details text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tournament_id, round_number, match_number)
);

create table public.match_participants (
  match_id uuid not null references public.matches(id) on delete cascade,
  registration_id uuid not null references public.registrations(id) on delete cascade,
  placement integer check (placement is null or placement > 0),
  score numeric(10,2) not null default 0 check (score >= 0),
  kills integer not null default 0 check (kills >= 0),
  primary key (match_id, registration_id)
);

create table public.match_results (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null unique references public.matches(id) on delete cascade,
  published_by uuid references public.profiles(id) on delete set null,
  summary text,
  published_at timestamptz not null default now()
);

create index tournaments_status_starts_idx on public.tournaments(status, starts_at);
create index registrations_tournament_status_idx on public.registrations(tournament_id, status);
create index registrations_captain_idx on public.registrations(captain_id);
create index matches_tournament_schedule_idx on public.matches(tournament_id, scheduled_at);
create index squad_members_user_idx on public.squad_members(user_id);

-- Create a player profile when Supabase Auth creates a user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  chosen_username text;
begin
  chosen_username := coalesce(
    nullif(new.raw_user_meta_data ->> 'username', ''),
    'player_' || substr(replace(new.id::text, '-', ''), 1, 10)
  );

  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    chosen_username,
    nullif(new.raw_user_meta_data ->> 'display_name', '')
  );

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute procedure public.set_updated_at();
create trigger tournaments_set_updated_at before update on public.tournaments
for each row execute procedure public.set_updated_at();
create trigger registrations_set_updated_at before update on public.registrations
for each row execute procedure public.set_updated_at();
create trigger matches_set_updated_at before update on public.matches
for each row execute procedure public.set_updated_at();

-- RLS is enabled for every table exposed through the public schema.
alter table public.profiles enable row level security;
alter table public.squads enable row level security;
alter table public.squad_members enable row level security;
alter table public.tournaments enable row level security;
alter table public.registrations enable row level security;
alter table public.matches enable row level security;
alter table public.match_participants enable row level security;
alter table public.match_results enable row level security;

-- Remove broad default privileges; grant only the operations needed by each role.
revoke all on public.profiles, public.squads, public.squad_members,
  public.tournaments, public.registrations, public.matches,
  public.match_participants, public.match_results from anon, authenticated;

grant select on public.profiles, public.squads, public.squad_members,
  public.tournaments, public.registrations, public.matches,
  public.match_participants, public.match_results to anon, authenticated;

grant insert, update on public.profiles to authenticated;
grant insert, update, delete on public.squads, public.squad_members to authenticated;
grant insert on public.registrations to authenticated;
grant update on public.registrations to authenticated;
-- Admin writes to tournament operations are guarded by RLS policies below.
grant insert, update, delete on public.tournaments, public.matches,
  public.match_participants, public.match_results to authenticated;

-- Profiles: visible usernames are public; users can only edit their own profile.
create policy "Profiles are publicly readable" on public.profiles
for select to anon, authenticated using (true);
create policy "Players can create their own profile" on public.profiles
for insert to authenticated with check (id = (select auth.uid()) and role = 'player');
create policy "Players can update their own non-role profile fields" on public.profiles
for update to authenticated using (id = (select auth.uid()))
with check (id = (select auth.uid()) and role = 'player');

-- Admin check always reads the trusted role stored in the profile table.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- Public tournament and match information.
create policy "Published tournaments are readable" on public.tournaments
for select to anon, authenticated using (status <> 'draft' or public.is_admin());
create policy "Admins manage tournaments" on public.tournaments
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Squads are publicly readable" on public.squads
for select to anon, authenticated using (true);
create policy "Squad owners manage squads" on public.squads
for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "Squad owners update squads" on public.squads
for update to authenticated using (owner_id = (select auth.uid()) or public.is_admin())
with check (owner_id = (select auth.uid()) or public.is_admin());
create policy "Squad owners or admins delete squads" on public.squads
for delete to authenticated using (owner_id = (select auth.uid()) or public.is_admin());

create policy "Squad memberships are readable" on public.squad_members
for select to anon, authenticated using (true);
create policy "Users can join a squad as members" on public.squad_members
for insert to authenticated with check (
  user_id = (select auth.uid())
  and member_role = 'member'
);
create policy "Squad owners or admins manage memberships" on public.squad_members
for all to authenticated using (
  public.is_admin() or exists (
    select 1 from public.squads s
    where s.id = squad_id and s.owner_id = (select auth.uid())
  )
) with check (
  public.is_admin() or exists (
    select 1 from public.squads s
    where s.id = squad_id and s.owner_id = (select auth.uid())
  )
);

create policy "Registrations are readable by their captain or admins" on public.registrations
for select to authenticated using (
  captain_id = (select auth.uid()) or public.is_admin()
);
create policy "Public can view confirmed registrations" on public.registrations
for select to anon using (status = 'confirmed');
create policy "Squad captains can register their squads" on public.registrations
for insert to authenticated with check (
  captain_id = (select auth.uid())
  and exists (
    select 1 from public.squads s
    where s.id = squad_id and s.owner_id = (select auth.uid())
  )
  and exists (
    select 1 from public.tournaments t
    where t.id = tournament_id
      and t.status = 'registration_open'
      and (t.registration_opens_at is null or t.registration_opens_at <= now())
      and (t.registration_closes_at is null or t.registration_closes_at > now())
  )
);
create policy "Captains can withdraw their pending registrations" on public.registrations
for update to authenticated using (
  captain_id = (select auth.uid()) and status = 'pending'
) with check (
  captain_id = (select auth.uid()) and status = 'withdrawn'
);
create policy "Admins manage registrations" on public.registrations
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Matches are publicly readable" on public.matches
for select to anon, authenticated using (
  exists (select 1 from public.tournaments t where t.id = tournament_id and t.status <> 'draft')
  or public.is_admin()
);
create policy "Admins manage matches" on public.matches
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Match participants are publicly readable for published tournaments" on public.match_participants
for select to anon, authenticated using (
  exists (
    select 1 from public.matches m
    join public.tournaments t on t.id = m.tournament_id
    where m.id = match_id and t.status <> 'draft'
  ) or public.is_admin()
);
create policy "Admins manage match participants" on public.match_participants
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "Match results are publicly readable" on public.match_results
for select to anon, authenticated using (
  exists (
    select 1 from public.matches m
    join public.tournaments t on t.id = m.tournament_id
    where m.id = match_id and t.status <> 'draft'
  ) or public.is_admin()
);
create policy "Admins publish match results" on public.match_results
for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- SECURITY NOTE:
-- Never put Supabase service_role/secret keys in frontend JavaScript.
-- Promote the first administrator manually in Supabase SQL Editor after the
-- first account is created:
-- update public.profiles set role = 'admin' where username = 'YOUR_USERNAME';
