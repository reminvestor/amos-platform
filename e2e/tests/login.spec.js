const { test, expect } = require('@playwright/test');
const { loginViaForm, loginViaQuickSelect } = require('../helpers/auth');

test.describe('Login Flow', () => {
  test('shows login page with expected elements', async ({ page }) => {
    await page.goto('/users/sign_in');

    await expect(page.locator('#user_email_field')).toBeVisible();
    await expect(page.locator('#user_password')).toBeVisible();
    await expect(page.locator('#login-form input[type="submit"]')).toBeVisible();
  });

  test('shows quick-login dropdown in dev mode', async ({ page }) => {
    await page.goto('/users/sign_in');

    const quickLogin = page.locator('#quick-login-selector');
    await expect(quickLogin).toBeVisible();

    // Should have user options beyond the placeholder
    const options = quickLogin.locator('option[value]');
    expect(await options.count()).toBeGreaterThan(0);
  });

  test('can login via form fill', async ({ page }) => {
    await loginViaForm(page, 'admin@demo.com');
    await expect(page).toHaveURL(/\/chat/);
  });

  test('can login via quick-login selector', async ({ page }) => {
    await loginViaQuickSelect(page, 'admin@demo.com');
    await expect(page).toHaveURL(/\/chat/);
  });

  test('rejects invalid credentials', async ({ page }) => {
    await page.goto('/users/sign_in');

    await page.fill('#user_email_field', 'nonexistent@test.com');
    await page.fill('#user_password', 'WrongPassword1!');
    await page.click('#login-form input[type="submit"]');

    // Should show error and stay on login page
    await expect(page.locator('.alert')).toBeVisible({ timeout: 5_000 });
  });
});
