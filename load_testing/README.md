# Load Testing

k6 scripts that load test VMI. Real runs target the **demo** environment (`https://demo.divt.app`) from the loadtester EC2 instance; local runs are only for developing the scripts.

## Test files

- **`loadTestUserFlow.js`** - applicant traffic in a realistic mix: sync polling, page views, front-end analytics events, signed Argyle webhooks, payment details, summary, PDF download
- **`loadTestAPI.js`** - `POST /api/v1/invitations` at a constant rate, authenticated with an API token
- **`loadTestAll.js`** - both of the above at the same time (the most realistic load)
- **`common.js`** - shared settings: load profiles, scenario weights, thresholds, SLOs

### How user-flow sessions are created

Each virtual user (VU) calls `POST /api/load_test/sessions`, which creates a CBV flow with Argyle payroll data already in place and returns a session cookie. The endpoint only works outside production (`development`, `test`, and `*.divt.app` hosts); elsewhere it returns 403. The flows it creates:

- use Argyle account `019571bc-…` ("Bob" in the mock Argyle fixtures), so **the partner must use the `mock` Argyle environment**
- are tagged with `device_id = "load-test"`, so cleanup deletes only these flows, and analytics events from them are not recorded
- get a unique `argyle_user_id` (`load-test-…`), returned in the response, so the webhook scenario can send Argyle webhooks for the flow

## Load profiles

User-flow load is set by `--env PROFILE=...`:

| Profile | Shape | Use it for |
|---|---|---|
| `smoke` | 1 VU for 30s | Checking config before a real run (URL, cookie, Argyle mocking, API token) |
| `baseline` (default) | ramp to 10 VUs, about 2 min | A quick check for regressions; matches historical runs |
| `capacity` | steps at 12.5/25/50/75/100% of `MAX_VUS` (default 400, so 50/100/200/300/400 VUs), each a 1m ramp then a `STEP_HOLD` hold (default 4m), then a 2m ramp down; about 27 min | Finding where latency and errors start to degrade, and comparing fixed capacity with autoscaling |

Each iteration picks one scenario by the weights in `SCENARIO_WEIGHTS` (`common.js`) and makes one request, so the weights are the request mix (see [Traffic model](#traffic-model)):

| Scenario | Share | Request |
|---|---|---|
| `sync` | 34% | `PATCH /cbv/synchronizations` (status polling) |
| `employer_search` | 25% | `GET /cbv/employer_search`; also stands in for the other light page views (home, entry, add-job pages, etc.) |
| `user_event` | 19% | `POST /api/events/user_action`, the front-end analytics call. Events from load-test traffic (k6 user agent or `load-test` device) are not sent to analytics, so this measures the request itself, not the analytics jobs a real event would enqueue |
| `webhook` | 19% | Signed `POST /webhooks/argyle/events`. Each VU walks a fresh pending flow through a sync (`accounts.updated` ×2, `identities.added`, `paystubs.partially_synced`, `paystubs.fully_synced`, `users.fully_synced`); completing the sync builds the Argyle report from the mock fixtures, as in production |
| `payment_details` / `summary` / `pdf` | 1% each | The heavy pages (`/cbv/payment_details`, `/cbv/summary`, `/cbv/submit.pdf`) |

After each request a VU sleeps as a user (or Argyle) would, about 5.2s on average, so **one VU makes about 0.19–0.2 requests per second**. The webhook scenario also creates a new session every 6 webhooks; those requests are tagged `slo:setup`. Run a single scenario with `--env SCENARIO=<name>`.

`URL` (the target, e.g. `http://localhost:3000`) is required for every script, and `API_KEY` (an API access token) for `loadTestAPI.js` and `loadTestAll.js`. Everything else is optional:

| Env var | Default | Meaning |
|---|---|---|
| `CLIENT_AGENCY_ID` | `sandbox` | Partner the load-test flows belong to |
| `MAX_VUS` / `STEP_HOLD` | `400` / `4m` | Size and hold time for the `capacity` profile |
| `API_RATE` | `2` | Invitations per second (API and combined tests). 2 is the planning target; use 5 as a stress test |
| `API_DURATION` | `2m` | API-only test length (the combined test runs the API for the whole user-flow profile) |
| `CUSTOM_ATTRIBUTES` | `{"case_number":"__UNIQUE__"}` | Invitation attributes, as JSON. Must satisfy the API user's partner's required invitation attributes. `"__UNIQUE__"` is replaced with a unique `LOAD_TEST_…` value |
| `SLA_MS` / `PDF_SLA_MS` | `2000` / `10000` | Responses slower than this are counted in `failed_slo` |
| `WEBHOOK_SECRET` | `mock` | Secret used to sign webhook payloads; `mock` matches the `mock` Argyle environment |

## Traffic model

The weights and targets are planning numbers for expected future volume, with headroom. They are set in `common.js` and the env-var defaults; update them there if the plan changes.

- **What is modeled:** applicant requests, Argyle webhooks and invitation API calls, the traffic that grows with the number of invitations. Requests that never reach a controller (redirects for unknown subdomains, 404s, blocked hosts, static files) take a few milliseconds each, don't grow with invitations, and are not modeled.
- **Mix:** sync polling dominates, followed by light page views, front-end analytics events and webhooks; the heavy pages (payment details, summary, PDF) are a small share. Each scenario's weight is in the table above.
- **Planning peak:** **about 16–20 requests per second** of combined applicant, webhook and invitation traffic, with invitations at **about 2 per second** (hence `API_RATE=2`). The peak is a busy-minute figure, so it is already on the high side for sustained load.

**Reading a capacity run:** at ~0.19 requests per second per VU, the steps are roughly:

| Step | VUs | Requests/second | Relative to the planning peak |
|---|---|---|---|
| 1 | 50 | ~10 | below |
| 2 | 100 | ~19 | about the planning peak |
| 3 | 200 | ~38 | **2× margin: the go/no-go step** |
| 4 | 300 | ~56 | 3× |
| 5 | 400 | ~75 | 4× |

Go/no-go: **at the step that delivers about 2× the planning peak (≈36–40 requests/second, normally step 3), p95 should stay under 500ms and errors under 1%.** Check the actual request rate per step in the dashboard (`http_reqs`) rather than relying on the VU count. If that step fails, check where the time went: a web-tier limit (ECS CPU high, database comfortable) means more web capacity (tasks, threads or autoscaling) is needed before volume reaches the planning peak.

## Thresholds and metrics

Every request is tagged `slo:standard`, `slo:pdf` or `slo:setup` (session creation, which is excluded from SLOs), plus a `name` tag per endpoint.

- `http_req_duration{slo:standard}`: p95 < 500ms, p99 < 1000ms
- `http_req_duration{slo:pdf}`: p95 < `PDF_SLA_MS`
- `http_req_failed{slo:...}`: < 1%
- `checks`: > 99% for the run to pass. The run **aborts** only if checks fall below 50% (after 30s), which means misconfiguration (bad URL or cookie, endpoint disabled) rather than overload, so a capacity run always finishes.
- `failed_slo`: count of responses slower than the SLA

A failed threshold makes k6 exit non-zero but does not stop the run. For capacity runs this is expected; the useful output is where things degraded, not pass/fail.

## Developing locally

Local runs are for working on the scripts, not for measuring anything. Install k6 (`brew install k6`, or see https://grafana.com/docs/k6/latest/set-up/install-k6/), start the app (`bin/rails server`), then:

```bash
k6 run --env URL=http://localhost:3000 --env PROFILE=smoke --env SCENARIO=sync loadTestUserFlow.js
```

`k6 inspect --env URL=http://localhost:3000 loadTestUserFlow.js` loads a script and prints its resolved options without sending any traffic, which is a quick way to check edits.

Payment details, summary, PDF and webhooks need your local `sandbox` partner set to the `mock` Argyle environment (with `sandbox`, they call the real Argyle sandbox, which doesn't know the test account, and webhooks signed with the `mock` secret are rejected with 401). From `app/`:

```bash
bin/rails runner 'PartnerConfig.find_by!(partner_id: "sandbox").update_column(:argyle_environment, "mock")'
```

(`update_column` because the partner-config importer only accepts `sandbox` and `production`.) Smoke each scenario on its own (`--env SCENARIO=webhook`, `user_event`, …) so a failure points at one endpoint, and clean up afterwards with `bin/rails 'load_test:cleanup_sessions[true]'`. Latency thresholds failing locally is normal: development mode is much slower than production.

### Grafana (optional)

`docker-compose up` starts InfluxDB and Grafana (http://localhost:3001, admin/admin). Add an InfluxDB data source (`http://influxdb:8086`, database `k6`), import dashboard [13719](https://grafana.com/grafana/dashboards/13719-k6-load-testing-results-by-groups/), and run k6 with `K6_OUT=influxdb`. The built-in web dashboard (`K6_WEB_DASHBOARD=true`, optionally with `K6_WEB_DASHBOARD_EXPORT=results/<name>.html`) is usually enough.

## Loadtester EC2 setup

```bash
sudo dnf install https://dl.k6.io/rpm/repo.rpm && sudo dnf install k6
```

```bash
git clone https://github.com/Digital-Public-Works/iv-cbv-payroll.git && cd iv-cbv-payroll/load_testing && mkdir -p results
```
