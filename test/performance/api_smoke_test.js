import http from 'k6/http';
import { check, sleep } from 'k6';

// Smoke test - quick verification that APIs work
export const options = {
  vus: 5,  // 5 concurrent users for smoke test
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(99)<1000'],
    http_req_failed: ['rate<0.05'],  // Allow 5% for smoke
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

  // Otherwise, try to login
  const loginRes = http.post(`${BASE_URL}/api/auth/login`, JSON.stringify({
    email: TEST_EMAIL,
    password: TEST_PASSWORD,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  if (loginRes.status === 200) {
    const body = JSON.parse(loginRes.body);
    console.log('Login successful');
    return { token: body.api_key || body.token };
  }

  console.error('Login failed:', loginRes.status, '- Use TEST_API_KEY env var for direct auth');
  return { token: null };
}

export default function(data) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${data.token}`,
  };

  // Test each endpoint once
  const endpoints = [
    { name: 'Auth Me', method: 'GET', url: '/api/auth/me' },
    { name: 'Agents List', method: 'GET', url: '/api/v1/agents' },
    { name: 'Contacts List', method: 'GET', url: '/api/v1/contacts' },
    { name: 'Campaigns List', method: 'GET', url: '/api/v1/campaigns' },
    { name: 'Landing Pages', method: 'GET', url: '/api/v1/landing_pages' },
    { name: 'Tasks List', method: 'GET', url: '/api/v1/tasks' },
  ];

  for (const endpoint of endpoints) {
    let res;
    if (endpoint.method === 'GET') {
      res = http.get(`${BASE_URL}${endpoint.url}`, { headers });
    } else {
      res = http.post(`${BASE_URL}${endpoint.url}`, JSON.stringify(endpoint.body || {}), { headers });
    }

    check(res, {
      [`${endpoint.name} is OK`]: (r) => r.status >= 200 && r.status < 300,
    });

    sleep(0.5);
  }
}
