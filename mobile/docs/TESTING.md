# Testing Guide - AMOS Mobile App

Comprehensive guide for unit testing, integration testing, and E2E testing the AMOS mobile app.

## Overview

The project includes:
- **Unit Tests**: Jest + React Native Testing Library for components, services, and utilities
- **E2E Tests**: Detox for end-to-end mobile testing
- **Integration Tests**: Redux store and API integration
- **Code Coverage**: 50%+ threshold for all metrics

## Running Tests

### Unit Tests

```bash
# Run all unit tests
npm test

# Run in watch mode
npm run test:watch

# Run specific test file
npm test validators.test.ts

# Run with coverage
npm test -- --coverage
```

### Type Checking

```bash
# Run TypeScript compiler
npm run type-check
```

### Linting

```bash
# Lint code
npm run lint

# Fix linting issues
npm run lint -- --fix
```

### E2E Tests

```bash
# Build and run E2E tests (iOS simulator)
npm run e2e:ios

# Run E2E tests (Android emulator)
npm run e2e:android

# E2E tests in debug mode
npm run e2e:ios:debug
```

## Test Structure

```
__tests__/
├── utils/
│   ├── validators.test.ts        # Validation rule tests
│   ├── formatters.test.ts        # Formatting function tests
│   ├── storage.test.ts           # Storage utility tests
│   └── logger.test.ts            # Logger tests
├── services/
│   ├── auth.service.test.ts      # Auth API tests
│   ├── campaigns.service.test.ts # Campaign API tests
│   └── contacts.service.test.ts  # Contact API tests
├── store/
│   └── slices/
│       ├── authSlice.test.ts     # Auth reducer tests
│       ├── campaignsSlice.test.ts
│       ├── contactsSlice.test.ts
│       └── uiSlice.test.ts
└── screens/
    ├── LoginScreen.test.tsx      # Screen component tests
    └── ChatScreen.test.tsx

e2e/
├── firstTest.e2e.js             # Login flow E2E tests
├── campaignFlow.e2e.js          # Campaign management E2E tests
├── contactFlow.e2e.js           # Contact management E2E tests
└── helpers/
    ├── auth.helpers.js           # E2E auth helpers
    └── api.mocks.js              # API mocking utilities
```

## Writing Unit Tests

### Test Utilities

Example: Testing validators

```typescript
import { isValidEmail } from '@utils/validators';

describe('isValidEmail', () => {
  it('should accept valid emails', () => {
    expect(isValidEmail('test@example.com')).toBe(true);
  });

  it('should reject invalid emails', () => {
    expect(isValidEmail('invalid')).toBe(false);
  });
});
```

### Testing Services

Example: Testing auth service

```typescript
import * as authService from '@services/auth';
import { apiClient } from '@services/api';

jest.mock('@services/api');

describe('Auth Service', () => {
  it('should login user', async () => {
    (apiClient.post as jest.Mock).mockResolvedValue({
      user: mockUser,
      token: 'token-123',
    });

    const result = await authService.login({
      email: 'test@example.com',
      password: 'password',
    });

    expect(apiClient.post).toHaveBeenCalledWith('/api/auth/login', expect.any(Object));
    expect(result.token).toBe('token-123');
  });
});
```

### Testing Redux

Example: Testing auth slice

```typescript
import authReducer, { loginUser } from '@store/slices/authSlice';

describe('authSlice', () => {
  it('should set user on login fulfilled', () => {
    const action = {
      type: loginUser.fulfilled.type,
      payload: {
        user: mockUser,
        api_key: 'token-123',
      },
    };

    const result = authReducer(initialState, action);

    expect(result.isAuthenticated).toBe(true);
    expect(result.user).toEqual(mockUser);
  });
});
```

### Testing Components

Example: Testing login screen

```typescript
import { render, screen, fireEvent } from '@testing-library/react-native';
import LoginScreen from '@screens/auth/LoginScreen';
import { Provider } from 'react-redux';
import { store } from '@store';

describe('LoginScreen', () => {
  it('should render login form', () => {
    render(
      <Provider store={store}>
        <LoginScreen />
      </Provider>
    );

    expect(screen.getByPlaceholderText(/email/i)).toBeDefined();
    expect(screen.getByPlaceholderText(/password/i)).toBeDefined();
  });

  it('should call login on submit', async () => {
    const { getByText, getByPlaceholderText } = render(
      <Provider store={store}>
        <LoginScreen />
      </Provider>
    );

    fireEvent.changeText(getByPlaceholderText(/email/i), 'test@example.com');
    fireEvent.changeText(getByPlaceholderText(/password/i), 'password');
    fireEvent.press(getByText('Sign In'));

    // Assert login was attempted
  });
});
```

## Writing E2E Tests

### Detox Setup

Install Detox CLI globally:

```bash
npm install -g detox-cli
```

Build the app for testing:

```bash
# iOS
detox build-framework-cache
detox build-app-and-cache --configuration ios.sim.debug

# Android
detox build-app-and-cache --configuration android.emu.debug
```

### Example E2E Test

```javascript
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

  it('should validate email format', async () => {
    await element(by.id('email-input')).typeText('invalid-email');
    await element(by.text('Sign In')).multiTap();

    await expect(element(by.text(/invalid email/i))).toBeVisible();
  });

  it('should successfully login', async () => {
    await element(by.id('email-input')).typeText('test@example.com');
    await element(by.id('password-input')).typeText('ValidPass123!');
    await element(by.text('Sign In')).multiTap();

    // Wait for navigation to campaigns
    await waitFor(element(by.text('Campaigns'))).toBeVisible().withTimeout(5000);
  });
});
```

### Running E2E Tests

```bash
# Run all E2E tests
detox test --configuration ios.sim.debug

# Run specific test
detox test --configuration ios.sim.debug --testNamePattern="Login Flow"

# Debug mode
detox test --configuration ios.sim.debug --debug-synchronization=200
```

## Mocking Strategies

### Mocking API Calls

```typescript
import { apiClient } from '@services/api';

jest.mock('@services/api');

// In test
(apiClient.get as jest.Mock).mockResolvedValue({
  data: [...],
  pagination: {...}
});
```

### Mocking Redux

```typescript
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import authReducer from '@store/slices/authSlice';

const preloadedState = {
  auth: {
    user: mockUser,
    token: 'token-123',
    isAuthenticated: true,
    isLoading: false,
    error: null,
  },
};

const mockStore = configureStore({
  reducer: {
    auth: authReducer,
  },
  preloadedState,
});

// In test
render(
  <Provider store={mockStore}>
    <YourComponent />
  </Provider>
);
```

### Mocking Storage

```typescript
import * as storage from '@utils/storage';

jest.mock('@utils/storage');

// In test
(storage.getSession as jest.Mock).mockResolvedValue({
  token: 'token-123',
  user: mockUser,
  expiresAt: Date.now() + 86400000,
});
```

## Test Coverage

View coverage report:

```bash
npm test -- --coverage
```

Coverage thresholds (from jest.config.js):
- Branches: 50%
- Functions: 50%
- Lines: 50%
- Statements: 50%

To increase coverage:

```bash
npm test -- --coverage --coverageReporters=lcov
# Open coverage/lcov-report/index.html in browser
```

## Best Practices

### 1. Test Naming

Use descriptive test names:

```typescript
// ✅ Good
it('should validate email format and show error for invalid email', () => {});

// ❌ Bad
it('should validate email', () => {});
```

### 2. Arrange-Act-Assert Pattern

```typescript
it('should login user', async () => {
  // Arrange
  const mockUser = { id: '1', email: 'test@example.com' };
  (apiClient.post as jest.Mock).mockResolvedValue(mockUser);

  // Act
  const result = await authService.login({
    email: 'test@example.com',
    password: 'password',
  });

  // Assert
  expect(result).toEqual(mockUser);
});
```

### 3. Test Independence

Each test should be independent:

```typescript
// ✅ Good - uses beforeEach to set up state
beforeEach(() => {
  state = initialState;
});

it('test 1', () => {
  // state is fresh
});

// ❌ Bad - tests depend on execution order
it('test 1', () => {
  state.value = 'modified';
});

it('test 2', () => {
  // Depends on test 1 running first
  expect(state.value).toBe('modified');
});
```

### 4. Avoid Testing Implementation Details

```typescript
// ❌ Bad - testing internal state
expect(component.instance().state.isLoading).toBe(true);

// ✅ Good - testing user-visible behavior
expect(screen.getByText('Loading...')).toBeVisible();
```

### 5. Use Semantic Queries

```typescript
// ✅ Good - semantic queries
screen.getByRole('button', { name: /sign in/i });
screen.getByLabelText(/email/i);

// ❌ Bad - implementation details
screen.getByTestId('submit-btn');
container.querySelector('.form');
```

## Continuous Integration

Add to `.github/workflows/test.yml`:

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-node@v2
        with:
          node-version: '18'
      - run: npm install
      - run: npm run type-check
      - run: npm run lint
      - run: npm test -- --coverage
      - uses: codecov/codecov-action@v2
```

## Debugging Tests

### Debug a Single Test

```bash
node --inspect-brk node_modules/.bin/jest validators.test.ts
```

Then open `chrome://inspect` in Chrome.

### Debug E2E Tests

```bash
detox test --configuration ios.sim.debug --debug-synchronization=200 --verbose
```

### Print Debug Info

```typescript
// In tests
import { screen, debug } from '@testing-library/react-native';

debug(); // Prints entire DOM tree
screen.debug(element); // Prints specific element
```

## Common Issues & Solutions

### Issue: Tests pass locally but fail in CI

**Solution**: Mock all external dependencies (API, storage, timers)

```typescript
jest.useFakeTimers();
```

### Issue: Flaky E2E tests

**Solution**: Add proper wait conditions

```javascript
// ✅ Good
await waitFor(element(by.text('Success'))).toBeVisible().withTimeout(5000);

// ❌ Bad
await sleep(1000); // Arbitrary wait
```

### Issue: Can't find test element

**Solution**: Add testID to component

```typescript
<TextInput testID="email-input" placeholder="Email" />
```

Then in test:

```javascript
await element(by.id('email-input')).typeText('test@example.com');
```

## Resources

- [Jest Documentation](https://jestjs.io/)
- [React Native Testing Library](https://callstack.github.io/react-native-testing-library/)
- [Detox E2E Testing](https://wix.github.io/Detox/docs/introduction/getting-started/)
- [Testing Best Practices](https://kentcdodds.com/blog/common-mistakes-with-react-testing-library)

## Next Steps

1. **Increase coverage**: Add tests for all services and screens
2. **Add visual regression**: Use snapshot testing for UI components
3. **Performance testing**: Benchmark component render times
4. **Accessibility testing**: Test screen reader compatibility
5. **Security testing**: Test auth flows and data encryption
