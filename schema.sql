-- ReciRepo · Supabase schema
-- Run this entire file in your Supabase project's SQL Editor.

-- ── Extensions ────────────────────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ── Profiles ──────────────────────────────────────────────────────────────
create table public.profiles (
  id         uuid references auth.users on delete cascade primary key,
  username   text unique not null,
  is_admin   boolean default false,
  is_friend  boolean default false,
  is_family  boolean default false,
  created_at timestamptz default now()
);
alter table public.profiles enable row level security;
create policy "Profiles are public"          on public.profiles for select using (true);
create policy "Users can update own profile" on public.profiles for update using (auth.uid() = id or public.is_admin());

-- Helper: check if the current user is an admin (SECURITY DEFINER bypasses RLS to avoid recursion)
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- Auto-create a profile row when a new user signs up.
-- The username comes from the `username` key in user_metadata (sent during sign-up).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ── Recipes ───────────────────────────────────────────────────────────────
create table public.recipes (
  id         uuid default uuid_generate_v4() primary key,
  title      text not null,
  author_id  uuid references public.profiles(id) on delete cascade not null,
  time_text  text,                          -- e.g. "20 min", "1 h 15"
  servings   int  default 2,
  color      text default '#E8C36E',        -- placeholder card colour
  accent     text default '#2F2A2A',
  source_url text,                          -- for "add via link"
  image_url  text,                          -- cover photo (Supabase Storage public URL)
  created_at timestamptz default now()
);
alter table public.recipes enable row level security;
-- Recipes are visible when: viewer is the author, viewer is admin,
-- or viewer's user type (friend/family) overlaps with the author's type.
create policy "Recipes visible by user type" on public.recipes for select using (
  author_id = auth.uid()
  or public.is_admin()
  or exists (
    select 1 from public.profiles v
    join public.profiles a on a.id = recipes.author_id
    where v.id = auth.uid()
      and (
        (v.is_friend and a.is_friend)
        or (v.is_family and a.is_family)
      )
  )
);
create policy "Authors can insert own recipes" on public.recipes for insert with check (auth.uid() = author_id);
create policy "Authors can update own recipes" on public.recipes for update using (auth.uid() = author_id);
create policy "Authors can delete own recipes" on public.recipes for delete using (auth.uid() = author_id);

-- ── Tags ──────────────────────────────────────────────────────────────────
create table public.recipe_tags (
  recipe_id uuid references public.recipes(id) on delete cascade,
  tag       text not null,
  primary key (recipe_id, tag)
);
alter table public.recipe_tags enable row level security;
create policy "Tags visible if recipe visible" on public.recipe_tags for select using (
  exists (select 1 from public.recipes where id = recipe_id)
);
create policy "Authors manage tags" on public.recipe_tags for all using (
  exists (select 1 from public.recipes where id = recipe_id and author_id = auth.uid())
);

-- ── Ingredients ───────────────────────────────────────────────────────────
create table public.ingredients (
  id         uuid default uuid_generate_v4() primary key,
  recipe_id  uuid references public.recipes(id) on delete cascade,
  qty        text,
  item       text not null,
  sort_order int  default 0
);
alter table public.ingredients enable row level security;
create policy "Ingredients visible if recipe visible" on public.ingredients for select using (
  exists (select 1 from public.recipes where id = recipe_id)
);
create policy "Authors manage ingredients" on public.ingredients for all using (
  exists (select 1 from public.recipes where id = recipe_id and author_id = auth.uid())
);

-- ── Steps ─────────────────────────────────────────────────────────────────
create table public.steps (
  id            uuid default uuid_generate_v4() primary key,
  recipe_id     uuid references public.recipes(id) on delete cascade,
  text          text not null,
  timer_seconds int  default 0,
  sort_order    int  default 0
);
alter table public.steps enable row level security;
create policy "Steps visible if recipe visible" on public.steps for select using (
  exists (select 1 from public.recipes where id = recipe_id)
);
create policy "Authors manage steps" on public.steps for all using (
  exists (select 1 from public.recipes where id = recipe_id and author_id = auth.uid())
);

-- ── Saves (bookmarks) ─────────────────────────────────────────────────────
create table public.saves (
  user_id    uuid references public.profiles(id) on delete cascade,
  recipe_id  uuid references public.recipes(id)  on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, recipe_id)
);
alter table public.saves enable row level security;
create policy "Users see own saves"   on public.saves for select using (auth.uid() = user_id);
create policy "Users manage own saves" on public.saves for all    using (auth.uid() = user_id);

-- ── Cook logs ─────────────────────────────────────────────────────────────
create table public.cook_logs (
  id         uuid default uuid_generate_v4() primary key,
  user_id    uuid references public.profiles(id) on delete cascade,
  recipe_id  uuid references public.recipes(id)  on delete cascade,
  cooked_at  timestamptz default now()
);
alter table public.cook_logs enable row level security;
create policy "Cook logs are public"    on public.cook_logs for select using (true);
create policy "Users log own cooks"     on public.cook_logs for insert with check (auth.uid() = user_id);

-- ── recipes_with_meta view ────────────────────────────────────────────────
-- security_invoker = true ensures the recipe RLS policies are applied when this view is queried.
-- Returned by the feed query — joins author username, cook count, and tags.
create or replace view public.recipes_with_meta with (security_invoker = true) as
select
  r.id,
  r.title,
  r.author_id,
  p.username          as author_username,
  r.time_text,
  r.servings,
  r.color,
  r.accent,
  r.source_url,
  r.image_url,
  r.created_at,
  count(distinct cl.id)                                        as cook_count,
  coalesce(array_agg(distinct rt.tag) filter (where rt.tag is not null), '{}') as tags
from      public.recipes      r
join      public.profiles     p  on p.id = r.author_id
left join public.cook_logs    cl on cl.recipe_id = r.id
left join public.recipe_tags  rt on rt.recipe_id = r.id
group by  r.id, p.username;

-- ── Storage: recipe cover images ──────────────────────────────────────────
-- Run in Supabase Dashboard → Storage → New bucket, OR via SQL:
insert into storage.buckets (id, name, public)
values ('recipe-images', 'recipe-images', true)
on conflict (id) do nothing;

create policy "Anyone can view recipe images"
  on storage.objects for select
  using (bucket_id = 'recipe-images');

create policy "Authenticated users can upload recipe images"
  on storage.objects for insert
  with check (bucket_id = 'recipe-images' and auth.role() = 'authenticated');

create policy "Users can update own recipe images"
  on storage.objects for update
  using (bucket_id = 'recipe-images' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Users can delete own recipe images"
  on storage.objects for delete
  using (bucket_id = 'recipe-images' and auth.uid()::text = (storage.foldername(name))[1]);
