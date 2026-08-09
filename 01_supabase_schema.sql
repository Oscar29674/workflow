-- ProJob Dispatch Orchestrator — Supabase schema
-- Apply this in the Supabase SQL editor (or via psql) before importing the n8n workflow.
-- Idempotent: safe to re-run.

-- ─────────────────────────────────────────────────────────────────────────────
-- subcontractors
--   Rostered subs the orchestrator can dispatch to. The workflow only considers
--   rows with availability_status = 'available' (filtered in the Get Available
--   Subcontractors node).
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.subcontractors (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  specialties           text[] not null default '{}',     -- e.g. {plumbing,water_heater}
  service_area          text[] not null default '{}',     -- Florida cities, e.g. {Miami,Doral,Hialeah}
  rating                numeric(3,2) not null default 0,  -- 0.00 - 5.00
  active_job_count      integer not null default 0,        -- lower = preferred (load balancing)
  availability_status   text not null default 'available' check (availability_status in ('available','busy','offline')),
  contact_phone         text,                              -- E.164, e.g. +13055551234  (used by notify sub)
  contact_email         text,                              -- optional fallback
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists subcontractors_availability_idx
  on public.subcontractors (availability_status);

-- ─────────────────────────────────────────────────────────────────────────────
-- jobs
--   Inbound jobs from ProJob Manager. Workflow reads by id (matching column on
--   the update nodes) and writes status + assigned_subcontractor_id.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.jobs (
  id                          uuid primary key default gen_random_uuid(),
  service_type                text not null,                            -- e.g. 'plumbing'
  description                 text,
  city                        text not null,                            -- job location city
  customer_name               text,
  customer_phone              text,
  priority                    text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status                      text not null default 'pending' check (status in ('pending','dispatched','escalated','completed','cancelled')),
  assigned_subcontractor_id   uuid references public.subcontractors(id) on delete set null,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

create index if not exists jobs_status_idx on public.jobs (status);
create index if not exists jobs_assigned_sub_idx on public.jobs (assigned_subcontractor_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- dispatch_log
--   One row per workflow run. Records both auto-dispatch AND escalation paths
--   so you can audit confidence, reasoning, and which model decided.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.dispatch_log (
  id                          uuid primary key default gen_random_uuid(),
  job_id                      uuid references public.jobs(id) on delete cascade,
  selected_subcontractor_id   uuid references public.subcontractors(id) on delete set null,
  selected_subcontractor_name text,
  reasoning                   text,
  confidence                  numeric(4,3),                  -- 0.000 - 1.000
  escalated                   boolean not null default false,
  escalation_reason           text,
  model_used                  text,                          -- e.g. 'llama3.1:8b'
  cost_usd                    numeric(8,4) not null default 0,
  raw_response                jsonb,                         -- full Ollama reply for debugging
  created_at                  timestamptz not null default now()
);

create index if not exists dispatch_log_job_idx     on public.dispatch_log (job_id);
create index if not exists dispatch_log_escalated_idx on public.dispatch_log (escalated);

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at triggers
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists subcontractors_set_updated_at on public.subcontractors;
create trigger subcontractors_set_updated_at
  before update on public.subcontractors
  for each row execute function public.tg_set_updated_at();

drop trigger if exists jobs_set_updated_at on public.jobs;
create trigger jobs_set_updated_at
  before update on public.jobs
  for each row execute function public.tg_set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- Seed roster — Ray Torres, Dana Walsh, Marco Reyes, Sara Kim
-- Adjust service_area / specialties to match real coverage.
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.subcontractors (name, specialties, service_area, rating, active_job_count, availability_status, contact_phone)
values
  ('Ray Torres',  ARRAY['plumbing','water_heater','drain'],          ARRAY['Miami','Doral','Hialeah','Kendall'], 4.8, 1, 'available', '+13055550101'),
  ('Dana Walsh',  ARRAY['electrical','lighting','panel_upgrade'],    ARRAY['Miami','Fort Lauderdale','Hollywood'], 4.9, 2, 'available', '+13055550102'),
  ('Marco Reyes', ARRAY['hvac','ac_repair','heating'],               ARRAY['Miami','Homestead','Cutler Bay'],    4.7, 0, 'available', '+13055550103'),
  ('Sara Kim',    ARRAY['carpentry','drywall','painting','general'], ARRAY['Miami','Coral Gables','Pinecrest'],  4.6, 1, 'available', '+13055550104')
on conflict do nothing;
