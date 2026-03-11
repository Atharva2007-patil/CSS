-- Adds media/document support and stable RLS policies for chat.
-- Run this whole file in Supabase SQL Editor for project ClientSideScripting.

alter table public.messages
  add column if not exists media_url text,
  add column if not exists media_type text,
  add column if not exists media_name text,
  add column if not exists media_size_bytes bigint,
  add column if not exists deleted_for uuid[] default '{}'::uuid[];

update public.messages
set deleted_for = '{}'::uuid[]
where deleted_for is null;

alter table public.messages enable row level security;
grant select, insert, update, delete on table public.messages to authenticated;

-- Restrict media_type to known values when set.
alter table public.messages
  drop constraint if exists messages_media_type_check;

alter table public.messages
  add constraint messages_media_type_check
  check (media_type in ('image', 'video', 'document') or media_type is null);

-- Make sure at least one of text or media exists.
alter table public.messages
  drop constraint if exists messages_has_text_or_media;

alter table public.messages
  add constraint messages_has_text_or_media
  check (
    (content is not null and char_length(trim(content)) > 0)
    or media_url is not null
  );

-- Create public bucket for chat attachments if missing.
insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', true)
on conflict (id) do nothing;

-- Storage policies for authenticated users.
drop policy if exists "chat_media_read_public" on storage.objects;
create policy "chat_media_read_public"
  on storage.objects
  for select
  to public
  using (bucket_id = 'chat-media');

drop policy if exists "chat_media_upload_auth" on storage.objects;
create policy "chat_media_upload_auth"
  on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'chat-media');

drop policy if exists "chat_media_delete_own" on storage.objects;
drop policy if exists "chat_media_delete_auth" on storage.objects;
create policy "chat_media_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'chat-media' and owner = auth.uid());

-- Force-drop every existing policy on public.messages to avoid hidden conflicts.
do $$
declare
  policy_name text;
begin
  for policy_name in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'messages'
  loop
    execute format('drop policy if exists %I on public.messages', policy_name);
  end loop;
end $$;

-- Select: user can read only their conversation.
-- Note: hide-for-me is handled in app state using deleted_for.
create policy "messages_select_own_conversations"
  on public.messages
  for select
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- Insert: sender must be current user.
create policy "messages_insert_sender_is_auth_user"
  on public.messages
  for insert
  to authenticated
  with check (auth.uid() = sender_id);

-- Update: both participants can update (used for delete-for-me via deleted_for array).
create policy "messages_update_delete_for_me"
  on public.messages
  for update
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = receiver_id)
  with check (true);

-- Delete-for-everyone: only sender can physically delete.
create policy "messages_delete_own"
  on public.messages
  for delete
  to authenticated
  using (auth.uid() = sender_id);
