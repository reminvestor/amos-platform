import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics per endpoint
const errorRate = new Rate('errors');
const endpointErrors = new Counter('endpoint_errors');

// Latency trends per API group
const authLatency = new Trend('auth_latency');
const agentsLatency = new Trend('agents_latency');
const campaignsLatency = new Trend('campaigns_latency');
const contactsLatency = new Trend('contacts_latency');
const landingPagesLatency = new Trend('landing_pages_latency');
const tasksLatency = new Trend('tasks_latency');
const chatLatency = new Trend('chat_latency');
const voiceLatency = new Trend('voice_latency');

export const options = {
  scenarios: {
    // Smoke test scenario
    smoke: {
      executor: 'constant-vus',
      vus: 5,
      duration: '1m',
      tags: { scenario: 'smoke' },
    },
    // Load test scenario
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 25 },
        { duration: '2m', target: 50 },
        { duration: '2m', target: 50 },
        { duration: '1m', target: 0 },
      ],
      startTime: '1m30s',
      tags: { scenario: 'load' },
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    errors: ['rate<0.1'],
    auth_latency: ['p(95)<300'],
    agents_latency: ['p(95)<500'],
    campaigns_latency: ['p(95)<500'],
    contacts_latency: ['p(95)<500'],
    landing_pages_latency: ['p(95)<500'],
    tasks_latency: ['p(95)<500'],
    chat_latency: ['p(95)<2000'],
    voice_latency: ['p(95)<500'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const TEST_EMAIL = __ENV.TEST_EMAIL || 'test@example.com';
const TEST_PASSWORD = __ENV.TEST_PASSWORD || 'password123';
const TEST_API_KEY = __ENV.TEST_API_KEY || null;

export function setup() {
  let token;

  // If API key is provided directly, skip login
  if (TEST_API_KEY) {
    console.log('Using direct API key authentication');
    token = TEST_API_KEY;
  } else {
    // Login
    const loginRes = http.post(`${BASE_URL}/api/auth/login`, JSON.stringify({
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
    }), {
      headers: { 'Content-Type': 'application/json' },
    });

    if (loginRes.status !== 200) {
      console.error('Setup login failed:', loginRes.status, '- Use TEST_API_KEY env var');
      return { token: null };
    }

    const body = JSON.parse(loginRes.body);
    token = body.api_key || body.token;
  }

  // Get initial data for testing
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`,
  };

  // Fetch existing IDs for update/delete tests
  const campaignsRes = http.get(`${BASE_URL}/api/v1/campaigns`, { headers });
  const contactsRes = http.get(`${BASE_URL}/api/v1/contacts`, { headers });
  const landingPagesRes = http.get(`${BASE_URL}/api/v1/landing_pages`, { headers });
  const tasksRes = http.get(`${BASE_URL}/api/v1/tasks`, { headers });
  const agentsRes = http.get(`${BASE_URL}/api/v1/agents`, { headers });

  const getData = (res, key) => {
    try {
      const data = JSON.parse(res.body);
      const items = data[key] || data.data || [];
      return items.length > 0 ? items[0].id : null;
    } catch { return null; }
  };

  return {
    token,
    campaignId: getData(campaignsRes, 'campaigns'),
    contactId: getData(contactsRes, 'contacts'),
    landingPageId: getData(landingPagesRes, 'landing_pages'),
    taskId: getData(tasksRes, 'tasks'),
    agentId: getData(agentsRes, 'agents'),
  };
}

function makeRequest(method, url, headers, body = null, latencyTrend = null) {
  const start = Date.now();
  let res;

  if (method === 'GET') {
    res = http.get(url, { headers });
  } else if (method === 'POST') {
    res = http.post(url, body ? JSON.stringify(body) : null, { headers });
  } else if (method === 'PUT' || method === 'PATCH') {
    res = http.patch(url, body ? JSON.stringify(body) : null, { headers });
  } else if (method === 'DELETE') {
    res = http.del(url, null, { headers });
  }

  if (latencyTrend) {
    latencyTrend.add(Date.now() - start);
  }

  return res;
}

export default function(data) {
  if (!data.token) {
    console.error('No auth token available');
    return;
  }

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${data.token}`,
  };

  // ========== AUTHENTICATION API ==========
  group('Auth API', () => {
    // GET /api/auth/me
    let res = makeRequest('GET', `${BASE_URL}/api/auth/me`, headers, null, authLatency);
    let success = check(res, { 'GET /api/auth/me': (r) => r.status === 200 });
    if (!success) endpointErrors.add(1, { endpoint: 'auth_me' });
    errorRate.add(!success);
  });

  sleep(0.2);

  // ========== AGENTS API (Mobile) ==========
  group('Agents API', () => {
    // GET /api/v1/agents
    let res = makeRequest('GET', `${BASE_URL}/api/v1/agents`, headers, null, agentsLatency);
    let success = check(res, { 'GET /api/v1/agents': (r) => r.status === 200 });
    if (!success) endpointErrors.add(1, { endpoint: 'agents_list' });
    errorRate.add(!success);

    // GET /api/v1/agents/:id
    if (data.agentId) {
      res = makeRequest('GET', `${BASE_URL}/api/v1/agents/${data.agentId}`, headers, null, agentsLatency);
      success = check(res, { 'GET /api/v1/agents/:id': (r) => r.status === 200 });
      if (!success) endpointErrors.add(1, { endpoint: 'agents_show' });
      errorRate.add(!success);
    }

    // GET /api/v1/agents/agent_types
    res = makeRequest('GET', `${BASE_URL}/api/v1/agents/agent_types`, headers, null, agentsLatency);
    success = check(res, { 'GET /api/v1/agents/agent_types': (r) => r.status === 200 || r.status === 404 });
    errorRate.add(!success);
  });

  sleep(0.2);

  // ========== CAMPAIGNS API ==========
  group('Campaigns API', () => {
    // GET /api/v1/campaigns
    let res = makeRequest('GET', `${BASE_URL}/api/v1/campaigns`, headers, null, campaignsLatency);
    let success = check(res, { 'GET /api/v1/campaigns': (r) => r.status === 200 });
    if (!success) endpointErrors.add(1, { endpoint: 'campaigns_list' });
    errorRate.add(!success);

    // GET /api/v1/campaigns/:id
    if (data.campaignId) {
      res = makeRequest('GET', `${BASE_URL}/api/v1/campaigns/${data.campaignId}`, headers, null, campaignsLatency);
      success = check(res, { 'GET /api/v1/campaigns/:id': (r) => r.status === 200 });
      if (!success) endpointErrors.add(1, { endpoint: 'campaigns_show' });
      errorRate.add(!success);
    }
  });

  sleep(0.2);

  // ========== CONTACTS API ==========
  group('Contacts API', () => {
    // GET /api/v1/contacts
    let res = makeRequest('GET', `${BASE_URL}/api/v1/contacts`, headers, null, contactsLatency);
    let success = check(res, { 'GET /api/v1/contacts': (r) => r.status === 200 });
    if (!success) endpointErrors.add(1, { endpoint: 'contacts_list' });
    errorRate.add(!success);

    // GET /api/v1/contacts/:id
    if (data.contactId) {
      res = makeRequest('GET', `${BASE_URL}/api/v1/contacts/${data.contactId}`, headers, null, contactsLatency);
      success = check(res, { 'GET /api/v1/contacts/:id': (r) => r.status === 200 });
      if (!success) endpointErrors.add(1, { endpoint: 'contacts_show' });
      errorRate.add(!success);
    }
  });

  sleep(0.2);

  // ========== LANDING PAGES API ==========
  group('Landing Pages API', () => {
    // GET /api/v1/landing_pages
    let res = makeRequest('GET', `${BASE_URL}/api/v1/landing_pages`, headers, null, landingPagesLatency);
    let success = check(res, { 'GET /api/v1/landing_pages': (r) => r.status === 200 });
    if (!success) endpointErrors.add(1, { endpoint: 'landing_pages_list' });
    errorRate.add(!success);

    // GET /api/v1/landing_pages/:id
    if (data.landingPageId) {
      res = makeRequest('GET', `${BASE_URL}/api/v1/landing_pages/${data.landingPageId}`, headers, null, landingPagesLatency);
      success = check(res, { 'GET /api/v1/landing_pages/:id': (r) => r.status === 200 });
      if (!success) endpointErrors.add(1, { endpoint: 'landing_pages_show' });
      errorRate.add(!success);
    }
  });

  sleep(0.2);

  // ========== TASKS API ==========
  group('Tasks API', () => {
    // GET /api/v1/tasks
    let res = makeRequest('GET', `${BASE_URL}/api/v1/tasks`, headers, null, tasksLatency);
    let success = check(res, { 'GET /api/v1/tasks': (r) => r.status === 200 });
    if (!success) endpointErrors.add(1, { endpoint: 'tasks_list' });
    errorRate.add(!success);

    // GET /api/v1/tasks/:id
    if (data.taskId) {
      res = makeRequest('GET', `${BASE_URL}/api/v1/tasks/${data.taskId}`, headers, null, tasksLatency);
      success = check(res, { 'GET /api/v1/tasks/:id': (r) => r.status === 200 });
      if (!success) endpointErrors.add(1, { endpoint: 'tasks_show' });
      errorRate.add(!success);
    }
  });

  sleep(0.2);

  // ========== CHAT API ==========
  group('Chat API', () => {
    // GET /api/v1/chat/history
    let res = makeRequest('GET', `${BASE_URL}/api/v1/chat/history`, headers, null, chatLatency);
    let success = check(res, { 'GET /api/v1/chat/history': (r) => r.status === 200 || r.status === 404 });
    errorRate.add(!success);

    // GET /api/v1/chat/conversations
    res = makeRequest('GET', `${BASE_URL}/api/v1/chat/conversations`, headers, null, chatLatency);
    success = check(res, { 'GET /api/v1/chat/conversations': (r) => r.status === 200 || r.status === 404 });
    errorRate.add(!success);
  });

  sleep(0.2);

  // ========== VOICE API ==========
  group('Voice API', () => {
    // POST /api/voice/sessions (create session)
    let res = makeRequest('POST', `${BASE_URL}/api/voice/sessions`, headers, {}, voiceLatency);
    let success = check(res, { 'POST /api/voice/sessions': (r) => r.status === 200 || r.status === 201 || r.status === 404 });
    errorRate.add(!success);

    // GET /api/voice/health/status
    res = makeRequest('GET', `${BASE_URL}/api/voice/health/status`, headers, null, voiceLatency);
    success = check(res, { 'GET /api/voice/health/status': (r) => r.status === 200 || r.status === 404 });
    errorRate.add(!success);
  });

  sleep(0.2);

  // ========== SCOUT/WEB CHAT ==========
  group('Scout Chat API', () => {
    // POST /scout/chat (non-streaming for perf test)
    let res = makeRequest('POST', `${BASE_URL}/scout/chat`, headers, {
      message: 'Performance test message',
      new_session: true,
    }, chatLatency);
    let success = check(res, { 'POST /scout/chat': (r) => r.status >= 200 && r.status < 500 });
    errorRate.add(!success);
  });

  sleep(0.5);

  // ========== HEALTH CHECK ==========
  group('Health API', () => {
    // GET /api/v1/health
    let res = makeRequest('GET', `${BASE_URL}/api/v1/health`, headers);
    let success = check(res, { 'GET /api/v1/health': (r) => r.status === 200 });
    errorRate.add(!success);

    // GET /health (public)
    res = http.get(`${BASE_URL}/health`);
    success = check(res, { 'GET /health': (r) => r.status === 200 });
    errorRate.add(!success);
  });

  sleep(0.3);
}

export function handleSummary(data) {
  // Generate comprehensive summary
  const summary = {
    timestamp: new Date().toISOString(),
    duration: data.state.testRunDurationMs,
    metrics: {
      total_requests: data.metrics.http_reqs?.values?.count || 0,
      failed_requests: data.metrics.http_req_failed?.values?.passes || 0,
      error_rate: data.metrics.errors?.values?.rate || 0,
      avg_response_time: data.metrics.http_req_duration?.values?.avg || 0,
      p95_response_time: data.metrics.http_req_duration?.values['p(95)'] || 0,
    },
    endpoints: {
      auth: { p95: data.metrics.auth_latency?.values['p(95)'] || 0 },
      agents: { p95: data.metrics.agents_latency?.values['p(95)'] || 0 },
      campaigns: { p95: data.metrics.campaigns_latency?.values['p(95)'] || 0 },
      contacts: { p95: data.metrics.contacts_latency?.values['p(95)'] || 0 },
      landing_pages: { p95: data.metrics.landing_pages_latency?.values['p(95)'] || 0 },
      tasks: { p95: data.metrics.tasks_latency?.values['p(95)'] || 0 },
      chat: { p95: data.metrics.chat_latency?.values['p(95)'] || 0 },
      voice: { p95: data.metrics.voice_latency?.values['p(95)'] || 0 },
    },
  };

  return {
    'test/performance/results/full_coverage_summary.json': JSON.stringify(summary, null, 2),
    stdout: generateTextReport(data),
  };
}

function generateTextReport(data) {
  let report = '\n';
  report += '╔══════════════════════════════════════════════════════════════╗\n';
  report += '║            AMOS API FULL COVERAGE TEST RESULTS              ║\n';
  report += '╠══════════════════════════════════════════════════════════════╣\n';
  report += `║  Total Requests:     ${String(data.metrics.http_reqs?.values?.count || 0).padStart(8)}                          ║\n`;
  report += `║  Failed Requests:    ${String(data.metrics.http_req_failed?.values?.passes || 0).padStart(8)}                          ║\n`;
  report += `║  Error Rate:         ${((data.metrics.errors?.values?.rate || 0) * 100).toFixed(2).padStart(7)}%                         ║\n`;
  report += '╠══════════════════════════════════════════════════════════════╣\n';
  report += '║  RESPONSE TIMES (ms)                                         ║\n';
  report += `║    Average:          ${(data.metrics.http_req_duration?.values?.avg || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += `║    P90:              ${(data.metrics.http_req_duration?.values['p(90)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += `║    P95:              ${(data.metrics.http_req_duration?.values['p(95)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += '╠══════════════════════════════════════════════════════════════╣\n';
  report += '║  ENDPOINT LATENCIES (P95 ms)                                 ║\n';
  report += `║    Auth:             ${(data.metrics.auth_latency?.values['p(95)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += `║    Agents:           ${(data.metrics.agents_latency?.values['p(95)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += `║    Campaigns:        ${(data.metrics.campaigns_latency?.values['p(95)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += `║    Contacts:         ${(data.metrics.contacts_latency?.values['p(95)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += `║    Landing Pages:    ${(data.metrics.landing_pages_latency?.values['p(95)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += `║    Tasks:            ${(data.metrics.tasks_latency?.values['p(95)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += `║    Chat:             ${(data.metrics.chat_latency?.values['p(95)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += `║    Voice:            ${(data.metrics.voice_latency?.values['p(95)'] || 0).toFixed(2).padStart(8)}                          ║\n`;
  report += '╚══════════════════════════════════════════════════════════════╝\n';

  return report;
}
