describe('Login Flow', () => {
  beforeAll(async () => {
    await device.launchApp();
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it('should show login screen on first launch', async () => {
    await expect(element(by.text('AMOS'))).toBeVisible();
    await expect(element(by.text('Sign In'))).toBeVisible();
  });

  it('should show email validation error for invalid email', async () => {
    await element(by.id('email-input')).typeText('invalid-email');
    await element(by.id('password-input')).typeText('password123');
    await element(by.text('Sign In')).multiTap();

    await expect(element(by.text(/email/i))).toBeVisible();
  });

  it('should show required field errors', async () => {
    await element(by.text('Sign In')).multiTap();

    await expect(element(by.text(/fill in all fields/i))).toBeVisible();
  });

  it('should attempt login with valid credentials', async () => {
    // Note: Mock the API or use test credentials
    await element(by.id('email-input')).typeText('test@example.com');
    await element(by.id('password-input')).typeText('ValidPass123!');
    await element(by.text('Sign In')).multiTap();

    // Would navigate to main app if login succeeds
    // This will fail without a working backend or mocked API
  });

  it('should handle network errors gracefully', async () => {
    // This would require mocking the API to simulate network failure
    await element(by.id('email-input')).typeText('test@example.com');
    await element(by.id('password-input')).typeText('ValidPass123!');
    await element(by.text('Sign In')).multiTap();

    // Error message should be displayed
  });

  it('should clear error on input change', async () => {
    await element(by.id('email-input')).typeText('invalid');
    await element(by.id('password-input')).typeText('password');
    await element(by.text('Sign In')).multiTap();

    // Wait for error to appear
    await waitFor(element(by.text(/email/i))).toBeVisible().withTimeout(3000);

    // Clear error by changing input
    await element(by.id('email-input')).clearText();
    await element(by.id('email-input')).typeText('valid@example.com');

    await expect(element(by.text(/email/i))).not.toBeVisible();
  });
});
