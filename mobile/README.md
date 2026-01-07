# Amos Labs Mobile App

React Native mobile application for Amos Labs - the AI Marketing Orchestration System. Supports both iOS and Android devices.

## Overview

This is a native iOS/Android app built with React Native and Expo that provides access to core Amos Labs features on mobile devices including:

- Amos AI Assistant (chat)
- Campaign management and monitoring
- Contact management and bulk import
- Landing page creation and tracking
- Push notifications for real-time updates
- User settings and preferences

## Tech Stack

- **Framework**: React Native + Expo
- **Language**: TypeScript
- **State Management**: Redux Toolkit
- **HTTP Client**: Axios
- **Navigation**: React Navigation
- **Storage**: AsyncStorage
- **UI Components**: React Native Paper
- **Voice Input**: @react-native-voice/voice
- **Push Notifications**: Firebase Cloud Messaging

## Project Structure

```
mobile/
├── src/
│   ├── screens/            # Screen components
│   │   ├── auth/           # Login, forgot password
│   │   ├── chat/           # Chat/Amos AI
│   │   ├── campaigns/      # Campaign list/detail
│   │   ├── contacts/       # Contact management
│   │   ├── landing-pages/  # Landing page management
│   │   └── settings/       # App settings
│   ├── components/         # Reusable UI components
│   ├── services/           # API service modules
│   ├── store/              # Redux store & slices
│   ├── utils/              # Helper functions
│   ├── types/              # TypeScript type definitions
│   ├── config/             # Configuration
│   ├── navigation/         # Navigation setup
│   └── App.tsx             # Root app component
├── index.tsx               # Entry point
├── app.json                # Expo configuration
├── tsconfig.json           # TypeScript config
├── babel.config.js         # Babel configuration
└── package.json            # Dependencies
```

## Installation & Setup

### Prerequisites

- Node.js 16+ and npm/yarn
- Expo CLI: `npm install -g expo-cli`
- Expo Go app on your phone (for testing)

### Quick Start

1. **Install dependencies**:
   ```bash
   cd mobile
   npm install
   ```

2. **Create .env file** from template:
   ```bash
   cp .env.example .env
   ```

3. **Update API configuration**:
   Edit `.env` and set `EXPO_PUBLIC_API_BASE_URL` to your API endpoint

4. **Start development server**:
   ```bash
   npm start
   ```

5. **Test on your device**:
   - Scan QR code with Expo Go app (iPhone/Android)
   - Or press `i` for iOS simulator or `a` for Android emulator

## Development

### Available Scripts

```bash
# Start development server (interactive)
npm start

# Start for iOS
npm run ios

# Start for Android
npm run android

# Run tests
npm test

# Type checking
npm run type-check

# Linting
npm run lint

# Format code
npm run format
```

### Project Architecture

#### Redux Store

Global state management with Redux Toolkit slices:

- **authSlice**: User authentication, login/logout
- **campaignsSlice**: Campaign list, details, operations
- **contactsSlice**: Contact list, groups, operations
- **uiSlice**: Theme, font size, notification settings

Access via:
```typescript
import { useAppDispatch, useAppSelector } from '@store';

const dispatch = useAppDispatch();
const { user, isAuthenticated } = useAppSelector(state => state.auth);
```

#### API Client

Axios-based HTTP client with interceptors at `src/services/api.ts`:

- Automatic Bearer token injection
- Request/response logging
- Error handling
- Token refresh logic

Service modules for each feature:
- `src/services/auth.ts` - Authentication
- `src/services/campaigns.ts` - Campaign operations
- `src/services/contacts.ts` - Contact operations

#### Navigation

Conditional navigation based on auth state:

- **AuthNavigator**: Login, forgot password (no auth required)
- **RootNavigator**: Tab-based navigation with 5 main screens

Update navigation in `src/navigation/index.tsx`

### Adding New Features

1. **Create screen component**:
   ```typescript
   // src/screens/feature/FeatureScreen.tsx
   export default function FeatureScreen() {
     return <View>{/* ... */}</View>;
   }
   ```

2. **Add to navigation**:
   ```typescript
   // src/navigation/index.tsx
   <Stack.Screen name="Feature" component={FeatureScreen} />
   ```

3. **Create API service** (if needed):
   ```typescript
   // src/services/feature.ts
   export async function getFeatureData() {
     return apiClient.get('/api/v1/feature');
   }
   ```

4. **Add Redux slice** (if needed):
   ```typescript
   // src/store/slices/featureSlice.ts
   const featureSlice = createSlice({...});
   ```

### Working with Types

All TypeScript types are in `src/types/index.ts`. Keep types organized:

- API models (User, Campaign, Contact, etc.)
- Redux state interfaces
- Props interfaces for components
- Utility type helpers

### Testing API Integration

Test API endpoints locally before deploying:

```typescript
// In any screen or effect
import * as campaignService from '@services/campaigns';

const campaigns = await campaignService.getCampaigns({ page: 1 });
```

## Configuration

### Environment Variables

Set these in `.env` (copy from `.env.example`):

```
EXPO_PUBLIC_API_BASE_URL=https://api.example.com
EXPO_PUBLIC_ENABLE_VOICE_INPUT=true
EXPO_PUBLIC_ENABLE_PUSH_NOTIFICATIONS=true
EXPO_PUBLIC_ENABLE_OFFLINE_MODE=true
```

### API Configuration

Update in `src/config/index.ts`:

- Base URL
- Timeout values
- Cache TTLs
- Pagination defaults
- Feature flags

## Building for Production

### iOS

```bash
# Build and submit to App Store
eas build --platform ios

# Or use Xcode for local building
npm run ios -- --configuration Release
```

### Android

```bash
# Build and submit to Google Play
eas build --platform android

# Or build APK
eas build --platform android --local
```

## Debugging

### Console Logs

View logs with:
```bash
npm start
# Then press `j` to open debugger
```

### Redux DevTools

Monitor store changes:
```typescript
import { useAppSelector } from '@store';

// View state updates in Redux DevTools browser extension
```

### Network Inspection

View API requests:
1. Start app in development
2. Press `j` for debugger
3. Check Network tab for API calls

### Logger

Use the built-in logger:
```typescript
import { log } from '@utils/logger';

log.debug('Message', { data: value });
log.info('Info message');
log.warn('Warning message');
log.error('Error message', error);

// Get all logs
const logs = log.getLogs();
```

## Common Tasks

### Add New API Endpoint

1. Create method in service file:
   ```typescript
   export async function newFeature(id: string) {
     return apiClient.get(`/api/v1/feature/${id}`);
   }
   ```

2. Create async thunk in Redux slice:
   ```typescript
   export const fetchFeature = createAsyncThunk(
     'feature/fetch',
     async (id: string) => {
       return featureService.newFeature(id);
     }
   );
   ```

3. Use in component:
   ```typescript
   const dispatch = useAppDispatch();
   dispatch(fetchFeature(id));
   ```

### Add New Screen

1. Create screen file in `src/screens/`
2. Add to navigation in `src/navigation/index.tsx`
3. Add Redux slice if managing state
4. Add types in `src/types/index.ts`

### Implement Voice Input

```typescript
import Voice from '@react-native-voice/voice';

const [transcript, setTranscript] = useState('');

const startListening = async () => {
  try {
    await Voice.start('en-US');
  } catch (e) {
    console.error(e);
  }
};

// Handle results
Voice.onSpeechResults = (e: any) => {
  setTranscript(e.value[0]);
};
```

### Handle Offline

```typescript
import { useAppSelector } from '@store';

const { isOnline } = useAppSelector(state => state.ui);

if (!isOnline) {
  // Show offline message or queue request
}
```

## Performance Tips

1. **Memoize components**: Use React.memo for list items
2. **Optimize re-renders**: Use selectors to minimize state subscriptions
3. **Lazy load images**: Use `Image` component with proper caching
4. **Paginate lists**: Load 20 items at a time, load more on scroll
5. **Cache API responses**: TTLs set in config (5-10 minutes)
6. **Use FlatList**: For long lists instead of ScrollView

## Troubleshooting

### App not starting

```bash
# Clear cache
rm -rf node_modules .expo
npm install
npm start
```

### API connection fails

1. Check `EXPO_PUBLIC_API_BASE_URL` in `.env`
2. Verify backend is running
3. Check network connectivity: `npm start` → press `d` for more debug info

### Build failures

```bash
# Clear build cache
npx expo prebuild --clean
npm install
npm start
```

### Token refresh issues

1. Check backend token endpoint
2. Verify token format in localStorage
3. Check auth service error handling

## Testing

### Unit Tests

```bash
npm test

# Watch mode
npm run test:watch
```

### E2E Tests (Manual)

1. Test login flow
2. Test campaign list loading
3. Test contact creation
4. Test offline functionality
5. Test push notifications

## Contributing

1. Create feature branch: `git checkout -b feature/my-feature`
2. Make changes and test locally
3. Run linter: `npm run lint`
4. Format code: `npm run format`
5. Commit: `git commit -m "feat: add my feature"`
6. Push and create PR

## Deployment

### TestFlight (iOS Beta)

```bash
eas build --platform ios
# Follow prompts to upload to TestFlight
```

### Google Play Beta

```bash
eas build --platform android
# Follow prompts to upload to Google Play Beta
```

## Resources

- [React Native Docs](https://reactnative.dev)
- [Expo Docs](https://docs.expo.dev)
- [Redux Toolkit Docs](https://redux-toolkit.js.org)
- [React Navigation Docs](https://reactnavigation.org)

## Support

For issues or questions:
1. Check logs: `npm start` → press `j`
2. Review error messages
3. Check API responses in network tab
4. Consult project documentation
5. Open issue with reproducible steps

## License

Same as main AMOS project
