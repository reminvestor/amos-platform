import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const authLatency = new Trend('auth_latency');
const agentsLatency = new Trend('agents_latency');
const chatLatency = new Trend('chat_latency');
const contactsLatency = new Trend('contacts_latency');

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 25 },  // Ramp up to 25 users
    { duration: '1m', target: 25 },   // Stay at 25 users
    { duration: '30s', target: 50 },  // Ramp up to 50 users
    { duration: '2m', target: 50 },   // Stay at 50 users
    { duration: '30s', target: 75 },  // Ramp up to 75 users
    { duration: '1m', target: 75 },   // Stay at 75 users
    { duration: '30s', target: 0 },   // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% of requests under 500ms
    errors: ['rate<0.1'],              // Error rate under 10%
    auth_latency: ['p(95)<300'],
    agents_latency: ['p(95)<400'],
    chat_latency: ['p(95)<1000'],      // Chat can be slower (streaming)
    contacts_latency: ['p(95)<300'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const TEST_EMAIL = __ENV.TEST_EMAIL || 'test@example.com';
const TEST_PASSWORD = __ENV.TEST_PASSWORD || 'password123';
const TEST_API_KEY = __ENV.TEST_API_KEY || null;

export function setup() {
  // If API key is provided directly, skip login
  if (TEST_API_KEY) {
    console.log('Using direct API key authentication');
    return { token: TEST_API_KEY };
  }

  // Login to get auth token
  const loginRes = http.post(`${BASE_URL}/api/auth/login`, JSON.stringify({
    email: TEST_EMAIL,
    password: TEST_PASSWORD,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  if (loginRes.status === 200) {
    const body = JSON.parse(loginRes.body);
    return { token: body.api_key || body.token };
  }

  console.error('Login failed:', loginRes.status, '- Use TEST_API_KEY env var');
  return { token: null };
}

export default function(data) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${data.token}`,
  };

  group('Authentication', () => {
    const start = Date.now();
    const res = http.get(`${BASE_URL}/api/auth/me`, { headers });
    authLatency.add(Date.now() - start);

    const success = check(res, {
      'auth status is 200': (r) => r.status === 200,
      'auth has user': (r) => JSON.parse(r.body).user !== undefined,
    });
    errorRate.add(!success);
  });

  sleep(0.5);

  group('Agents API', () => {
    const start = Date.now();
    const res = http.get(`${BASE_URL}/api/v1/agents`, { headers });
    agentsLatency.add(Date.now() - start);

    const success = check(res, {
      'agents status is 200': (r) => r.status === 200,
      'agents returns array': (r) => {
        const body = JSON.parse(r.body);
        return Array.isArray(body.agents);
      },
    });
    errorRate.add(!success);
  });

  sleep(0.5);

  group('Contacts API', () => {
    const start = Date.now();
    const res = http.get(`${BASE_URL}/api/v1/contacts`, { headers });
    contactsLatency.add(Date.now() - start);

    const success = check(res, {
      'contacts status is 200': (r) => r.status === 200,
    });
    errorRate.add(!success);
  });

  sleep(0.5);

  group('Chat Session', () => {
    // Create a new chat session
    const start = Date.now();
    const res = http.post(`${BASE_URL}/scout/chat`, JSON.stringify({
      message: 'Hello, this is a performance test',
    }), { headers });
    chatLatency.add(Date.now() - start);

    const success = check(res, {
      'chat responds': (r) => r.status === 200 || r.status === 201,
    });
    errorRate.add(!success);
  });

  sleep(1);
}

export function teardown(data) {
  console.log('Performance test completed');
}
