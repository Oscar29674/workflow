# Sample test job payload

This file documents the JSON body the **New Job Request** webhook expects, plus a few variations for forcing different code paths.

## The happy path

`05_sample_job_payload.json`:

```json
{
  "id": "11111111-1111-1111-1111-111111111111",
  "service_type": "plumbing",
  "description": "Kitchen sink leaking under the cabinet, water pooling on the floor.",
  "city": "Miami",
  "customer_name": "Test Customer",
  "customer_phone": "+13055550000",
  "priority": "normal"
}
```

Fire it:

```bash
curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d @05_sample_job_payload.json
```

Expected: Ray Torres is chosen (specialty `plumbing`, service area includes Miami, low active_job_count). He gets an SMS. `jobs.status = dispatched`. One `dispatch_log` row with `confidence > 0.6`.

## Forced escalation: bad city

```bash
cat > /tmp/bad_city.json <<'EOF'
{
  "id": "22222222-2222-2222-2222-222222222222",
  "service_type": "plumbing",
  "description": "Burst pipe",
  "city": "Orlando",
  "customer_name": "Out of area",
  "customer_phone": "+14075550000",
  "priority": "high"
}
EOF
curl -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" -d @/tmp/bad_city.json
```

Expected: no sub covers Orlando → `escalate = true`. Job status becomes `escalated`. Oscar gets the email. No SMS sent.

## Specialty match edge case

```bash
cat > /tmp/hvac.json <<'EOF'
{
  "id": "33333333-3333-3333-3333-333333333333",
  "service_type": "hvac",
  "description": "AC blowing warm air",
  "city": "Homestead",
  "customer_name": "Hot House",
  "customer_phone": "+13055557777",
  "priority": "urgent"
}
EOF
curl -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" -d @/tmp/hvac.json
```

Expected: Marco Reyes (hvac, Homestead in service area, lowest active_job_count) wins.

## Notes on the `id` field

- The webhook doesn't insert the job itself — ProJob Manager is expected to insert into `jobs` and call the webhook with that row's id.
- The matching-column on the `Mark Job Dispatched` / `Mark Job Escalated` update nodes is `id`, so the row must already exist in `jobs` for the update to land.
- For pure end-to-end testing without ProJob Manager, INSERT the row manually first:
  ```sql
  insert into jobs (id, service_type, city, description, customer_name, customer_phone, priority)
  values ('11111111-1111-1111-1111-111111111111', 'plumbing', 'Miami', 'Test', 'Test Customer', '+13055550000', 'normal');
  ```
  Then fire the webhook.
