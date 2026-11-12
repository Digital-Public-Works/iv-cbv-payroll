import http from 'k6/http';
import { check, group } from 'k6';
import { URL, SLO, checkSlo, commonOptions } from './common.js';

// Invitations per second, and how long to sustain it.
export const API_RATE = Number(__ENV.API_RATE || 100);
const API_DURATION = __ENV.API_DURATION || '2m';

export let options = {
    ...commonOptions,
    scenarios: {
        bulk_create: {
            executor: 'constant-arrival-rate',
            rate: API_RATE,
            timeUnit: '1s',
            duration: API_DURATION,
            preAllocatedVUs: 50,
            maxVUs: 100,            // Allow scaling if needed
        },
    },
};

const API_KEY = __ENV.API_KEY;

if(!API_KEY) {
    throw new Error("API_KEY environment variable is required");
}

// The attributes an invitation needs depend on the API user's partner config
// (required invitation attributes, partner identifier name). Override with
// --env CUSTOM_ATTRIBUTES='{"case_number":"x","date_of_birth":"1990-01-01"}'.
// Values equal to "__UNIQUE__" are replaced with a unique LOAD_TEST_ id per request.
const CUSTOM_ATTRIBUTES = JSON.parse(__ENV.CUSTOM_ATTRIBUTES || '{"case_number":"__UNIQUE__"}');

function buildCustomAttributes() {
    const unique = `LOAD_TEST_${Date.now()}_${Math.random().toString(36).substring(7)}`;
    return Object.fromEntries(
        Object.entries(CUSTOM_ATTRIBUTES).map(([key, value]) => [key, value === '__UNIQUE__' ? unique : value])
    );
}

export default function () {
    testCreateInvitation();
}

function testCreateInvitation() {
    group("Create invitation (API)", () => {
        const payload = JSON.stringify({
            language: 'en',
            custom_attributes: buildCustomAttributes(),
        });

        const response = http.post(
            `${URL}/api/v1/invitations`,
            payload,
            {
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${API_KEY}`,
                },
                tags: { slo: SLO.standard, name: 'api_create_invitation' },
            }
        );

        check(response, {
            'invitation created': (r) => r.status === 201,
            'has tokenized_url': (r) => {
                try {
                    return JSON.parse(r.body).tokenized_url !== undefined;
                } catch (_e) {
                    return false; // HTML error page, timeout, etc.
                }
            },
        });

        checkSlo(response);
    });

    // No sleep needed - constant-arrival-rate executor controls the rate
}

// vim: expandtab sw=4 ts=4
