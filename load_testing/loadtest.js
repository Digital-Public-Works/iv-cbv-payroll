import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Counter } from 'k6/metrics';

export let options = {
    vus: 0, // start at 0 users, and ramp up linearly
    stages: [
        { duration: '60s', target: 10 },
        { duration: '30s', target: 10 },
        { duration: '30s', target: 0 },
    ],
    maxRedirects: 0,
    thresholds: {
        // bail early if more than 10% of checks are failing (bad cookie?)
        checks: [{ threshold: 'rate>0.1', abortOnFail: true }],
        // measure against our SLO for p95, p99, and max durations
        failed_slo: ['count<=0'],
        http_req_duration: ['p(95)<500', 'p(99)<1000', 'max<2000'],
    },
    summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

const SLA_IN_MILLISECONDS = 2000;
const COOKIES = __ENV.COOKIES ? __ENV.COOKIES.split(',') : [];
const URL = __ENV.URL;
const SCENARIO = __ENV.SCENARIO || 'mixed'; // 'mixed', 'sync', 'summary', 'pdf'
const failedSloCounter = new Counter("failed_slo");

if(COOKIES.length === 0) {
    throw new Error("COOKIES environment variable is required. Run: bin/rails 'load_test:seed_sessions[100]'");
}

if(URL === undefined) {
    throw new Error("URL environment variable is required");
}

// Get a unique cookie for each virtual user
function getCookie() {
    return COOKIES[__VU % COOKIES.length];
}

// Get a unique account ID for each virtual user (matches the test data pattern)
function getAccountId() {
    return `test_account_${__VU % COOKIES.length}`;
}

export default function () {
    const cookie = getCookie();
    const headers = {
        'Cookie': `_iv_cbv_payroll_session=${cookie}`,
        'Accept': 'text/html,application/xhtml+xml,application/xml',
    };

    // Weighted distribution based on where users spend time in the flow
    const scenario = SCENARIO === 'mixed' ? selectScenario() : SCENARIO;

    switch(scenario) {
        case 'sync':
            testSynchronization(headers);
            break;
        case 'payment_details':
            testPaymentDetails(headers);
            break;
        case 'summary':
            testSummary(headers);
            break;
        case 'pdf':
            testPdfGeneration(headers);
            break;
        case 'employer_search':
            testEmployerSearch(headers);
            break;
    }
}

function selectScenario() {
    const rand = Math.random();

    // Distribution based on typical user time per page:
    // - 50% Synchronization (longest wait, most DB polling)
    // - 20% Payment details review
    // - 15% Summary page
    // - 10% Employer search
    // - 5% PDF generation

    if (rand < 0.50) return 'sync';
    if (rand < 0.70) return 'payment_details';
    if (rand < 0.85) return 'summary';
    if (rand < 0.95) return 'employer_search';
    return 'pdf'; }

function testSynchronization(headers) {
    group("Synchronization polling (DB intensive)", () => {
        const accountId = getAccountId();
        const response = http.post(
            `${URL}/cbv/synchronizations`,
            JSON.stringify({ user: { account_id: accountId } }),
            {
                headers: {
                    ...headers,
                    'Content-Type': 'application/json',
                    'Accept': 'text/vnd.turbo-stream.html',
                }
            }
        );

        check(response, {
            'synchronization check succeeded': (r) => r.status === 200,
        });

        if (response.timings.duration > SLA_IN_MILLISECONDS) {
            failedSloCounter.add(1);
        }
    });

    // Realistic polling interval
    sleep(3);
}

function testPaymentDetails(headers) {
    group("Payment details (DB + aggregation)", () => {
        const accountId = getAccountId();
        const response = http.get(
            `${URL}/cbv/payment_details?user[account_id]=${accountId}`,
            { headers }
        );

        check(response, {
            'payment details loaded': (r) => r.status === 200,
        });

        if (response.timings.duration > SLA_IN_MILLISECONDS) {
            failedSloCounter.add(1);
        }
    });

    // Time reviewing payment details
    sleep(15);
}

function testSummary(headers) {
    group("Summary page (aggregation)", () => {
        const response = http.get(
            `${URL}/cbv/summary`,
            { headers }
        );

        check(response, {
            'summary loaded': (r) => r.status === 200,
        });

        if (response.timings.duration > SLA_IN_MILLISECONDS) {
            failedSloCounter.add(1);
        }
    });

    // Time reviewing summary
    sleep(10);
}

function testPdfGeneration(headers) {
    group("PDF generation (CPU intensive)", () => {
        const response = http.get(
            `${URL}/cbv/submit.pdf`,
            {
                headers: {
                    ...headers,
                    'Accept': 'application/pdf',
                }
            }
        );

        check(response, {
            'pdf generated': (r) => r.status === 200,
            'pdf content type': (r) => r.headers['Content-Type'] && r.headers['Content-Type'].includes('pdf'),
        });

        if (response.timings.duration > SLA_IN_MILLISECONDS) {
            failedSloCounter.add(1);
        }
    });

    // PDFs are downloaded less frequently
    sleep(30);
}

function testEmployerSearch(headers) {
    console.log("hi")
    group("Employer search page", () => {
        console.log("hi2")
        const response = http.get(
            `${URL}/cbv/employer_search`,
            { headers }
        );
        console.log("hi3")

        check(response, {
            'employer search loaded': (r) => r.status === 200,
        });
        console.log("hi4")

        if (response.timings.duration > SLA_IN_MILLISECONDS) {
            failedSloCounter.add(1);
        }
    });

    // Time searching for employer
    sleep(20);
}

// vim: expandtab sw=4 ts=4
