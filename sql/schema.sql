-- ============================================================
-- JUICY 파트너 게시판 - Supabase 스키마
-- Supabase 대시보드 > SQL Editor 에 전체를 붙여넣고 실행하세요.
-- ============================================================

-- 1) 점주/바이저 프로필 테이블
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  store_name text not null default '미지정 매장',
  role text not null default 'owner' check (role in ('owner', 'visor')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- 역할 확인용 헬퍼 함수 (RLS 정책에서 재귀 없이 안전하게 사용하기 위해 security definer로 선언)
create or replace function public.is_visor()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'visor'
  );
$$;

create policy "profiles_select" on public.profiles
  for select using (auth.uid() = id or public.is_visor());

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- 회원가입(Auth 계정 생성) 시 profiles 행을 자동 생성해주는 트리거
-- Supabase 대시보드에서 계정을 만들 때 "User Metadata"에 store_name, role을 넣어두면 자동 반영됩니다.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, store_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'store_name', '미지정 매장'),
    coalesce(new.raw_user_meta_data->>'role', 'owner')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 2) 공지사항
create table if not exists public.notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  category text not null default '일반',
  is_pinned boolean not null default false,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.notices enable row level security;

create policy "notices_select_authenticated" on public.notices
  for select using (auth.role() = 'authenticated');

create policy "notices_write_visor" on public.notices
  for all using (public.is_visor()) with check (public.is_visor());


-- 3) 신메뉴/기존 메뉴 레시피
create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default '베이직 메뉴',
  video_url text,
  ingredients text[] not null default '{}',
  steps text[] not null default '{}',
  pdf_url text,
  is_new boolean not null default true,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.recipes enable row level security;

create policy "recipes_select_authenticated" on public.recipes
  for select using (auth.role() = 'authenticated');

create policy "recipes_write_visor" on public.recipes
  for all using (public.is_visor()) with check (public.is_visor());


-- 4) 자주 묻는 질문 (FAQ)
create table if not exists public.faqs (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  answer text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.faqs enable row level security;

create policy "faqs_select_authenticated" on public.faqs
  for select using (auth.role() = 'authenticated');

create policy "faqs_write_visor" on public.faqs
  for all using (public.is_visor()) with check (public.is_visor());


-- 5) 건의사항
create table if not exists public.suggestions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  is_anonymous boolean not null default false,
  owner_id uuid not null references public.profiles(id),
  status text not null default '답변대기' check (status in ('답변대기', '답변완료')),
  created_at timestamptz not null default now()
);

alter table public.suggestions enable row level security;

-- 본인 글이거나, 바이저는 전체 조회 가능
create policy "suggestions_select" on public.suggestions
  for select using (owner_id = auth.uid() or public.is_visor());

-- 로그인한 점주 본인 명의로만 작성 가능
create policy "suggestions_insert" on public.suggestions
  for insert with check (owner_id = auth.uid());

-- 상태 변경(답변완료 처리)은 바이저만
create policy "suggestions_update_visor" on public.suggestions
  for update using (public.is_visor());


-- 6) 건의사항 답변
create table if not exists public.suggestion_replies (
  id uuid primary key default gen_random_uuid(),
  suggestion_id uuid not null references public.suggestions(id) on delete cascade,
  content text not null,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.suggestion_replies enable row level security;

create policy "replies_select" on public.suggestion_replies
  for select using (
    exists (
      select 1 from public.suggestions s
      where s.id = suggestion_id and (s.owner_id = auth.uid() or public.is_visor())
    )
  );

create policy "replies_insert_visor" on public.suggestion_replies
  for insert with check (public.is_visor());


-- 7) 자료실
create table if not exists public.resources (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default '문서',
  url text not null,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.resources enable row level security;

create policy "resources_select_authenticated" on public.resources
  for select using (auth.role() = 'authenticated');

create policy "resources_write_visor" on public.resources
  for all using (public.is_visor()) with check (public.is_visor());


-- 8) 업체 정보 (재료/장비 공급업체, AS 등 연락처 모음)
create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default '기타',
  contact_name text,
  phone text,
  email text,
  notes text,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.companies enable row level security;

create policy "companies_select_authenticated" on public.companies
  for select using (auth.role() = 'authenticated');

create policy "companies_write_visor" on public.companies
  for all using (public.is_visor()) with check (public.is_visor());


-- 9) 본사 발주 요청 (점주가 필요한 물품을 요청하고, 바이저가 발주 확인/댓글을 남깁니다)
create table if not exists public.supply_requests (
  id uuid primary key default gen_random_uuid(),
  item_name text not null,
  quantity text,
  note text,
  owner_id uuid not null references public.profiles(id),
  status text not null default '요청' check (status in ('요청', '발주완료')),
  created_at timestamptz not null default now()
);

alter table public.supply_requests enable row level security;

-- 건의사항과 동일한 원칙: 본인 글이거나 바이저는 전체 조회
create policy "supply_requests_select" on public.supply_requests
  for select using (owner_id = auth.uid() or public.is_visor());

create policy "supply_requests_insert" on public.supply_requests
  for insert with check (owner_id = auth.uid());

create policy "supply_requests_update_visor" on public.supply_requests
  for update using (public.is_visor());

create table if not exists public.supply_request_comments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.supply_requests(id) on delete cascade,
  content text not null,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.supply_request_comments enable row level security;

create policy "supply_request_comments_select" on public.supply_request_comments
  for select using (
    exists (
      select 1 from public.supply_requests r
      where r.id = request_id and (r.owner_id = auth.uid() or public.is_visor())
    )
  );

create policy "supply_request_comments_insert_visor" on public.supply_request_comments
  for insert with check (public.is_visor());


-- ============================================================
-- (선택) 화면 미리보기용 샘플 데이터 - 필요 없으면 지우고 실행하세요.
-- 아래 INSERT는 author_id/owner_id를 비워두면 실패하니, 먼저 계정을 만든 뒤
-- 해당 계정의 uuid로 author_id 값을 바꿔서 실행해도 됩니다. 그냥 건너뛰어도 무방합니다.
-- ============================================================
-- insert into public.faqs (question, answer, sort_order) values
--   ('포장 용기·빨대는 어디서 추가 주문하나요?', '자료실 > 발주 서식에서 포장재 발주서를 다운로드해 물류팀 이메일로 보내주세요.', 1),
--   ('직원 급여 정산일이 언제인가요?', '매월 10일 마감 후 15일에 지급됩니다.', 2);
