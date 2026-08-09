# ProJob Dispatch Orchestrator — Click-by-Click Setup

Detailed per-screen walkthrough. If you just want it running, use `03_setup_guide.md` instead.

---

## Part A — Supabase (database)

1. Go to https://supabase.com/dashboard → **New project**
2. Pick a region close to Florida, set a strong database password, click **Create new project** (wait ~1 min for provisioning)
3. In the left sidebar: **SQL Editor** → **New query**
4. Paste the full contents of `01_supabase_schema.sql`
5. Click **Run** (or press Ctrl/Cmd+Enter). You should see `Success. No rows returned`
6. **Table Editor** → confirm three tables exist:
   - `subcontractors` (4 rows: Ray Torres, Dana Walsh, Marco Reyes, Sara Kim)
   - `jobs` (0 rows)
   - `dispatch_log` (0 rows)
7. Grab credentials you'll need for n8n:
   - **Project Settings → API**:
     - **Project URL** (looks like `https://abcdefg.supabase.co`)
     - **service_role** key (click "Reveal", then copy) — this bypasses RLS so the workflow can update any row
   - ⚠️ Use the `service_role` key, **not** the `anon` key. The orchestrator writes to tables; the anon key is read-only by design.

---

## Part B — Ollama (local LLM)

1. Install Ollama from https://ollama.com/download (Mac/Linux/Windows installers available)
2. Confirm it's running:
   ```bash
   ollama --version
   ```
3. Pull a model that supports `format: "json"`:
   ```bash
   ollama pull llama3.1:8b
   ```
   (Other options: `qwen2.5:7b`, `mistral-nemo`, etc. Stick to ≥ 7B for reliable JSON.)
4. Verify it speaks JSON:
   ```bash
   curl http://localhost:11434/api/chat -d '{
     "model": "llama3.1:8b",
     "messages": [{"role":"user","content":"Reply with JSON {\"ok\": true}"}],
     "format": "json",
     "stream": false
   }'
   ```
   You should see `{"ok": true}` in `message.content`. If you get prose back, your Ollama is too old — upgrade.
5. **If n8n runs in Docker**, Ollama on `localhost` is not the same `localhost` as inside the container. Either:
   - Run Ollama on the host and use `OLLAMA_BASE_URL=http://host.docker.internal:11434` in n8n env vars (Docker Desktop / WSL2)
   - Or run Ollama in a container on the same Docker network and use `http://ollama:11434`

---

## Part C — n8n (workflow runtime)

### Install n8n

Pick one:
- **Local node**: `npx n8n` (requires Node.js 18+)
- **Docker**:
  ```bash
  docker run -it --rm \
    --name n8n \
    -p 5678:5678 \
    -v ~/.n8n:/home/node/.n8n \
    n8nio/n8n
  ```
- **Hosted free tier**: n8n.cloud has a free trial; you can use that if you'd rather not self-host.

Open the URL n8n prints (default `http://localhost:5678`).

### Create credentials

**ProJob Supabase**
1. Left sidebar → **Credentials** → **Create Credential** → search "Supabase"
2. **Host**: your `Project URL` from Supabase (e.g. `https://abcdefg.supabase.co`)
3. **Service Role Key**: paste the `service_role` key
4. Name: `ProJob Supabase` → **Save**
5. **Copy the credential id** from the URL — it's the long string after `/credentials/`. You'll paste this into the workflow JSON.

**ProJob SMTP** (for Oscar alerts)
1. **Credentials → Create** → search "SMTP"
2. Fill in your SMTP host/user/pass (Gmail requires an App Password: https://myaccount.google.com/apppasswords)
3. Name: `ProJob SMTP` → **Save**
4. Copy the credential id.

**Twilio HTTP Basic Auth**
1. **Credentials → Create** → search "HTTP Basic Auth"
2. **User**: your Twilio Account SID (starts with `AC...`)
3. **Password**: your Twilio Auth Token (find both at https://console.twilio.com/)
4. Name: `Twilio` → **Save**

### Set environment variables

1. Left sidebar → **Settings** → **Variables** (or in older versions, Settings → Environment Variables)
2. Add each of:
   - `OLLAMA_BASE_URL` → `http://host.docker.internal:11434` (or `http://localhost:11434` if n8n is on the host)
   - `OLLAMA_MODEL` → `llama3.1:8b`
   - `TWILIO_ACCOUNT_SID` → your Account SID
   - `TWILIO_AUTH_TOKEN` → your Auth Token
   - `TWILIO_FROM_NUMBER` → your Twilio-provisioned phone number (E.164, e.g. `+13055551234`)
   - `OSCAR_ALERT_FROM_EMAIL` → sender address (must match the SMTP user)
   - `OSCAR_ALERT_TO_EMAIL` → where Oscar wants escalations delivered
3. **Save** each.

### Import the workflow

1. **Workflows** → **Import from File** (or **New** → three-dot menu → **Import from File**)
2. Select `02_projob_dispatch_orchestrator.json`
3. n8n will warn that credentials need to be set. Click each warning → choose the matching credential from the dropdown.
4. Search-and-replace in the workflow JSON for the two placeholders:
   - `REPLACE_WITH_YOUR_SUPABASE_CRED_ID` → your ProJob Supabase credential id (appears on the four Supabase nodes)
   - `REPLACE_WITH_YOUR_SMTP_CRED_ID` → your ProJob SMTP credential id (appears on the email node)
   - You can also paste these into each node's **Credential** dropdown — that updates the JSON for you.
5. On the **Send SMS via Twilio** node, set the **Authentication** dropdown to the Twilio HTTP Basic Auth credential you created.
6. Click **Activate** (top-right toggle).

### Get the webhook URL

1. Open the **New Job Request** node
2. The **Webhook URL** field shows the production URL once the workflow is active. It looks like:
   `https://your-n8n.example/webhook/dispatch-job`
3. Copy it for testing.

---

## Part D — Smoke test

Use the sample payload (`05_sample_job_payload.json`) once you've added it, or paste this minimal body:

```json
{
  "id": "11111111-1111-1111-1111-111111111111",
  "service_type": "plumbing",
  "description": "Kitchen sink leaking under the cabinet",
  "city": "Miami",
  "customer_name": "Test Customer",
  "customer_phone": "+13055550000",
  "priority": "normal"
}
```

Then:
```bash
curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d @05_sample_job_payload.json
```

What to check:
- **Supabase → Table Editor → jobs**: the row's `status` is now `dispatched` and `assigned_subcontractor_id` is one of the four seeded subs
- **dispatch_log**: one new row with `confidence`, `reasoning`, `model_used = llama3.1:8b`
- **Sub's phone**: receives the SMS

To force an escalation, send a job with a city none of the subs cover (e.g. `"city": "Orlando"`). Expect: `status = escalated`, email to Oscar, no SMS sent.

---

## Maintenance

- **Add a sub**: `insert into subcontractors (...)` — no workflow change needed; the filter is dynamic
- **Change escalation threshold**: open the **Needs Human?** node and adjust the `0.6` constant
- **Swap models**: change `OLLAMA_MODEL` env var; pick one that supports `format: "json"`
- **Audit**: `select * from dispatch_log order by created_at desc limit 50;`
