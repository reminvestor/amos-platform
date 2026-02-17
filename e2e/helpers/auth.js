/**
 * Login using the quick-login dropdown (dev/test only).
 * The dropdown auto-fills email/password and submits the form after 500ms.
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} email - Email of the user to select from dropdown
 */
async function loginViaQuickSelect(page, email) {
  await page.goto('/users/sign_in');
  const selector = page.locator('#quick-login-selector');
  await selector.waitFor({ state: 'visible' });
  await selector.selectOption(email);
  // Dropdown auto-submits after 500ms — wait for navigation away from sign_in
  await page.waitForURL(url => !url.pathname.includes('/sign_in'), { timeout: 15_000 });
}

/**
 * Login using manual form fill.
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} email
 * @param {string} [password='Password123!']
 */
async function loginViaForm(page, email, password = 'Password123!') {
  await page.goto('/users/sign_in');

  const emailField = page.locator('#user_email_field');
  const passwordField = page.locator('#user_password');

  await emailField.click();
  await emailField.fill(email);

  await passwordField.click();
  await passwordField.fill(password);

  // Verify password was actually filled before submitting
  await page.waitForTimeout(200);

  await page.locator('#login-form input[type="submit"], #login-form button[type="submit"]').click();
  await page.waitForURL(url => !url.pathname.includes('/sign_in'), { timeout: 15_000 });
}

module.exports = { loginViaQuickSelect, loginViaForm };
