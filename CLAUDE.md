# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: ProJob Dispatch Orchestrator

Dynamic, AI-assisted job dispatch for ProJob Manager. Routes incoming jobs to the best-fit subcontractor (Ray Torres, Dana Walsh, Marco Reyes, Sara Kim) based on specialty, service area, current workload, and rating — instead of a fixed rule table. Escalates to manual dispatch when no confident match exists.

## Stack

Free, self-hosted stack — no per-request API cost:
- **n8n** (self-hosted) — workflow orchestration
- **Supabase** (free tier, Postgres) — data store
- **Ollama** (local LLM) — matching/decision model
- **Twilio** — SMS to dispatched subs
- **SMTP** (Gmail app password works) — escalation email to Oscar

## Files

- `01_supabase_schema.sql` — `subcontractors`, `jobs`, `dispatch_log` tables + seed roster
- `02_projob_dispatch_orchestrator.json` — importable n8n workflow (15 nodes)
- `03_setup_guide.md` — quick-start (~30 min)
- `04_click_by_click_setup.md` — detailed per-screen walkthrough
- `05_sample_job_payload.json` — happy-path test body
- `05_sample_job_payload.md` — three test variations + manual `jobs` insert for end-to-end
- `README.md` — project overview

## Workflow architecture

Linear pipeline with a branch at the confidence gate. Every node passes JSON forward; `Code` nodes mutate/build payloads, `Supabase` nodes read/write rows, `HTTP Request` calls Ollama + Twilio.

```
Webhook (POST /dispatch-job)
  └─> Supabase: Get Available Subcontractors           (filter: availability_status = 'available')
        └─> Code: Build Orchestrator Prompt            (curates job + sub fields into system/user prompts)
              └─> HTTP Request: Ask Orchestrator (Local Ollama)   (POST {OLLAMA_BASE_URL}/api/chat, format=json)
                    └─> Code: Parse Decision           (JSON.parse(ollama.message.content); fall back to escalate on failure)
                          └─> If: Needs Human?         (escalate == true  OR  confidence < 0.6)
                                ├─ true  → Log Escalation → Mark Job Escalated → Notify Oscar (Email) → Respond (Escalated)
                                └─ false → Log Decision to Supabase → Mark Job Dispatched
                                                              └─> Supabase: Lookup Sub Phone (gets contact_phone for SMS)
                                                                    └─> HTTP Request: Send SMS via Twilio
                                                                          └─> Respond (Dispatched)
```

Key node behaviors:
- **Build Orchestrator Prompt** — "tight context" rule: only fields the model needs (`id, name, specialties, service_area, rating, active_job_count`). System prompt forbids inventing subcontractor IDs and mandates JSON-only output.
- **Ask Orchestrator (Local Ollama)** — env vars `OLLAMA_BASE_URL` (default `http://localhost:11434`) and `OLLAMA_MODEL` (default `llama3.1:8b`). Requires a recent enough Ollama for `format: "json"`. In Docker, set `OLLAMA_BASE_URL=http://host.docker.internal:11434`.
- **Parse Decision** — sets `cost_usd: 0`, `model_used: response.model || 'local-ollama'`. On JSON parse failure, force-escalates with `confidence: 0`.
- **Needs Human?** — escalates when `escalate == true` OR `confidence < 0.6` (combinator: `or`).
- **Lookup Sub Phone** — Supabase `get` on `subcontractors` filtered by `selected_subcontractor_id`; supplies `contact_phone` for the SMS node.
- **Send SMS via Twilio** — generic HTTP Request + HTTP Basic Auth credential (Account SID / Auth Token). Reads `TWILIO_FROM_NUMBER` from env.
- **Notify Oscar (Email)** — SMTP `emailSend` node; recipient/subject templated from `$json.job.id` and `$json.escalation_reason`.

## Required env vars (n8n Settings → Variables)

- `OLLAMA_BASE_URL`, `OLLAMA_MODEL`
- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`
- `OSCAR_ALERT_FROM_EMAIL`, `OSCAR_ALERT_TO_EMAIL`

## Required n8n credentials

- **ProJob Supabase** — host = Project URL, key = `service_role` (NOT `anon`; the workflow writes rows)
- **ProJob SMTP** — for the escalation email
- **HTTP Basic Auth** — for Twilio (user = Account SID, password = Auth Token)

After import, find-and-replace `REPLACE_WITH_YOUR_SUPABASE_CRED_ID` (4 Supabase nodes) and `REPLACE_WITH_YOUR_SMTP_CRED_ID` (1 SMTP node) with the real credential ids.

## Editing notes

- No traditional build/test/lint pipeline. Validate by importing the JSON into n8n, applying the SQL schema to Supabase, and exercising the webhook with `05_sample_job_payload.json` (insert the `jobs` row first — the update nodes match on `id`).
- Dispatch logic (prompt, decision rules, escalation threshold) lives inside the workflow JSON, not in code. Edit `Build Orchestrator Prompt`'s `jsCode` to change matching policy; edit the `Needs Human?` threshold to change escalation sensitivity.
- Subcontractor roster is the `subcontractors` table — `INSERT` to add; no workflow change required because the filter is dynamic.
- Both notify nodes are now wired to real channels; do not regress them back to stubs without a reason.
