create table public.document (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null references public.shop(id) on delete cascade,
  type_id uuid not null references public.document_type(id) on delete restrict,
  storage_bucket text not null check (storage_bucket = 'shop-documents'),
  storage_path text not null check (
    length(btrim(storage_path)) > 0
    and storage_path like (shop_id::text || '/%')
  ),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  size_bytes integer not null check (size_bytes > 0 and size_bytes <= 8388608),
  ocr_status_id uuid not null references public.ocr_status(id) on delete restrict,
  ocr_result jsonb,
  uploaded_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, id),
  unique (storage_bucket, storage_path)
);

create trigger set_document_updated_at
before update on public.document
for each row execute function public.set_updated_at();

create table public.ocr_job (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null,
  document_id uuid not null,
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'success', 'failed')),
  attempts integer not null default 0 check (attempts >= 0),
  locked_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (document_id),
  unique (shop_id, id),
  foreign key (shop_id, document_id) references public.document(shop_id, id) on delete cascade
);

create trigger set_ocr_job_updated_at
before update on public.ocr_job
for each row execute function public.set_updated_at();

create table public.ocr_correction (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_id uuid not null,
  document_id uuid not null,
  raw_text text not null check (length(btrim(raw_text)) > 0),
  accepted_entity_table text not null
    check (accepted_entity_table in ('shop_item', 'party', 'expense_category', 'unknown')),
  accepted_entity_id uuid,
  confidence numeric(5, 4) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, document_id) references public.document(shop_id, id) on delete cascade
);

create index document_shop_id_type_created_at_idx
  on public.document (shop_id, type_id, created_at desc);

create index document_uploaded_by_idx
  on public.document (uploaded_by, created_at desc);

create index ocr_job_status_created_at_idx
  on public.ocr_job (status, created_at);

create index ocr_correction_shop_id_document_id_idx
  on public.ocr_correction (shop_id, document_id);

grant select, insert, update on public.document to authenticated;
grant select on public.ocr_job to authenticated;
grant select, insert on public.ocr_correction to authenticated;

alter table public.document enable row level security;
alter table public.ocr_job enable row level security;
alter table public.ocr_correction enable row level security;

create policy document_select
on public.document
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy document_insert
on public.document
for insert
with check (
  public.auth_can_access_shop(shop_id)
  and uploaded_by = auth.uid()
  and storage_path like (shop_id::text || '/%')
);

create policy document_update
on public.document
for update
using (public.auth_can_access_shop(shop_id))
with check (
  public.auth_can_access_shop(shop_id)
  and storage_path like (shop_id::text || '/%')
);

create policy ocr_job_select
on public.ocr_job
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy ocr_correction_select
on public.ocr_correction
for select
using (
  public.auth_can_access_shop(shop_id)
  or public.auth_is_platform_staff(null)
);

create policy ocr_correction_insert
on public.ocr_correction
for insert
with check (
  public.auth_can_access_shop(shop_id)
  and created_by = auth.uid()
);
