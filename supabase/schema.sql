create extension if not exists "pgcrypto";

create table if not exists public.guides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  status text not null default 'draft'
    check (status in ('draft', 'published')),
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.steps (
  id uuid primary key default gen_random_uuid(),
  guide_id uuid not null references public.guides(id) on delete cascade,
  position integer not null default 0,
  title text not null,
  description text not null default '',
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.guides enable row level security;
alter table public.steps enable row level security;

drop policy if exists "Users manage own guides" on public.guides;

create policy "Users manage own guides"
on public.guides
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Anyone can read public guides" on public.guides;

create policy "Anyone can read public guides"
on public.guides
for select
using (
  is_public = true
  or auth.uid() = user_id
);

drop policy if exists "Users manage steps in own guides" on public.steps;

create policy "Users manage steps in own guides"
on public.steps
for all
using (
  exists (
    select 1
    from public.guides
    where guides.id = steps.guide_id
      and guides.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.guides
    where guides.id = steps.guide_id
      and guides.user_id = auth.uid()
  )
);

drop policy if exists "Anyone can read public guide steps" on public.steps;

create policy "Anyone can read public guide steps"
on public.steps
for select
using (
  exists (
    select 1
    from public.guides
    where guides.id = steps.guide_id
      and (
        guides.is_public = true
        or guides.user_id = auth.uid()
      )
  )
);

insert into storage.buckets (
  id,
  name,
  public
)
values (
  'guide-images',
  'guide-images',
  true
)
on conflict (id)
do update set public = true;

drop policy if exists "Authenticated users upload guide images"
on storage.objects;

create policy "Authenticated users upload guide images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'guide-images'
);

drop policy if exists "Authenticated users update guide images"
on storage.objects;

create policy "Authenticated users update guide images"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'guide-images'
);

drop policy if exists "Authenticated users delete guide images"
on storage.objects;

create policy "Authenticated users delete guide images"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'guide-images'
);

drop policy if exists "Anyone can read guide images"
on storage.objects;

create policy "Anyone can read guide images"
on storage.objects
for select
using (
  bucket_id = 'guide-images'
);

create or replace function public.update_modified_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists update_guides_modified
on public.guides;

create trigger update_guides_modified
before update on public.guides
for each row
execute procedure public.update_modified_column();

drop trigger if exists update_steps_modified
on public.steps;

create trigger update_steps_modified
before update on public.steps
for each row
execute procedure public.update_modified_column();
