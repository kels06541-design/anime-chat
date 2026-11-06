-- ANIME CHAT — base Supabase sécurisée
-- À exécuter une seule fois dans Supabase > SQL Editor.
-- Les pseudos sont les adresses internes pseudo@animechat.invalid.
-- Créer le compte Kems dans Authentication AVANT de réactiver les inscriptions publiques.

create table if not exists public.docs (
  col text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  created timestamptz not null default now(),
  primary key (col, id)
);
create index if not exists docs_col_created on public.docs(col, created desc);
alter table public.docs enable row level security;

create table if not exists public.chat_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member'))
);
alter table public.chat_roles enable row level security;

-- Tout nouveau compte reçoit automatiquement le rôle membre.
create or replace function public.assign_default_chat_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.chat_roles (user_id, role)
  values (new.id, 'member')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_chat_role on auth.users;
create trigger on_auth_user_created_chat_role
after insert on auth.users
for each row execute procedure public.assign_default_chat_role();

-- Rattrape aussi les comptes déjà existants.
insert into public.chat_roles (user_id, role)
select id, 'member' from auth.users
on conflict (user_id) do nothing;

-- Fonction réservée aux contrôles RLS : les membres ne peuvent pas s'attribuer ADMIN.
create or replace function public.is_chat_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.chat_roles
    where user_id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.my_chat_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.chat_roles where user_id = auth.uid()),
    'member'
  );
$$;

revoke all on function public.assign_default_chat_role() from public, anon, authenticated;
revoke all on function public.is_chat_admin() from public, anon;
grant execute on function public.is_chat_admin() to authenticated;
revoke all on function public.my_chat_role() from public, anon;
grant execute on function public.my_chat_role() to authenticated;

-- Supprime les anciennes policies de docs pour éviter qu'une ancienne policy permissive
-- (par exemple docs_all) ne contourne les règles ci-dessous.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'docs'
  loop
    execute format('drop policy if exists %I on public.docs', p.policyname);
  end loop;
end $$;

-- Un utilisateur ne lit un DM que si son UUID figure dans le chemin dm:UUID_UUID:msgs.
create policy docs_read_authenticated on public.docs
for select to authenticated
using (
  col not like 'dm:%'
  or split_part(split_part(col, ':', 2), '_', 1) = auth.uid()::text
  or split_part(split_part(col, ':', 2), '_', 2) = auth.uid()::text
);

-- Le pseudo du profil doit correspondre au pseudo du compte Auth.
-- Cela empêche un membre de se faire passer pour Kems ou un autre membre.
create policy docs_insert_own on public.docs
for insert to authenticated
with check (
  (
    col = 'profiles'
    and id = auth.uid()::text
    and lower(coalesce(data->>'name', '')) =
        lower(split_part(coalesce(auth.jwt()->>'email', ''), '@', 1))
    and (lower(coalesce(data->>'name', '')) <> 'kems' or public.is_chat_admin())
  )
  or (
    col like 'dm:%'
    and (
      split_part(split_part(col, ':', 2), '_', 1) = auth.uid()::text
      or split_part(split_part(col, ':', 2), '_', 2) = auth.uid()::text
    )
    and data->>'uid' = auth.uid()::text
  )
  or (
    col <> 'profiles' and col <> 'games' and col not like 'dm:%'
    and data->>'uid' = auth.uid()::text
  )
  or (col = 'games' and data->>'h' = auth.uid()::text)
);

create policy docs_update_own on public.docs
for update to authenticated
using (
  (
    col = 'profiles' and id = auth.uid()::text
    and lower(coalesce(data->>'name', '')) =
        lower(split_part(coalesce(auth.jwt()->>'email', ''), '@', 1))
    and (lower(coalesce(data->>'name', '')) <> 'kems' or public.is_chat_admin())
  )
  or (
    col like 'dm:%'
    and (
      split_part(split_part(col, ':', 2), '_', 1) = auth.uid()::text
      or split_part(split_part(col, ':', 2), '_', 2) = auth.uid()::text
    )
    and data->>'uid' = auth.uid()::text
  )
  or (
    col <> 'profiles' and col <> 'games' and col not like 'dm:%'
    and data->>'uid' = auth.uid()::text
  )
  or (
    col = 'games' and (
      data->>'h' = auth.uid()::text
      or coalesce(data->'pl', '[]'::jsonb) ? auth.uid()::text
      or data->>'to' = auth.uid()::text
      or data->>'to' = 'all'
    )
  )
)
with check (
  (
    col = 'profiles' and id = auth.uid()::text
    and lower(coalesce(data->>'name', '')) =
        lower(split_part(coalesce(auth.jwt()->>'email', ''), '@', 1))
    and (lower(coalesce(data->>'name', '')) <> 'kems' or public.is_chat_admin())
  )
  or (
    col like 'dm:%'
    and (
      split_part(split_part(col, ':', 2), '_', 1) = auth.uid()::text
      or split_part(split_part(col, ':', 2), '_', 2) = auth.uid()::text
    )
    and data->>'uid' = auth.uid()::text
  )
  or (
    col <> 'profiles' and col <> 'games' and col not like 'dm:%'
    and data->>'uid' = auth.uid()::text
  )
  or (
    col = 'games' and (
      data->>'h' = auth.uid()::text
      or coalesce(data->'pl', '[]'::jsonb) ? auth.uid()::text
      or coalesce(data->'dc', '[]'::jsonb) ? auth.uid()::text
    )
  )
);

create policy docs_delete_own on public.docs
for delete to authenticated
using (
  (
    col = 'profiles' and id = auth.uid()::text
  )
  or (
    col like 'dm:%'
    and (
      split_part(split_part(col, ':', 2), '_', 1) = auth.uid()::text
      or split_part(split_part(col, ':', 2), '_', 2) = auth.uid()::text
    )
    and data->>'uid' = auth.uid()::text
  )
  or (
    col <> 'profiles' and col <> 'games' and col not like 'dm:%'
    and data->>'uid' = auth.uid()::text
  )
  or (col = 'games' and data->>'h' = auth.uid()::text)
);

grant select, insert, update, delete on public.docs to authenticated;
revoke all on public.docs from anon;

-- Chaque membre ne peut lire que son propre rôle. Aucun droit d'écriture côté client.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'chat_roles'
  loop
    execute format('drop policy if exists %I on public.chat_roles', p.policyname);
  end loop;
end $$;
create policy read_own_role on public.chat_roles
for select to authenticated using (user_id = auth.uid());
grant select on public.chat_roles to authenticated;
revoke insert, update, delete on public.chat_roles from anon, authenticated;

-- Messages en temps réel.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'docs'
  ) then
    alter publication supabase_realtime add table public.docs;
  end if;
end $$;

-- Stockage des médias. Les URL du bucket sont publiques pour l'affichage des médias du chat.
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do update set public = true;

drop policy if exists media_read on storage.objects;
drop policy if exists media_write on storage.objects;
drop policy if exists media_delete on storage.objects;
drop policy if exists media_insert_own on storage.objects;
drop policy if exists media_delete_own on storage.objects;

create policy media_read on storage.objects
for select to authenticated using (bucket_id = 'media');
create policy media_insert_own on storage.objects
for insert to authenticated
with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy media_delete_own on storage.objects
for delete to authenticated
using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
