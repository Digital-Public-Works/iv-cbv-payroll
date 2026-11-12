# Load Testing

k6 scripts that load test VMI. Real runs target the **demo** environment (`https://demo.divt.app`) from the loadtester EC2 instance; local runs are only for developing the scripts.

## Test files

- **`loadTestUserFlow.js`** - applicant page traffic: sync polling, employer search, payment details, summary, PDF download
- **`loadTestAPI.js`** - `POST /api/v1/invitations` at a constant rate, authenticated with an API token
- **`loadTestAll.js`** - both of the above at the same time (the closest to production traffic)
- **`common.js`** - shared settings: load profiles, thresholds, SLOs

### How user-flow sessions are created

Each virtual user (VU) calls `POST /api/load_test/sessions`, which creates a CBV flow with Argyle payroll data already in place and returns a session cookie. The endpoint only exists outside production (`development`, `test`, and `*.divt.app`). The flows it creates:

- use Argyle account `019571bc-…` ("Bob" in the mock Argyle fixtures), so **the partner must use the `mock` Argyle environment** (see Preparation)
- are tagged with `device_id = "load-test"`, so cleanup deletes only these flows and their analytics events are easy to filter out

## Load profiles

User-flow load is set by `--env PROFILE=...`:

| Profile | Shape | Use it for |
|---|---|---|
| `smoke` | 1 VU for 30s | Checking config before a real run (URL, cookie, Argyle mocking, API token) |
| `baseline` (default) | ramp to 10 VUs, about 2 min | A quick check for regressions; matches historical runs |
| `capacity` | steps at 12.5/25/50/75/100% of `MAX_VUS` (default 200), each a 1m ramp then a `STEP_HOLD` hold (default 4m), then a 2m ramp down; about 27 min | Finding where latency and errors start to degrade, and comparing fixed capacity with autoscaling |

Mixed scenario weights, picked per iteration: 77% sync polling, 10% employer search, 5% payment details, 3% summary, 5% PDF. Each scenario waits between requests the way a real user would, so one VU makes roughly 0.3–0.5 requests per second on average. Run a single scenario with `--env SCENARIO=sync|employer_search|payment_details|summary|pdf`.

Other knobs (all optional):

| Env var | Default | Meaning |
|---|---|---|
| `CLIENT_AGENCY_ID` | `sandbox` | Partner the load-test flows belong to |
| `MAX_VUS` / `STEP_HOLD` | `200` / `4m` | Size and hold time for the `capacity` profile |
| `API_RATE` | `100` | Invitations per second (API and combined tests) |
| `API_DURATION` | `2m` | API-only test length (the combined test runs the API for the whole user-flow profile) |
| `CUSTOM_ATTRIBUTES` | `{"case_number":"__UNIQUE__"}` | Invitation attributes, as JSON. Must satisfy the API user's partner's required invitation attributes. `"__UNIQUE__"` is replaced with a unique `LOAD_TEST_…` value |
| `SLA_MS` / `PDF_SLA_MS` | `2000` / `10000` | Responses slower than this are counted in `failed_slo` |

## Thresholds and metrics

Every request is tagged `slo:standard`, `slo:pdf` or `slo:setup` (session creation, which is excluded from SLOs), plus a `name` tag per endpoint.

- `http_req_duration{slo:standard}`: p95 < 500ms, p99 < 1000ms
- `http_req_duration{slo:pdf}`: p95 < `PDF_SLA_MS`
- `http_req_failed{slo:...}`: < 1%
- `checks`: > 99% for the run to pass. The run **aborts** only if checks fall below 50% (after 30s), which means misconfiguration (bad URL or cookie, endpoint disabled) rather than overload, so a capacity run always finishes.
- `failed_slo`: count of responses slower than the SLA

A failed threshold makes k6 exit non-zero but does not stop the run. For capacity runs this is expected; the useful output is where things degraded, not pass/fail.

## Running a load test against demo

### Preparation

1. **Deploy this branch's app code to demo.** The k6 scripts depend on the session endpoint marking flows `device_id = "load-test"` and completing the applicant-information step; without it, the summary page just returns a redirect.
2. **Argyle must be mocked** for the partner under test. On demo, open a Rails console (ECS exec) and check `ClientAgencyConfig.instance["sandbox"].argyle_environment`. It must be `"mock"`. With `"sandbox"`, payment details, summary and PDF call the real Argyle sandbox, which doesn't know the test account. Those requests fail, and the results would measure Argyle rather than VMI.
3. **API test user:** use a dedicated user that exists only for load testing. Its invitations are what `cleanup_invitations` deletes. Its partner must allow invitations, and `CUSTOM_ATTRIBUTES` must include that partner's required invitation attributes. Create a token in the demo console: `User.find_by(email: "...").api_access_tokens.create!.access_token`.
4. **Queues:** decide whether the Shoryuken workers run. Leave them running to include background work (Mixpanel events, etc.) in the measurement; stop the worker service to measure the web tier alone. Either way, **do the same in every run you plan to compare.**
5. **Write down the environment state** before each run: ECS web and worker task counts, task CPU/memory, `RAILS_MAX_THREADS` (Puma runs one process with 5 threads by default), Aurora min/max ACUs, and the deployed git SHA. Aurora Serverless scales itself, so record ACUs during the run as well.
6. Run k6 from the loadtester EC2 instance, not a laptop. Check that the instance still exists; it isn't defined in Terraform.

### Comparing fixed capacity with autoscaling

Run **the same command** in both configurations and compare the outputs:

1. **Without autoscaling:** demo at a fixed task count (currently 1 web task).
2. **With autoscaling:** after the autoscaling Terraform is applied to demo, starting from the same minimum task count.

Start with `smoke` to confirm everything works, then run `capacity`:

```bash
k6 run --env URL=https://demo.divt.app --env PROFILE=smoke loadTestUserFlow.js
```

```bash
K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=results/userflow-fixed-1task.html k6 run --env URL=https://demo.divt.app --env PROFILE=capacity --tag testid=userflow-fixed-1task --summary-export=results/userflow-fixed-1task.json loadTestUserFlow.js
```

To include API load, use `loadTestAll.js` with `--env API_KEY=...` (and `--env API_RATE=...`). Note that 100 invitations per second is much more load than the user flows produce, so on its own it can dominate the result.

What to compare between runs:

- p95/p99 latency and error rate **at each VU step**, shown in the web dashboard's time series
- the step at which latency or errors break down with fixed capacity, compared with the same step under autoscaling
- (autoscaling) when tasks were added relative to when load rose, and how far latency spiked before the new tasks were in service (ECS console and CloudWatch)
- ECS CPU/memory, Aurora ACUs/CPU/connections, and ALB target response time and 5xx counts (CloudWatch) over the same window

### Cleanup

Run these from a Rails console or shell on demo after each run:

```bash
bin/rails 'load_test:cleanup_sessions[true]'
```

```bash
bin/rails 'load_test:cleanup_invitations[loadtest-user@example.com,2026-11-12 09:00,true]'
```

- `cleanup_sessions` deletes every flow tagged `device_id = "load-test"`, with its payroll accounts (including discarded ones), webhook events and applicant. Leave off `[true]` to be asked for confirmation first.
- `cleanup_invitations` deletes the given user's invitations created at or after that time, along with their applicants. Invitations that have been opened are kept.

## Developing locally

Local runs are for working on the scripts, not for measuring anything. Install k6 (`brew install k6`, or see https://grafana.com/docs/k6/latest/set-up/install-k6/), start the app (`bin/rails server`), then:

```bash
k6 run --env URL=http://localhost:3000 --env PROFILE=smoke --env SCENARIO=sync loadTestUserFlow.js
```

`k6 inspect --env URL=http://localhost:3000 loadTestUserFlow.js` loads a script and prints its resolved options without sending any traffic, which is a quick way to check edits.

Payment details, summary and PDF need your local `sandbox` partner set to the `mock` Argyle environment (see Preparation step 2).

### Grafana (optional)

`docker-compose up` starts InfluxDB and Grafana (http://localhost:3001, admin/admin). Add an InfluxDB data source (`http://influxdb:8086`, database `k6`), import dashboard [13719](https://grafana.com/grafana/dashboards/13719-k6-load-testing-results-by-groups/), and run k6 with `K6_OUT=influxdb`. The built-in `K6_WEB_DASHBOARD` shown above is usually enough.

## Loadtester EC2 setup

```bash
sudo dnf install https://dl.k6.io/rpm/repo.rpm && sudo dnf install k6
```

```bash
git clone https://github.com/Digital-Public-Works/iv-cbv-payroll.git && cd iv-cbv-payroll/load_testing && mkdir -p results
```
