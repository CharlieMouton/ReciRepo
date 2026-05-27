-- Migration: Add friend/family user types
-- Run this in your Supabase project's SQL Editor for existing deployments.
-- Fresh deployments should use schema.sql instead.

-- ── 1. Add type columns to profiles ───────────────────────────────────────
alter table public.profiles
  add column if not exists is_admin  boolean default false,
  add column if not exists is_friend boolean default false,
  add column if not exists is_family boolean default false;

-- ── 2. Helper function (SECURITY DEFINER to avoid RLS recursion) ──────────
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- ── 3. Update profiles UPDATE policy to allow admin edits ─────────────────
drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles
  for update using (auth.uid() = id or public.is_admin());

-- ── 4. Replace public recipe visibility with type-based policy ────────────
drop policy if exists "Recipes are public" on public.recipes;
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

-- ── 5. Cascade recipe visibility to child tables ───────────────────────────
drop policy if exists "Tags are public"        on public.recipe_tags;
drop policy if exists "Ingredients are public" on public.ingredients;
drop policy if exists "Steps are public"       on public.steps;

create policy "Tags visible if recipe visible" on public.recipe_tags for select using (
  exists (select 1 from public.recipes where id = recipe_id)
);
create policy "Ingredients visible if recipe visible" on public.ingredients for select using (
  exists (select 1 from public.recipes where id = recipe_id)
);
create policy "Steps visible if recipe visible" on public.steps for select using (
  exists (select 1 from public.recipes where id = recipe_id)
);

-- ── 6. Update view to respect recipe RLS ──────────────────────────────────
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
