# ProJob Dispatch Orchestrator — Quick Start

Five steps, ~30 minutes. Need-for-click details live in `04_click_by_click_setup.md`.

## 1. Apply the Supabase schema

- Create a free Supabase project: https://supabase.com/dashboard
- Open **SQL Editor → New query**
- Paste the contents of `01_supabase_schema.sql` and run it
- Confirm three tables exist: `subcontractors` (with 4 seeded rows), `jobs`, `dispatch_log`

## 2. Stand up Ollama locally

- Install: https://ollama.com/download
- Pull a model with JSON-mode support:
  ```bash
  ollama pull llama3.1:8b
  ```
- Confirm it's serving on `http://localhost:11434`:
  ```bash
  curl http://localhost:11434/api/tags
  ```

## 3. Stand up n8n (self-hosted)

- Easiest: `npx n8n` or Docker — see https://docs.n8n.io/hosting/
- Note the webhook base URL n8n prints (e.g. `http://localhost:5678`)

## 4. Import the workflow + set credentials

- In n8n: **Workflows → Import from File** → select `02_projob_dispatch_orchestrator.json`
- **Credentials → Create**:
  - **ProJob Supabase** (Supabase API): paste your project URL + `service_role` key
    - Find both under Supabase **Project Settings → API**
  - **ProJob SMTP** (SMTP): host/user/pass for the mailbox that will send Oscar's alerts
  - **HTTP Basic Auth** (for Twilio): username = Twilio Account SID, password = Auth Token
- **Settings → Variables** (n8n env vars):
  - `OLLAMA_BASE_URL` → `http://host.docker.internal:11434` (if n8n is in Docker) or `http://localhost:11434`
  - `OLLAMA_MODEL` → `llama3.1:8b`
  - `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`
  - `OSCAR_ALERT_FROM_EMAIL`, `OSCAR_ALERT_TO_EMAIL`
- Find-and-replace in the workflow JSON (or in each Supabase / SMTP node):
  - `REPLACE_WITH_YOUR_SUPABASE_CRED_ID` → real Supabase credential id
  - `REPLACE_WITH_YOUR_SMTP_CRED_ID` → real SMTP credential id

## 5. Activate and test

- Open the imported workflow, click **Activate** (top right)
- Copy the webhook URL n8n shows for the **New Job Request** node (POST `/dispatch-job`)
- Send a test job — see `05_sample_job_payload.md` for the curl:
  ```bash
  curl -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d @05_sample_job_payload.json
  ```
- Expected: `dispatch_log` row appears in Supabase; if confidence ≥ 0.6, the chosen sub gets an SMS and the job's `status` becomes `dispatched`. If low confidence, the job is `escalated` and Oscar gets an email.

## Troubleshooting

- **"Failed to parse orchestrator response"** → your Ollama is too old. Upgrade to ≥ 0.5.0 or pick a different model.
- **HTTP 404 on the webhook** → workflow isn't activated, or you hit the wrong n8n instance.
- **SMS never arrives** → check Twilio logs; the `From` number must be verified (trial accounts).
