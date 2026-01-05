import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// CRUD operations test - tests create, update, delete
// WARNING: This creates/modifies/deletes real data!

const errorRate = new Rate('errors');
const createLatency = new Trend('create_latency');
const updateLatency = new Trend('update_latency');
const deleteLatency = new Trend('delete_latency');

export const options = {
  vus: 1,
  iterations: 1,  // Run once (CRUD is destructive)
  thresholds: {
    errors: ['rate<0.2'],
    create_latency: ['p(95)<1000'],
    update_latency: ['p(95)<1000'],
    delete_latency: ['p(95)<1000'],
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

  const loginRes = http.post(`${BASE_URL}/api/auth/login`, JSON.stringify({
    email: TEST_EMAIL,
    password: TEST_PASSWORD,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  if (loginRes.status !== 200) {
    console.error('Login failed:', loginRes.status, '- Use TEST_API_KEY env var');
    return { token: null };
  }

  const body = JSON.parse(loginRes.body);
  return { token: body.api_key || body.token };
}

export default function(data) {
  if (!data.token) {
    console.error('No auth token');
    return;
  }

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${data.token}`,
  };

  const timestamp = Date.now();

  // ========== CONTACTS CRUD ==========
  group('Contacts CRUD', () => {
    // CREATE
    let start = Date.now();
    let createRes = http.post(`${BASE_URL}/api/v1/contacts`, JSON.stringify({
      contact: {
        email: `perf-test-${timestamp}@example.com`,
        first_name: 'Performance',
        last_name: 'Test',
      }
    }), { headers });
    createLatency.add(Date.now() - start);

    let success = check(createRes, {
      'Contact CREATE': (r) => r.status === 200 || r.status === 201,
    });
    errorRate.add(!success);

    if (!success) {
      console.error('Contact create failed:', createRes.status, createRes.body);
      return;
    }

    const contact = JSON.parse(createRes.body);
    const contactId = contact.id || contact.contact?.id;

    if (!contactId) {
      console.error('No contact ID returned');
      return;
    }

    sleep(0.5);

    // UPDATE
    start = Date.now();
    let updateRes = http.patch(`${BASE_URL}/api/v1/contacts/${contactId}`, JSON.stringify({
      contact: {
        first_name: 'Updated',
        last_name: 'PerfTest',
      }
    }), { headers });
    updateLatency.add(Date.now() - start);

    success = check(updateRes, {
      'Contact UPDATE': (r) => r.status === 200,
    });
    errorRate.add(!success);

    sleep(0.5);

    // DELETE
    start = Date.now();
    let deleteRes = http.del(`${BASE_URL}/api/v1/contacts/${contactId}`, null, { headers });
    deleteLatency.add(Date.now() - start);

    success = check(deleteRes, {
      'Contact DELETE': (r) => r.status === 200 || r.status === 204,
    });
    errorRate.add(!success);
  });

  sleep(1);

  // ========== TASKS CRUD ==========
  group('Tasks CRUD', () => {
    // CREATE
    let start = Date.now();
    let createRes = http.post(`${BASE_URL}/api/v1/tasks`, JSON.stringify({
      task: {
        title: `Performance Test Task ${timestamp}`,
        description: 'Created by k6 performance test',
        status: 'pending',
        priority: 'medium',
      }
    }), { headers });
    createLatency.add(Date.now() - start);

    let success = check(createRes, {
      'Task CREATE': (r) => r.status === 200 || r.status === 201,
    });
    errorRate.add(!success);

    if (!success) {
      console.error('Task create failed:', createRes.status, createRes.body);
      return;
    }

    const task = JSON.parse(createRes.body);
    const taskId = task.id || task.task?.id;

    if (!taskId) {
      console.error('No task ID returned');
      return;
    }

    sleep(0.5);

    // UPDATE
    start = Date.now();
    let updateRes = http.patch(`${BASE_URL}/api/v1/tasks/${taskId}`, JSON.stringify({
      task: {
        title: `Updated Task ${timestamp}`,
        status: 'in_progress',
      }
    }), { headers });
    updateLatency.add(Date.now() - start);

    success = check(updateRes, {
      'Task UPDATE': (r) => r.status === 200,
    });
    errorRate.add(!success);

    sleep(0.5);

    // DELETE
    start = Date.now();
    let deleteRes = http.del(`${BASE_URL}/api/v1/tasks/${taskId}`, null, { headers });
    deleteLatency.add(Date.now() - start);

    success = check(deleteRes, {
      'Task DELETE': (r) => r.status === 200 || r.status === 204,
    });
    errorRate.add(!success);
  });

  sleep(1);

  // ========== CAMPAIGNS CRUD ==========
  group('Campaigns CRUD', () => {
    // CREATE
    let start = Date.now();
    let createRes = http.post(`${BASE_URL}/api/v1/campaigns`, JSON.stringify({
      campaign: {
        name: `Perf Test Campaign ${timestamp}`,
        subject: 'Performance Test',
        body: '<p>Performance test email body</p>',
        campaign_type: 'one_time',
      }
    }), { headers });
    createLatency.add(Date.now() - start);

    let success = check(createRes, {
      'Campaign CREATE': (r) => r.status === 200 || r.status === 201,
    });
    errorRate.add(!success);

    if (!success) {
      console.error('Campaign create failed:', createRes.status, createRes.body);
      return;
    }

    const campaign = JSON.parse(createRes.body);
    const campaignId = campaign.id || campaign.campaign?.id;

    if (!campaignId) {
      console.error('No campaign ID returned');
      return;
    }

    sleep(0.5);

    // UPDATE
    start = Date.now();
    let updateRes = http.patch(`${BASE_URL}/api/v1/campaigns/${campaignId}`, JSON.stringify({
      campaign: {
        name: `Updated Perf Campaign ${timestamp}`,
        subject: 'Updated Subject',
      }
    }), { headers });
    updateLatency.add(Date.now() - start);

    success = check(updateRes, {
      'Campaign UPDATE': (r) => r.status === 200,
    });
    errorRate.add(!success);

    sleep(0.5);

    // DELETE
    start = Date.now();
    let deleteRes = http.del(`${BASE_URL}/api/v1/campaigns/${campaignId}`, null, { headers });
    deleteLatency.add(Date.now() - start);

    success = check(deleteRes, {
      'Campaign DELETE': (r) => r.status === 200 || r.status === 204,
    });
    errorRate.add(!success);
  });
}

export function handleSummary(data) {
  let report = '\n=== CRUD OPERATIONS TEST SUMMARY ===\n\n';
  report += `Create P95: ${(data.metrics.create_latency?.values['p(95)'] || 0).toFixed(2)}ms\n`;
  report += `Update P95: ${(data.metrics.update_latency?.values['p(95)'] || 0).toFixed(2)}ms\n`;
  report += `Delete P95: ${(data.metrics.delete_latency?.values['p(95)'] || 0).toFixed(2)}ms\n`;
  report += `Error Rate: ${((data.metrics.errors?.values?.rate || 0) * 100).toFixed(2)}%\n`;

  return {
    stdout: report,
    'test/performance/results/crud_test_summary.json': JSON.stringify(data, null, 2),
  };
}
