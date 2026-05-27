-- Migration: Security fixes
-- Run this in your Supabase project's SQL Editor.

-- ── 1. Prevent privilege escalation on profile flags ──────────────────────────
-- A BEFORE UPDATE trigger resets is_admin/is_friend/is_family to their current
-- values whenever the caller is not an admin. This stops any user from granting
-- themselves or others elevated flags via direct API calls.
create or replace function public.protect_profile_flags()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.is_admin  := old.is_admin;
    new.is_friend := old.is_friend;
    new.is_family := old.is_family;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_flags_trigger on public.profiles;
create trigger protect_profile_flags_trigger
  before update on public.profiles
  for each row execute procedure public.protect_profile_flags();

-- ── 2. Enforce per-user upload paths in Storage ───────────────────────────────
-- The previous INSERT policy allowed any authenticated user to upload to any
-- path in the recipe-images bucket. This restricts uploads to the user's own
-- UUID folder (e.g. <user-id>/filename.jpg), matching the existing DELETE/UPDATE
-- policies which already enforce this via storage.foldername(name).
drop policy if exists "Authenticated users can upload recipe images" on storage.objects;
create policy "Authenticated users can upload recipe images"
  on storage.objects for insert
  with check (
    bucket_id = 'recipe-images'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
