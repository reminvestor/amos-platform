import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

// Stress test - find breaking point
export const options = {
  stages: [
    { duration: '2m', target: 50 },   // Ramp to 50 users
    { duration: '3m', target: 50 },   // Stay at 50
    { duration: '2m', target: 100 },  // Ramp to 100 users
    { duration: '3m', target: 100 },  // Stay at 100
    { duration: '2m', target: 150 },  // Ramp to 150 users
    { duration: '3m', target: 150 },  // Stay at 150
    { duration: '2m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'], // Allow higher latency under stress
    errors: ['rate<0.3'],              // Allow up to 30% errors to find breaking point
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const TEST_EMAIL = __ENV.TEST_EMAIL || 'test@example.com';
const TEST_PASSWORD = __ENV.TEST_PASSWORD || 'password123';
const TEST_API_KEY = __ENV.TEST_API_KEY || null;

export function setup() {
  if (TEST_API_KEY) {
    console.log('Using direct API key authentication');
    return { token: TEST_API_KEY };
  }

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
  console.error('Login failed - Use TEST_API_KEY env var');
  return { token: null };
}

export default function(data) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${data.token}`,
  };

  // Randomly select an endpoint to simulate varied traffic
  const endpoints = [
    { weight: 3, fn: () => http.get(`${BASE_URL}/api/auth/me`, { headers }) },
    { weight: 2, fn: () => http.get(`${BASE_URL}/api/v1/agents`, { headers }) },
    { weight: 2, fn: () => http.get(`${BASE_URL}/api/v1/contacts`, { headers }) },
    { weight: 2, fn: () => http.get(`${BASE_URL}/api/v1/campaigns`, { headers }) },
    { weight: 1, fn: () => http.get(`${BASE_URL}/api/v1/landing_pages`, { headers }) },
  ];

  // Weighted random selection
  const totalWeight = endpoints.reduce((sum, e) => sum + e.weight, 0);
  let random = Math.random() * totalWeight;
  let selectedEndpoint;

  for (const endpoint of endpoints) {
    random -= endpoint.weight;
    if (random <= 0) {
      selectedEndpoint = endpoint;
      break;
    }
  }

  const res = selectedEndpoint.fn();

  const success = check(res, {
    'status is 2xx or 3xx': (r) => r.status >= 200 && r.status < 400,
    'response time < 2s': (r) => r.timings.duration < 2000,
  });

  errorRate.add(!success);
  sleep(Math.random() * 0.5 + 0.1); // Random sleep 100-600ms
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'test/performance/results/stress_test_summary.json': JSON.stringify(data),
  };
}

function textSummary(data, opts) {
  const indent = opts.indent || '';
  let output = '\n=== STRESS TEST SUMMARY ===\n\n';

  output += `${indent}Total Requests: ${data.metrics.http_reqs.values.count}\n`;
  output += `${indent}Failed Requests: ${data.metrics.http_req_failed.values.passes}\n`;
  output += `${indent}Error Rate: ${(data.metrics.errors.values.rate * 100).toFixed(2)}%\n\n`;

  output += `${indent}Response Times:\n`;
  output += `${indent}  Average: ${data.metrics.http_req_duration.values.avg.toFixed(2)}ms\n`;
  output += `${indent}  Min: ${data.metrics.http_req_duration.values.min.toFixed(2)}ms\n`;
  output += `${indent}  Max: ${data.metrics.http_req_duration.values.max.toFixed(2)}ms\n`;
  output += `${indent}  P90: ${data.metrics.http_req_duration.values['p(90)'].toFixed(2)}ms\n`;
  output += `${indent}  P95: ${data.metrics.http_req_duration.values['p(95)'].toFixed(2)}ms\n`;

  return output;
}
