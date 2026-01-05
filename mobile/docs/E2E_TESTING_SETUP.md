# E2E Testing Setup - AMOS Mobile App

Complete guide to setting up and running E2E tests with Detox.

## Prerequisites

### System Requirements

- **macOS**: Xcode 12+, Node.js 14+
- **Linux**: Node.js 14+
- **Windows**: WSL2 recommended

### Install Detox CLI

```bash
# Install globally
npm install -g detox-cli

# Verify installation
detox --version
```

## Setup E2E Testing

### 1. Install Dependencies

```bash
cd mobile
npm install
```

This installs:
- `detox` - E2E testing framework
- `detox-cli` - Command-line tools

### 2. Build Framework Cache (iOS)

```bash
detox build-framework-cache
```

This is a one-time setup that caches the Detox framework.

### 3. Build App for Testing

**iOS:**
```bash
npm run e2e:build:ios
```

**Android:**
```bash
npm run e2e:build:android
```

## Running E2E Tests

### Run All Tests

**iOS:**
```bash
npm run e2e:ios
```

**Android:**
```bash
npm run e2e:android
```

### Run Specific Test File

```bash
detox test --configuration ios.sim.debug --testNamePattern="Login Flow"
```

### Debug Mode

```bash
npm run e2e:ios:debug
```

This enables synchronization logging to help identify timing issues.

### With Custom Grep Pattern

```bash
detox test --configuration ios.sim.debug --grep "should login"
```

## Test File Structure

Create E2E test files in `e2e/` folder:

```javascript
// e2e/loginFlow.e2e.js
describe('Login Flow', () => {
  beforeAll(async () => {
    await device.launchApp();
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it('should show login screen', async () => {
    await expect(element(by.text('AMOS'))).toBeVisible();
  });
});
```

## Key Detox APIs

### Device Control

```javascript
// Launch app
await device.launchApp();

// Reload React Native
await device.reloadReactNative();

// Take screenshot
await device.takeScreenshot('login-screen');

// Simulate orientation
await device.setOrientation('landscape');
```

### Element Matchers

```javascript
// By ID
by.id('email-input')

// By text (regex supported)
by.text(/sign in/i)

// By label
by.label('Login Button')

// By type
by.type('RCTScrollView')

// Multiple matchers
by.id('container').and(by.text('Hello'))
```

### Element Actions

```javascript
// Type text
await element(by.id('email-input')).typeText('test@example.com');

// Clear text
await element(by.id('email-input')).clearText();

// Tap
await element(by.text('Sign In')).multiTap();

// Long press
await element(by.id('button')).longPress();

// Scroll
await element(by.id('list')).scroll(200, 'down');

// Swipe
await element(by.id('list')).swipe('up');
```

### Element Assertions

```javascript
// Visible
await expect(element(by.text('Welcome'))).toBeVisible();

// Not visible
await expect(element(by.text('Error'))).not.toBeVisible();

// Exists
await expect(element(by.id('button'))).toExist();

// Has text
await expect(element(by.id('label'))).toHaveText('Hello');

// Is focused
await expect(element(by.id('input'))).toBeFocused();
```

### Waits and Synchronization

```javascript
// Wait for element
await waitFor(element(by.text('Loaded'))).toBeVisible().withTimeout(5000);

// Wait and perform action
await waitFor(element(by.id('submit'))).toExist().withTimeout(3000);
await element(by.id('submit')).multiTap();

// Timeout: 5 seconds
await waitFor(element(by.text('Done'))).toBeVisible().withTimeout(5000);
```

## Example Test Scenarios

### Login Test

```javascript
describe('Authentication', () => {
  beforeAll(async () => {
    await device.launchApp();
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it('should successfully login with valid credentials', async () => {
    // Enter email
    await element(by.id('email-input')).typeText('test@example.com');

    // Enter password
    await element(by.id('password-input')).typeText('ValidPass123!');

    // Tap sign in button
    await element(by.text('Sign In')).multiTap();

    // Wait for navigation to campaigns
    await waitFor(element(by.text('Campaigns'))).toBeVisible().withTimeout(5000);

    // Verify campaign list is visible
    await expect(element(by.text('Campaigns'))).toBeVisible();
  });

  it('should show error for invalid email', async () => {
    // Enter invalid email
    await element(by.id('email-input')).typeText('invalid-email');

    // Enter password
    await element(by.id('password-input')).typeText('password');

    // Tap sign in
    await element(by.text('Sign In')).multiTap();

    // Verify error message
    await expect(element(by.text(/invalid email/i))).toBeVisible();
  });
});
```

### Campaign Management Test

```javascript
describe('Campaign Management', () => {
  beforeAll(async () => {
    await device.launchApp();
    // Login first
    await loginHelper.loginWithTestAccount();

    // Navigate to campaigns
    await element(by.text('Campaigns')).multiTap();
  });

  it('should display list of campaigns', async () => {
    await waitFor(element(by.text(/campaign/i))).toBeVisible().withTimeout(5000);

    // Verify at least one campaign is visible
    await expect(element(by.type('RCTText')).atIndex(0)).toBeVisible();
  });

  it('should open campaign details', async () => {
    // Tap first campaign
    await element(by.type('RCTTouchableOpacity')).atIndex(0).multiTap();

    // Wait for detail screen
    await waitFor(element(by.text('Campaign Details'))).toBeVisible().withTimeout(5000);

    // Verify details are shown
    await expect(element(by.text(/status/i))).toBeVisible();
  });

  it('should pause a campaign', async () => {
    // Assuming we're on campaign detail screen

    // Tap pause button
    await element(by.text('Pause')).multiTap();

    // Verify status changed
    await expect(element(by.text('Paused'))).toBeVisible();
  });
});
```

### Contact Management Test

```javascript
describe('Contact Management', () => {
  beforeAll(async () => {
    await device.launchApp();
    await loginHelper.loginWithTestAccount();

    // Navigate to contacts
    await element(by.text('Contacts')).multiTap();
  });

  it('should add a new contact', async () => {
    // Tap add contact button
    await element(by.id('add-contact-btn')).multiTap();

    // Enter email
    await element(by.id('contact-email')).typeText('newcontact@example.com');

    // Enter name
    await element(by.id('contact-name')).typeText('New Contact');

    // Submit form
    await element(by.text('Add Contact')).multiTap();

    // Verify success message
    await expect(element(by.text(/success/i))).toBeVisible();
  });

  it('should search contacts', async () => {
    // Tap search field
    await element(by.id('search-input')).multiTap();

    // Type search term
    await element(by.id('search-input')).typeText('john');

    // Verify filtered results
    await waitFor(element(by.text('john'))).toBeVisible().withTimeout(3000);
  });
});
```

## Test Helpers

Create helper functions in `e2e/helpers/`:

### Authentication Helper

```javascript
// e2e/helpers/auth.helper.js
export const loginHelper = {
  async loginWithTestAccount() {
    const testEmail = 'test@example.com';
    const testPassword = 'TestPass123!';

    // Enter credentials
    await element(by.id('email-input')).typeText(testEmail);
    await element(by.id('password-input')).typeText(testPassword);

    // Sign in
    await element(by.text('Sign In')).multiTap();

    // Wait for navigation
    await waitFor(element(by.text('Campaigns'))).toBeVisible().withTimeout(5000);
  },

  async logout() {
    // Navigate to settings
    await element(by.text('Settings')).multiTap();

    // Tap logout
    await element(by.text('Logout')).multiTap();

    // Verify back at login
    await expect(element(by.text('AMOS'))).toBeVisible();
  }
};
```

## Best Practices

### 1. Use Meaningful Test IDs

```typescript
// In components
<TextInput
  testID="email-input"  // Descriptive ID
  placeholder="Email"
/>
```

Then in tests:
```javascript
await element(by.id('email-input')).typeText('test@example.com');
```

### 2. Handle Async Operations

```javascript
// ✅ Good - wait for elements to appear
await waitFor(element(by.text('Loaded'))).toBeVisible().withTimeout(5000);

// ❌ Bad - arbitrary wait
await sleep(2000);
```

### 3. Use Descriptive Test Names

```javascript
// ✅ Good
it('should successfully login with valid email and password', async () => {});

// ❌ Bad
it('logs in', async () => {});
```

### 4. Test Real User Flows

```javascript
// ✅ Good - tests complete user journey
it('should create and publish a campaign', async () => {
  // Login
  await loginHelper.loginWithTestAccount();

  // Create campaign
  await createCampaign('Test Campaign');

  // Verify campaign appears in list
  await expect(element(by.text('Test Campaign'))).toBeVisible();

  // Publish campaign
  await publishCampaign();

  // Verify status changed
  await expect(element(by.text('Published'))).toBeVisible();
});
```

### 5. Clean Up After Tests

```javascript
afterEach(async () => {
  // Navigate back to initial state
  await device.sendUserActivity({type: 'OpenURL', url: 'app://home'});

  // Or reload app
  await device.reloadReactNative();
});
```

## Troubleshooting

### Issue: Elements not found

```bash
# Take screenshot to debug
detox test --configuration ios.sim.debug --cleanup

# View what's on screen
await device.takeScreenshot('debug-screen');
```

### Issue: Timeout waiting for element

```javascript
// Increase timeout
await waitFor(element(by.text('Loaded')))
  .toBeVisible()
  .withTimeout(10000); // 10 seconds instead of 5
```

### Issue: Tests fail intermittently (Flaky)

```javascript
// Use explicit waits instead of sleep
// ❌ Flaky
await sleep(1000);
await element(by.text('Done')).multiTap();

// ✅ Stable
await waitFor(element(by.text('Done'))).toBeVisible().withTimeout(5000);
await element(by.text('Done')).multiTap();
```

### Issue: App not launching

```bash
# Clear app data and rebuild
detox test --configuration ios.sim.debug --cleanup

# Build from scratch
npm run e2e:build:ios
```

## CI/CD Integration

### GitHub Actions

```yaml
name: E2E Tests

on: [push, pull_request]

jobs:
  e2e:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2

      - uses: actions/setup-node@v2
        with:
          node-version: '18'

      - run: npm install

      - run: npm run e2e:build:ios

      - run: npm run e2e:ios

      - if: failure()
        uses: actions/upload-artifact@v2
        with:
          name: detox-artifacts
          path: artifacts/
```

## Resources

- [Detox Documentation](https://wix.github.io/Detox/)
- [Detox CLI](https://wix.github.io/Detox/docs/cli/cli/)
- [Detox Best Practices](https://wix.github.io/Detox/docs/guide/test-practices/)
- [Synchronization](https://wix.github.io/Detox/docs/guide/synchronization/)
