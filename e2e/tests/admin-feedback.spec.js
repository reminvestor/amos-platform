const { test, expect } = require('@playwright/test');
const { loginViaQuickSelect } = require('../helpers/auth');

test.describe('Admin Feedback Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    // Login as admin user
    await loginViaQuickSelect(page, 'admin@demo.com');
  });

  test('can access admin portal', async ({ page }) => {
    await page.goto('/admin');
    await expect(page.locator('body')).toBeVisible();
    // Should see admin dashboard content
    await expect(page.locator('text=Dashboard').first()).toBeVisible({ timeout: 5_000 });
  });

  test('admin feedback dashboard loads', async ({ page }) => {
    await page.goto('/admin/feedbacks');

    await expect(page.locator('h1')).toContainText('User Feedback');

    // Stats cards
    await expect(page.locator('text=Total Feedback')).toBeVisible();
    await expect(page.locator('text=Satisfaction Score')).toBeVisible();
    await expect(page.locator('text=Positive').first()).toBeVisible();
  });

  test('admin feedback dashboard has date filter', async ({ page }) => {
    await page.goto('/admin/feedbacks');

    await expect(page.locator('input[name="start_date"]')).toBeVisible();
    await expect(page.locator('input[name="end_date"]')).toBeVisible();
    await expect(page.locator('button:has-text("Filter")')).toBeVisible();
    await expect(page.locator('text=Reset')).toBeVisible();
  });

  test('admin feedback date filter works', async ({ page }) => {
    await page.goto('/admin/feedbacks');

    await page.fill('input[name="start_date"]', '2026-01-01');
    await page.fill('input[name="end_date"]', '2026-02-17');
    await page.click('button:has-text("Filter")');

    // URL should include date params
    await expect(page).toHaveURL(/start_date=2026-01-01/);
    await expect(page).toHaveURL(/end_date=2026-02-17/);

    // Page should still show correctly
    await expect(page.locator('h1')).toContainText('User Feedback');
  });

  test('admin feedback dashboard shows trend chart', async ({ page }) => {
    await page.goto('/admin/feedbacks');

    await expect(page.locator('#feedbackTrendChart')).toBeVisible();
    await expect(page.locator('text=Daily Feedback Trend')).toBeVisible();
  });

  test('admin feedback dashboard shows data tables', async ({ page }) => {
    await page.goto('/admin/feedbacks');

    await expect(page.locator('text=Feedback by Type')).toBeVisible();
    await expect(page.locator('text=Recent Negative Feedback')).toBeVisible();
    await expect(page.locator('text=Recent Feedback')).toBeVisible();
  });
});
