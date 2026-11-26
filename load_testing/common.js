import { Counter } from 'k6/metrics';

// Shared constants
export const URL = __ENV.URL;
export const CLIENT_AGENCY_ID = __ENV.CLIENT_AGENCY_ID || 'sandbox';

// Response-time SLOs. Every request is tagged with an `slo` tag so thresholds
// can be applied per class:
//   standard - normal page/API requests
//   argyle   - requests that wait on Argyle API calls, with simulated latency
//   pdf      - wkhtmltopdf rendering, which is expected to be much slower
//   setup    - load-test session creation; not real user traffic, excluded from SLOs
export const SLA_IN_MILLISECONDS = Number(__ENV.SLA_MS || 2000);
export const PDF_SLA_IN_MILLISECONDS = Number(__ENV.PDF_SLA_MS || 10000);
export const SLO = { standard: 'standard', argyle: 'argyle', pdf: 'pdf', setup: 'setup' };

// Pause after each request (seconds). Only the per-VU request rate depends on
// these; the request mix is set by SCENARIO_WEIGHTS. With the weights below a
// VU averages ~5.2s of sleep per request, so ~0.19 requests/second.
export const SIMULATE_DELAY_EMPLOYER_SEARCH_S = 10; // also stands in for other page views
export const SIMULATE_DELAY_SYNC_POLLING_S = 2;
export const SIMULATE_DELAY_PAYMENT_DETAILS_S = 20;
export const SIMULATE_DELAY_SUMMARY_S = 3;
export const SIMULATE_DELAY_PDF_DOWNLOAD_S = 30;
export const SIMULATE_DELAY_USER_EVENT_S = 5;
export const SIMULATE_DELAY_WEBHOOK_S = 3;

// Share of requests per scenario in the mixed run, in percent. Each iteration
// makes exactly one request, so these are request shares (see README
// "Traffic model"):
//   sync            - PATCH /cbv/synchronizations (status polling)
//   employer_search - employer search page; also stands in for the other
//                     light page views (home, entry, add-job pages, etc.)
//   user_event      - POST /api/events/user_action (front-end analytics)
//   webhook         - signed Argyle webhooks, a full sync sequence per flow
//   payment_details, summary, pdf - the heavy pages
export const SCENARIO_WEIGHTS = {
    sync: 34,
    employer_search: 25,
    user_event: 19,
    webhook: 19,
    payment_details: 1,
    summary: 1,
    pdf: 1,
};

// Signs webhook payloads. Partners on the `mock` Argyle environment use "mock".
export const WEBHOOK_SECRET = __ENV.WEBHOOK_SECRET || 'mock';

// Shared metrics
export const failedSloCounter = new Counter("failed_slo");

// Validate required environment variables
if(URL === undefined) {
    throw new Error("URL environment variable is required");
}

// Load profiles for the user-flow VUs. Select with --env PROFILE=<name>.
//   smoke    - 1 VU for 30s; sanity-check config, cookies and Argyle mocking
//   baseline - the historical 10-VU run (~2 min); quick regression check
//   capacity - stepped ramp to MAX_VUS with long holds, to find the point where
//              latency/errors break down. Holds are long enough for ECS
//              autoscaling to react, so the same profile can be run with and
//              without autoscaling and compared directly.
export const PROFILE = __ENV.PROFILE || 'baseline';
const MAX_VUS = Number(__ENV.MAX_VUS || 400);
const STEP_HOLD = __ENV.STEP_HOLD || '4m';

const PROFILES = {
    smoke: [
        { duration: '30s', target: 1 },
    ],
    baseline: [
        { duration: '60s', target: 10 },
        { duration: '30s', target: 10 },
        { duration: '30s', target: 0 },
    ],
    capacity: [0.125, 0.25, 0.5, 0.75, 1].flatMap((fraction) => {
        const target = Math.max(1, Math.round(MAX_VUS * fraction));
        return [
            { duration: '1m', target },
            { duration: STEP_HOLD, target },
        ];
    }).concat([{ duration: '2m', target: 0 }]),
};

export function userFlowStages() {
    const stages = PROFILES[PROFILE];
    if (!stages) {
        throw new Error(`Unknown PROFILE "${PROFILE}". Use one of: ${Object.keys(PROFILES).join(', ')}`);
    }
    return stages;
}

// Total length of the selected profile, e.g. "1380s"; lets the API scenario
// run for the same window as the user flows in loadTestAll.js.
export function userFlowDuration() {
    const seconds = userFlowStages().reduce((total, stage) => total + parseDuration(stage.duration), 0);
    return `${seconds}s`;
}

function parseDuration(duration) {
    const match = /^(\d+)(s|m|h)$/.exec(duration);
    if (!match) throw new Error(`Unsupported duration "${duration}"`);
    return Number(match[1]) * { s: 1, m: 60, h: 3600 }[match[2]];
}

// Options shared by every script.
export const commonOptions = {
    // Rails redirects on auth/state errors; following them would turn a failure
    // into a 200 from some other page.
    maxRedirects: 0,
    thresholds: {
        checks: [
            // Abort only when nearly everything fails (bad URL, bad cookie,
            // endpoint disabled) - not when the app is merely overloaded, so a
            // capacity run still completes and shows where it degraded.
            { threshold: 'rate>0.5', abortOnFail: true, delayAbortEval: '30s' },
            // Pass/fail criterion for the run.
            'rate>0.99',
        ],
        failed_slo: ['count<=0'],
        [`http_req_duration{slo:${SLO.standard}}`]: ['p(95)<500', 'p(99)<1000'],
        [`http_req_duration{slo:${SLO.argyle}}`]: ['p(95)<1500', 'p(99)<3000'],
        [`http_req_duration{slo:${SLO.pdf}}`]: [`p(95)<${PDF_SLA_IN_MILLISECONDS}`],
        [`http_req_failed{slo:${SLO.standard}}`]: ['rate<0.01'],
        [`http_req_failed{slo:${SLO.argyle}}`]: ['rate<0.01'],
        [`http_req_failed{slo:${SLO.pdf}}`]: ['rate<0.01'],
    },
    summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// Count responses that blow past the SLA for their class.
export function checkSlo(response, slo = SLO.standard) {
    const limit = slo === SLO.pdf ? PDF_SLA_IN_MILLISECONDS : SLA_IN_MILLISECONDS;
    if (response.timings.duration > limit) {
        failedSloCounter.add(1, { slo });
    }
}

// vim: expandtab sw=4 ts=4
