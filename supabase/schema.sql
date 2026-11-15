-- نفّذ هذا الملف في Supabase > SQL Editor
create extension if not exists pgcrypto;

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  image_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  price numeric(12,2) not null default 0 check (price >= 0),
  image_url text,
  available boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  customer_name text not null,
  customer_phone text not null,
  quantity integer not null check (quantity > 0),
  notes text not null default '',
  status text not null default 'new' check (status in ('new','processing','completed','cancelled')),
  created_at timestamptz not null default now()
);

alter table public.admins enable row level security;
alter table public.projects enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;

create or replace function public.is_site_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- بيانات الأعمال والمنتجات متاحة للعرض العام، والكتابة للمسؤول فقط.
create policy "Public read projects" on public.projects for select using (true);
create policy "Admin manage projects" on public.projects for all using (public.is_site_admin()) with check (public.is_site_admin());

create policy "Public read available products" on public.products for select using (available = true or public.is_site_admin());
create policy "Admin manage products" on public.products for all using (public.is_site_admin()) with check (public.is_site_admin());

-- الزائر يستطيع إرسال طلب فقط؛ لا يستطيع قراءة الطلبات أو تغيير حالتها.
create policy "Visitors submit orders" on public.orders for insert
with check (
  status = 'new' and quantity > 0
  and length(trim(customer_name)) between 2 and 100
  and length(trim(customer_phone)) between 6 and 30
  and length(trim(product_name)) between 1 and 150
  and length(notes) <= 1000
);
create policy "Admin read and manage orders" on public.orders for all
using (public.is_site_admin()) with check (public.is_site_admin());

-- لا يحتاج الموقع إلى قراءة جدول admins من المتصفح. التحقق يتم عبر الدالة is_site_admin.

-- مساحة صور عامة للعرض، والرفع/الحذف للمسؤول فقط.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('portfolio-media', 'portfolio-media', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880,
allowed_mime_types = array['image/jpeg','image/png','image/webp'];

create policy "Public view portfolio media" on storage.objects
for select using (bucket_id = 'portfolio-media');
create policy "Admins upload portfolio media" on storage.objects
for insert to authenticated with check (bucket_id = 'portfolio-media' and public.is_site_admin());
create policy "Admins update portfolio media" on storage.objects
for update to authenticated using (bucket_id = 'portfolio-media' and public.is_site_admin())
with check (bucket_id = 'portfolio-media' and public.is_site_admin());
create policy "Admins delete portfolio media" on storage.objects
for delete to authenticated using (bucket_id = 'portfolio-media' and public.is_site_admin());

-- بعد إنشاء حساب المسؤول من Authentication > Users، انسخ UUID الخاص به ثم نفّذ:
-- insert into public.admins(user_id) values ('ضع-UUID-حساب-المسؤول-هنا');
