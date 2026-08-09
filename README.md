# ProJob Dispatch Orchestrator

Dynamic, AI-assisted job dispatch for ProJob Manager — routes incoming jobs to the best-fit
subcontractor (Ray Torres, Dana Walsh, Marco Reyes, Sara Kim) based on specialty, service area,
current workload, and rating, instead of a fixed rule table. Escalates to manual dispatch when
no confident match exists.

Runs on a fully free stack: self-hosted n8n, Supabase (free tier), and a local Ollama model —
no per-request API cost.

## Files
- `01_supabase_schema.sql` — database schema (subcontractors, jobs, dispatch_log tables + seed roster)
- `02_projob_dispatch_orchestrator.json` — importable n8n workflow (15 nodes)
- `03_setup_guide.md` — quick-start setup (~30 min)
- `04_click_by_click_setup.md` — detailed click-by-click walkthrough
- `05_sample_job_payload.json` / `.md` — happy-path test body + escalation/edge-case variants

## Stack
n8n (self-hosted) → Supabase (Postgres) → Ollama (local LLM, free)
SMS via Twilio · escalation email via SMTP

## Flow
Webhook → fetch available subs → build prompt → call Ollama (JSON mode) → parse decision →
confidence gate (≥ 0.6) → either SMS the chosen sub (dispatched) or email Oscar (escalated),
logging every run to `dispatch_log`.
