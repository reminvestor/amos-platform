describe('Authentication Flow', () => {
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

  it('should clear error on input change', async () => {
    await element(by.id('email-input')).typeText('invalid');
    await element(by.id('password-input')).typeText('password');
    await element(by.text('Sign In')).multiTap();

    await waitFor(element(by.text(/email/i))).toBeVisible().withTimeout(3000);

    await element(by.id('email-input')).clearText();
    await element(by.id('email-input')).typeText('valid@example.com');

    await expect(element(by.text(/email/i))).not.toBeVisible();
  });
});

describe('Campaign List Flow', () => {
  beforeAll(async () => {
    await device.launchApp();
    // Assumes user is already logged in or logged in via previous tests
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it('should navigate to campaigns tab', async () => {
    await element(by.text('Campaigns')).multiTap();

    await expect(element(by.text(/campaigns/i))).toBeVisible();
  });

  it('should display campaign list', async () => {
    await element(by.text('Campaigns')).multiTap();

    // Wait for campaign list to load
    await waitFor(element(by.type('RCTScrollView'))).toBeVisible().withTimeout(5000);
  });

  it('should search campaigns', async () => {
    await element(by.text('Campaigns')).multiTap();

    // Find and type in search field
    await element(by.id('campaign-search')).typeText('Test Campaign');

    // Wait for filtered results
    await waitFor(element(by.text('Search campaigns...'))).toBeVisible().withTimeout(3000);
  });

  it('should open filter modal', async () => {
    await element(by.text('Campaigns')).multiTap();

    // Find and tap filter button
    await element(by.id('filter-button')).multiTap();

    // Filter modal should be visible
    await expect(element(by.text(/filter campaigns/i))).toBeVisible();
  });

  it('should filter campaigns by status', async () => {
    await element(by.text('Campaigns')).multiTap();
    await element(by.id('filter-button')).multiTap();

    // Tap a status filter option
    await element(by.text('In Progress')).multiTap();

    // Apply filter
    await element(by.text('Apply Filter')).multiTap();

    // Modal should close
    await expect(element(by.text(/filter campaigns/i))).not.toBeVisible();
  });
});

describe('Campaign Detail Flow', () => {
  beforeAll(async () => {
    await device.launchApp();
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it('should navigate to campaign detail from list', async () => {
    // Go to campaigns
    await element(by.text('Campaigns')).multiTap();

    // Wait for list to load
    await waitFor(element(by.type('RCTScrollView'))).toBeVisible().withTimeout(5000);

    // Tap first campaign card
    await element(by.type('RCTTouchableOpacity')).atIndex(0).multiTap();

    // Detail screen should show campaign name
    await waitFor(element(by.type('RCTText')).withAncestor(by.id('campaign-name'))).toBeVisible().withTimeout(3000);
  });

  it('should display campaign analytics', async () => {
    // Assumes we're on campaign detail screen
    await expect(element(by.text(/performance metrics/i))).toBeVisible();
    await expect(element(by.text(/open rate/i))).toBeVisible();
    await expect(element(by.text(/click rate/i))).toBeVisible();
  });

  it('should display campaign information section', async () => {
    await expect(element(by.text(/campaign information/i))).toBeVisible();
    await expect(element(by.text(/created/i))).toBeVisible();
    await expect(element(by.text(/recipients/i))).toBeVisible();
  });

  it('should display quick action buttons', async () => {
    await expect(element(by.text(/edit campaign/i))).toBeVisible();
    await expect(element(by.text(/duplicate campaign/i))).toBeVisible();
    await expect(element(by.text(/send test email/i))).toBeVisible();
    await expect(element(by.text(/archive campaign/i))).toBeVisible();
  });

  it('should open action menu', async () => {
    // Tap menu button (three dots)
    await element(by.id('menu-button')).multiTap();

    // Menu should be visible
    await expect(element(by.text(/edit campaign/i))).toBeVisible();
    await expect(element(by.text(/duplicate campaign/i))).toBeVisible();
  });

  it('should pull to refresh campaign details', async () => {
    // Scroll to top
    await element(by.type('RCTScrollView')).swipe('down', 'slow', 0.75);

    // Wait for refresh to complete
    await waitFor(element(by.type('RCTActivityIndicator'))).not.toBeVisible().withTimeout(5000);
  });

  it('should navigate back to campaign list', async () => {
    // Tap back button
    await element(by.id('back-button')).multiTap();

    // Should return to campaign list
    await expect(element(by.text(/search campaigns/i))).toBeVisible();
  });
});
