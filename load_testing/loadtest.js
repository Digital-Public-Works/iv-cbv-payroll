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
const TOKENS = __ENV.TOKENS ? __ENV.TOKENS.split(',') : [];
const URL = __ENV.URL;
const SCENARIO = __ENV.SCENARIO || 'mixed'; // 'mixed', 'sync', 'summary', 'pdf'
const CLIENT_AGENCY_ID = __ENV.CLIENT_AGENCY_ID || 'sandbox';
const LOAD_TEST_SCENARIO = __ENV.LOAD_TEST_SCENARIO || 'synced'; // 'synced', 'pending', 'failed'
const USE_DYNAMIC_SESSIONS = __ENV.USE_DYNAMIC_SESSIONS === 'true';
const failedSloCounter = new Counter("failed_slo");

if(!USE_DYNAMIC_SESSIONS && COOKIES.length === 0 && TOKENS.length === 0) {
    throw new Error("Either COOKIES, TOKENS, or USE_DYNAMIC_SESSIONS=true is required");
}

if(URL === undefined) {
    throw new Error("URL environment variable is required");
}

// Get a unique cookie or token for each virtual user
function getCookie() {
    return COOKIES[__VU % COOKIES.length];
}

function getToken() {
    return TOKENS[__VU % TOKENS.length];
}

// Get a unique account ID for each virtual user (matches the test data pattern)
function getAccountId() {
    return '0199a235-3e16-a138-f7a8-f2069507768d';
}

export default function () {
    let headers = {
        'Accept': 'text/html,application/xhtml+xml,application/xml',
    };
    let accountId = getAccountId(); // Default hardcoded account ID
    let csrfToken = null;

    // Three modes: dynamic sessions, tokens, or pre-baked cookies
    if (USE_DYNAMIC_SESSIONS) {
        // Request a fresh session from the dev endpoint
        const sessionResponse = http.post(`${URL}/api/load_test/sessions`, JSON.stringify({
            client_agency_id: CLIENT_AGENCY_ID,
            scenario: LOAD_TEST_SCENARIO
        }), {
            headers: {
                'Content-Type': 'application/json'
            }
        });

        if (sessionResponse.status === 201) {
            // Extract session cookie from Set-Cookie header (Rails automatically encrypts it)
            const sessionCookie = sessionResponse.cookies['_iv_cbv_payroll_session'];
            if (sessionCookie && sessionCookie[0]) {
                headers['Cookie'] = `_iv_cbv_payroll_session=${sessionCookie[0].value}`;

                // Extract account_id and csrf_token from response body
                const sessionData = JSON.parse(sessionResponse.body);
                accountId = sessionData.account_id;
                csrfToken = sessionData.csrf_token;
            } else {
                console.error('No session cookie in response');
                return;
            }
        } else {
            console.error('Failed to create session:', sessionResponse.status, sessionResponse.body);
            return;
        }
    } else if (TOKENS.length > 0) {
        // Use token to get session cookie
        const token = getToken();
        const entryResponse = http.get(`${URL}/cbv/flow_entry?token=${token}`, {
            headers,
            redirects: 0
        });

        const sessionCookie = entryResponse.cookies['_iv_cbv_payroll_session'];
        if (sessionCookie && sessionCookie[0]) {
            headers['Cookie'] = `_iv_cbv_payroll_session=${sessionCookie[0].value}`;
        }
    } else {
        // Using pre-baked cookies
        const cookie = getCookie();
        headers['Cookie'] = `_iv_cbv_payroll_session=${cookie}`;
    }

    // Weighted distribution based on where users spend time in the flow
    const scenario = SCENARIO === 'mixed' ? selectScenario() : SCENARIO;

    switch(scenario) {
        case 'sync':
            testSynchronization(headers, accountId, csrfToken);
            break;
        case 'payment_details':
            testPaymentDetails(headers, accountId);
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
    // TODO: should add another load test for generating invitations as a separate load test. Create 10k invitations
    return 'pdf'; }

function testSynchronization(headers, accountId, csrfToken) {
    group("Synchronization polling (DB intensive)", () => {
        console.log("sync test")
        console.log("accountid:", accountId)
        console.log("headers:", headers)
        console.log("cookie:", headers["Cookie"])

        const requestHeaders = {
            ...headers,
            'Content-Type': 'application/json',
            'Accept': 'text/vnd.turbo-stream.html',
        };

        // Add CSRF token if available (for dynamic sessions)
        if (csrfToken) {
            requestHeaders['X-CSRF-Token'] = csrfToken;
        }

        const response = http.patch(
            `${URL}/cbv/synchronizations?user%5Baccount_id%5D=${accountId}`, {},
            { headers: requestHeaders }
        );

        console.log("response")
        console.log(JSON.stringify(response, null, 2))

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

function testPaymentDetails(headers, accountId) {
    group("Payment details (DB + aggregation)", () => {
        const response = http.get(
            `${URL}/cbv/payment_details?user%5Baccount_id%5D=${accountId}`,
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
        console.log("request")
        console.log(JSON.stringify(headers, null, 2))
        const response = http.get(
            `${URL}/cbv/employer_search`,
            { headers }
        );
        console.log("response")
        console.log(JSON.stringify(response, null, 2))

        check(response, {
            'is Status 200': (r) => r.status === 200,
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
