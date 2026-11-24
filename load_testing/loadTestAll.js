import runUserFlow from './loadTestUserFlow.js';
import runAPITest, { API_RATE } from './loadTestAPI.js';
import { commonOptions, userFlowStages, userFlowDuration } from './common.js';

export let options = {
    ...commonOptions,
    scenarios: {
        // User flow tests - session-based; shape set by PROFILE (see common.js)
        user_flows: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: userFlowStages(),
            exec: 'userFlow',
        },
        // API tests - token-based bulk creation
        api_invitations: {
            executor: 'constant-arrival-rate',
            rate: API_RATE,         // invitations per second (API_RATE env, default 2)
            timeUnit: '1s',
            duration: userFlowDuration(),
            preAllocatedVUs: 5,
            maxVUs: 50,
            exec: 'apiInvitations',
        },
    },
};

// User flow test function - delegates to loadTestUserFlow
export function userFlow() {
    runUserFlow();
}

// API test function - delegates to loadTestAPI
export function apiInvitations() {
    runAPITest();
}

// vim: expandtab sw=4 ts=4
