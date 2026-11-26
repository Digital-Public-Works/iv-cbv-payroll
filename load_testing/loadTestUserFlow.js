import http from 'k6/http';
import crypto from 'k6/crypto';
import { sleep, check, group } from 'k6';
import {
    URL,
    CLIENT_AGENCY_ID,
    SLO,
    checkSlo,
    commonOptions,
    userFlowStages,
    SIMULATE_DELAY_SYNC_POLLING_S,
    SIMULATE_DELAY_PAYMENT_DETAILS_S,
    SIMULATE_DELAY_SUMMARY_S,
    SIMULATE_DELAY_PDF_DOWNLOAD_S,
    SIMULATE_DELAY_EMPLOYER_SEARCH_S,
    SIMULATE_DELAY_USER_EVENT_S,
    SIMULATE_DELAY_WEBHOOK_S,
    SCENARIO_WEIGHTS,
    WEBHOOK_SECRET,
} from './common.js';

export let options = {
    ...commonOptions,
    stages: userFlowStages(), // PROFILE env var; see common.js
};

// 'mixed', or one of the SCENARIO_WEIGHTS keys in common.js
const SCENARIO = __ENV.SCENARIO || 'mixed';
if (SCENARIO !== 'mixed' && !(SCENARIO in SCENARIO_WEIGHTS)) {
    throw new Error(`Unknown SCENARIO "${SCENARIO}". Use mixed or one of: ${Object.keys(SCENARIO_WEIGHTS).join(', ')}`);
}

// Session manager - reuses sessions across iterations per VU
const getOrCreateSession = (() => {
    let pendingSession;  // For sync tests
    let syncedSession;   // For everything else

    return (scenario) => {
        if (scenario === 'sync') {
            if (!pendingSession) {
                pendingSession = createSession('pending');
            }
            return pendingSession;
        } else {
            if (!syncedSession) {
                syncedSession = createSession('synced');
            }
            return syncedSession;
        }
    };
})();

let webhookFlow = null;

export default function () {
    const scenario = SCENARIO === 'mixed' ? selectScenario() : SCENARIO;

    // Webhooks come from Argyle, not the applicant's browser: no cookie needed.
    if (scenario === 'webhook') {
        testWebhook();
        return;
    }

    const session = getOrCreateSession(scenario);

    if (session) {
        executeTestScenario(scenario, session);
    }
}

function createSession(dataState) {
    const headers = {
        'Accept': 'text/html,application/xhtml+xml,application/xml',
    };

    // Request a fresh session from the dev endpoint
    const sessionResponse = http.post(`${URL}/api/load_test/sessions`, JSON.stringify({
        client_agency_id: CLIENT_AGENCY_ID,
        scenario: dataState
    }), {
        headers: {
            'Content-Type': 'application/json'
        },
        tags: { slo: SLO.setup, name: 'create_session' },
    });

    check(sessionResponse, {
        'load test session created': (r) => r.status === 201,
    }, { slo: SLO.setup });

    if (sessionResponse.status === 201) {
        // Extract session cookie from Set-Cookie header (Rails automatically encrypts it)
        const sessionCookie = sessionResponse.cookies['_iv_cbv_payroll_session'];
        if (sessionCookie && sessionCookie[0]) {
            headers['Cookie'] = `_iv_cbv_payroll_session=${sessionCookie[0].value}`;

            // Extract account_id and csrf_token from response body
            const sessionData = JSON.parse(sessionResponse.body);

            return {
                headers: headers,
                accountId: sessionData.account_id,
                argyleUserId: sessionData.argyle_user_id,
                csrfToken: sessionData.csrf_token
            };
        } else {
            console.error('No session cookie in response');
            return null;
        }
    } else {
        console.error('Failed to create session:', sessionResponse.status, sessionResponse.body);
        return null;
    }
}

function executeTestScenario(scenario, session) {
    switch(scenario) {
        case 'sync':
            testSynchronization(session);
            break;
        case 'payment_details':
            testPaymentDetails(session);
            break;
        case 'summary':
            testSummary(session);
            break;
        case 'pdf':
            testPdfGeneration(session);
            break;
        case 'employer_search':
            testEmployerSearch(session);
            break;
        case 'user_event':
            testUserEvent(session);
            break;
    }
}

const WEIGHTED_SCENARIOS = Object.entries(SCENARIO_WEIGHTS);
const TOTAL_WEIGHT = WEIGHTED_SCENARIOS.reduce((total, [, weight]) => total + weight, 0);

// Pick a scenario with probability proportional to SCENARIO_WEIGHTS.
function selectScenario() {
    let rand = Math.random() * TOTAL_WEIGHT;
    for (const [scenario, weight] of WEIGHTED_SCENARIOS) {
        if (rand < weight) return scenario;
        rand -= weight;
    }
    return WEIGHTED_SCENARIOS[WEIGHTED_SCENARIOS.length - 1][0];
}

function testSynchronization(session) {
    const { headers, accountId, csrfToken } = session;

    group("Synchronization polling (DB intensive)", () => {
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
            { headers: requestHeaders, tags: { slo: SLO.standard, name: 'synchronizations' } }
        );

        check(response, {
            'synchronization check succeeded': (r) => r.status === 200,
        });

        checkSlo(response);
    });

    // Realistic polling interval
    sleep(SIMULATE_DELAY_SYNC_POLLING_S);
}

function testPaymentDetails(session) {
    const { headers, accountId } = session;

    group("Payment details (DB + aggregation)", () => {
        const response = http.get(
            `${URL}/cbv/payment_details?user%5Baccount_id%5D=${accountId}`,
            { headers, tags: { slo: SLO.standard, name: 'payment_details' } }
        );

        check(response, {
            'payment details loaded': (r) => r.status === 200,
        });

        checkSlo(response);
    });

    // Time reviewing payment details
    sleep(SIMULATE_DELAY_PAYMENT_DETAILS_S);
}

function testSummary(session) {
    const { headers } = session;

    group("Summary page (aggregation)", () => {
        const response = http.get(
            `${URL}/cbv/summary`,
            { headers, tags: { slo: SLO.standard, name: 'summary' } }
        );

        check(response, {
            'summary loaded': (r) => r.status === 200,
        });

        checkSlo(response);
    });

    // Time reviewing summary
    sleep(SIMULATE_DELAY_SUMMARY_S);
}

function testPdfGeneration(session) {
    const { headers } = session;

    group("PDF generation (CPU intensive)", () => {
        const response = http.get(
            `${URL}/cbv/submit.pdf`,
            {
                headers: {
                    ...headers,
                    'Accept': 'application/pdf',
                },
                tags: { slo: SLO.pdf, name: 'submit_pdf' },
            }
        );

        check(response, {
            'pdf generated': (r) => r.status === 200,
            'pdf content type': (r) => r.headers['Content-Type'] && r.headers['Content-Type'].includes('pdf'),
        });

        checkSlo(response, SLO.pdf);
    });

    // PDFs are downloaded less frequently
    sleep(SIMULATE_DELAY_PDF_DOWNLOAD_S);
}

function testEmployerSearch(session) {
    const { headers } = session;

    group("Employer search page", () => {
        const response = http.get(
            `${URL}/cbv/employer_search`,
            { headers, tags: { slo: SLO.standard, name: 'employer_search' } }
        );

        check(response, {
            'employer search loaded': (r) => r.status === 200,
        });

        checkSlo(response);
    });

    // Time searching for employer
    sleep(SIMULATE_DELAY_EMPLOYER_SEARCH_S);
}

function testUserEvent(session) {
    const { headers, csrfToken } = session;

    group("Front-end analytics event", () => {
        const requestHeaders = {
            ...headers,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        };
        if (csrfToken) {
            requestHeaders['X-CSRF-Token'] = csrfToken;
        }

        // Same shape as trackUserAction() in app/javascript/utilities/api.js.
        // The app does not forward load-test events to analytics, so this
        // measures the request itself, not the analytics jobs.
        const response = http.post(
            `${URL}/api/events/user_action`,
            JSON.stringify({ events: { event_name: 'ApplicantViewedHelpText', attributes: { source: 'load-test' } } }),
            { headers: requestHeaders, tags: { slo: SLO.standard, name: 'user_event' } }
        );

        check(response, {
            'user event accepted': (r) => r.status === 200,
        });

        checkSlo(response);
    });

    sleep(SIMULATE_DELAY_USER_EVENT_S);
}

const WEBHOOK_SEQUENCE = [
    (user, account) => ({ event: 'accounts.updated', data: { user, account, resource: { connection: { status: 'connected' } } } }),
    (user, account) => ({ event: 'accounts.updated', data: { user, account, resource: { connection: { status: 'connected' } } } }),
    (user, account) => ({ event: 'identities.added', data: { user, account } }),
    (user, account) => ({ event: 'paystubs.partially_synced', data: { user, account, days_synced: 90 } }),
    (user, account) => ({ event: 'paystubs.fully_synced', data: { user, account } }),
    (user, account) => ({ event: 'users.fully_synced', data: { user, resource: { accounts_connected: [account] } } }),
];

function testWebhook() {
    if (!webhookFlow || webhookFlow.step >= WEBHOOK_SEQUENCE.length) {
        const session = createSession('pending');
        if (!session || !session.argyleUserId) {
            if (session) console.error('Session has no argyle_user_id; is the app on the current load-test session endpoint?');
            sleep(SIMULATE_DELAY_WEBHOOK_S);
            return;
        }
        webhookFlow = { argyleUserId: session.argyleUserId, accountId: session.accountId, step: 0 };
    }

    const payload = WEBHOOK_SEQUENCE[webhookFlow.step](webhookFlow.argyleUserId, webhookFlow.accountId);
    webhookFlow.step += 1;

    group("Argyle webhook", () => {
        const body = JSON.stringify(payload);
        const response = http.post(`${URL}/webhooks/argyle/events`, body, {
            headers: {
                'Content-Type': 'application/json',
                'X-Argyle-Signature': crypto.hmac('sha512', WEBHOOK_SECRET, body, 'hex'),
            },
            tags: { slo: SLO.standard, name: 'argyle_webhook', event: payload.event },
        });

        check(response, {
            'webhook processed': (r) => r.status === 200 && r.body.includes('"status":"ok"'),
        });

        checkSlo(response);
    });

    sleep(SIMULATE_DELAY_WEBHOOK_S);
}

// vim: expandtab sw=4 ts=4
