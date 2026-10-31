-- =====================================================================
-- CashNest database setup for Supabase
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- It is safe to run more than once.
-- =====================================================================

-- 1) One table holds every saved item. Each item has a "path", e.g.
--    groups/<groupId>                      a Split & Share group
--    groups/<groupId>/expenses/<id>        an expense or payment in that group
--    data/users/<userId>/settings          your personal settings
--    data/users/<userId>/me/spending/<id>  a Daily Spending entry
--    data/users/<userId>/me/goals/<id>     a savings goal
create table if not exists public.docs (
  path       text primary key,
  parent     text not null,
  group_id   text,
  owner_id   uuid,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint docs_path_shape check (path ~ '^[A-Za-z0-9_.~:@+-]+(/[A-Za-z0-9_.~:@+-]+)+$'),
  constraint docs_data_size check (pg_column_size(data) < 262144)
);
create index if not exists docs_parent_idx on public.docs (parent);
create index if not exists docs_group_idx  on public.docs (group_id);
create index if not exists docs_owner_idx  on public.docs (owner_id);

-- 2) Who belongs to which Split & Share group.
create table if not exists public.group_members (
  group_id  text not null,
  user_id   uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- 3) Work out parent / group / owner from the path (never trusted from the browser).
create or replace function public.docs_fill() returns trigger
language plpgsql as $$
declare
  seg text[] := string_to_array(new.path, '/');
  n   int    := array_length(seg, 1);
begin
  if tg_op = 'UPDATE' and new.path <> old.path then
    raise exception 'path cannot change';
  end if;
  new.parent     := array_to_string(seg[1:n-1], '/');
  new.updated_at := now();
  new.group_id   := null;
  new.owner_id   := null;
  if seg[1] = 'groups' and (n = 2 or (n = 4 and seg[3] = 'expenses')) then
    new.group_id := seg[2];
  elsif seg[1] = 'data' and seg[2] = 'users' and n >= 4 then
    begin
      new.owner_id := seg[3]::uuid;
    exception when others then
      raise exception 'invalid user id in path';
    end;
  else
    raise exception 'path not allowed: %', new.path;
  end if;
  return new;
end $$;

drop trigger if exists docs_fill on public.docs;
create trigger docs_fill before insert or update on public.docs
  for each row execute function public.docs_fill();

-- 4) Helper checks (security definer so they can look at membership safely).
create or replace function public.is_group_member(gid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.group_members where group_id = gid and user_id = auth.uid());
$$;

create or replace function public.group_is_new(gid text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.group_members where group_id = gid)
     and not exists (select 1 from public.docs where path = 'groups/' || gid);
$$;

-- Whoever creates a group becomes its first member; deleting a group clears its members.
create or replace function public.docs_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.parent = 'groups' and auth.uid() is not null then
    insert into public.group_members (group_id, user_id) values (new.group_id, auth.uid())
    on conflict do nothing;
  elsif tg_op = 'DELETE' and old.parent = 'groups' then
    delete from public.group_members where group_id = old.group_id;
  end if;
  return null;
end $$;

drop trigger if exists docs_after on public.docs;
create trigger docs_after after insert or delete on public.docs
  for each row execute function public.docs_after();

-- 5) Joining a group from an invite link.
create or replace function public.join_group(gid text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'sign in first';
  end if;
  if not exists (select 1 from public.docs where path = 'groups/' || gid) then
    return false;
  end if;
  insert into public.group_members (group_id, user_id) values (gid, auth.uid())
  on conflict do nothing;
  return true;
end $$;

-- 6) Row level security: you only ever see your own personal data,
--    and only the groups you are a member of.
alter table public.docs          enable row level security;
alter table public.group_members enable row level security;

drop policy if exists docs_select on public.docs;
drop policy if exists docs_insert on public.docs;
drop policy if exists docs_update on public.docs;
drop policy if exists docs_delete on public.docs;

create policy docs_select on public.docs for select to authenticated
  using (owner_id = auth.uid() or (group_id is not null and public.is_group_member(group_id)));

create policy docs_insert on public.docs for insert to authenticated
  with check (
    owner_id = auth.uid()
    or (group_id is not null and (
          public.is_group_member(group_id)
          or (parent = 'groups' and public.group_is_new(group_id))))
  );

create policy docs_update on public.docs for update to authenticated
  using      (owner_id = auth.uid() or (group_id is not null and public.is_group_member(group_id)))
  with check (owner_id = auth.uid() or (group_id is not null and public.is_group_member(group_id)));

create policy docs_delete on public.docs for delete to authenticated
  using (owner_id = auth.uid() or (group_id is not null and public.is_group_member(group_id)));

drop policy if exists members_select on public.group_members;
create policy members_select on public.group_members for select to authenticated
  using (user_id = auth.uid());

-- 7) Permissions for the API roles.
revoke all on public.docs, public.group_members from anon;
grant select, insert, update, delete on public.docs to authenticated;
grant select on public.group_members to authenticated;
revoke execute on function public.join_group(text) from public, anon;
grant execute on function public.join_group(text) to authenticated;
