const { test, expect } = require('@playwright/test');
const { loginViaQuickSelect } = require('../helpers/auth');

test.describe('Feedback System', () => {
  test.beforeEach(async ({ page }) => {
    await loginViaQuickSelect(page, 'admin@demo.com');
  });

  test('chat page loads after login', async ({ page }) => {
    await expect(page).toHaveURL(/\/chat/);
  });

  test('feedback buttons are present on assistant messages', async ({ page }) => {
    const feedbackContainers = page.locator('[data-controller="feedback"]');
    const count = await feedbackContainers.count();

    test.skip(count === 0, 'No assistant messages with feedback buttons in current session');

    const first = feedbackContainers.first();
    await expect(first.locator('[data-feedback-rating-param="1"]')).toBeVisible();
    await expect(first.locator('[data-feedback-rating-param="-1"]')).toBeVisible();
  });

  test('thumbs up submits positive feedback immediately', async ({ page }) => {
    const feedbackContainers = page.locator('[data-controller="feedback"]');
    const count = await feedbackContainers.count();
    test.skip(count === 0, 'No assistant messages with feedback buttons');

    const first = feedbackContainers.first();

    // Intercept the POST to /scout/feedback
    const responsePromise = page.waitForResponse(
      resp => resp.url().includes('/scout/feedback') && resp.request().method() === 'POST'
    );

    await first.locator('[data-feedback-rating-param="1"]').click();

    const response = await responsePromise;
    expect(response.status()).toBe(200);

    // Success message should appear
    await expect(first.locator('.feedback-success')).toBeVisible();
    await expect(first.locator('.feedback-message')).toContainText('positive feedback');

    // Buttons should be hidden
    await expect(first.locator('.btn-group')).toBeHidden();
  });

  test('thumbs down shows comment form before submitting', async ({ page }) => {
    const feedbackContainers = page.locator('[data-controller="feedback"]');
    const count = await feedbackContainers.count();
    test.skip(count === 0, 'No assistant messages with feedback buttons');

    const first = feedbackContainers.first();

    await first.locator('[data-feedback-rating-param="-1"]').click();

    // Comment form should appear
    await expect(first.locator('.feedback-comment-form')).toBeVisible();
    await expect(first.locator('.feedback-comment-input')).toBeVisible();

    // Original buttons should be hidden
    await expect(first.locator('.btn-group')).toBeHidden();

    // Submit and Skip buttons visible
    await expect(first.locator('button:has-text("Submit")')).toBeVisible();
    await expect(first.locator('button:has-text("Skip")')).toBeVisible();
  });

  test('negative feedback with comment submits correctly', async ({ page }) => {
    const feedbackContainers = page.locator('[data-controller="feedback"]');
    const count = await feedbackContainers.count();
    test.skip(count === 0, 'No assistant messages with feedback buttons');

    const first = feedbackContainers.first();

    // Click thumbs down
    await first.locator('[data-feedback-rating-param="-1"]').click();
    await expect(first.locator('.feedback-comment-form')).toBeVisible();

    // Type a comment
    await first.locator('.feedback-comment-input').fill('The response was not accurate');

    // Intercept the POST
    const responsePromise = page.waitForResponse(
      resp => resp.url().includes('/scout/feedback') && resp.request().method() === 'POST'
    );

    await first.locator('button:has-text("Submit")').click();

    const response = await responsePromise;
    expect(response.status()).toBe(200);

    // Success state
    await expect(first.locator('.feedback-success')).toBeVisible();
    await expect(first.locator('.feedback-comment-form')).toBeHidden();
  });

  test('negative feedback skip submits without comment', async ({ page }) => {
    const feedbackContainers = page.locator('[data-controller="feedback"]');
    const count = await feedbackContainers.count();
    test.skip(count === 0, 'No assistant messages with feedback buttons');

    const first = feedbackContainers.first();

    await first.locator('[data-feedback-rating-param="-1"]').click();
    await expect(first.locator('.feedback-comment-form')).toBeVisible();

    const responsePromise = page.waitForResponse(
      resp => resp.url().includes('/scout/feedback') && resp.request().method() === 'POST'
    );

    await first.locator('button:has-text("Skip")').click();

    const response = await responsePromise;
    expect(response.status()).toBe(200);

    await expect(first.locator('.feedback-success')).toBeVisible();
  });
});
