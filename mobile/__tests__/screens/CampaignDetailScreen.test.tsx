import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react-native';
import { Provider } from 'react-redux';
import { configureStore, PreloadedState } from '@reduxjs/toolkit';
import CampaignDetailScreen from '@screens/campaigns/CampaignDetailScreen';
import authReducer from '@store/slices/authSlice';
import campaignsReducer from '@store/slices/campaignsSlice';
import contactsReducer from '@store/slices/contactsSlice';
import uiReducer from '@store/slices/uiSlice';
import * as campaignService from '@services/campaigns';

// Mock navigation
const mockNavigation = {
  goBack: jest.fn(),
  navigate: jest.fn(),
};

const mockRoute = {
  params: {
    campaignId: 'campaign-123',
  },
};

// Mock campaign service
jest.mock('@services/campaigns');

// Mock useFocusEffect
jest.mock('@react-navigation/native', () => ({
  ...jest.requireActual('@react-navigation/native'),
  useFocusEffect: (callback: any) => {
    React.useEffect(() => {
      callback();
    }, []);
  },
}));

describe('CampaignDetailScreen', () => {
  const mockCampaign = {
    id: 'campaign-123',
    name: 'Test Campaign',
    subject: 'Welcome to our platform',
    status: 'in_progress',
    contact_count: 100,
    open_rate: 0.25,
    click_rate: 0.1,
    created_at: '2024-01-15T10:00:00Z',
    scheduled_at: '2024-01-20T10:00:00Z',
    from_name: 'Test Sender',
    from_email: 'sender@example.com',
    reply_to_email: 'reply@example.com',
  };

  const mockAnalytics = {
    sent_count: 100,
    opens: 25,
    clicks: 10,
    bounces: 2,
    unsubscribes: 1,
    complaints: 0,
    conversion_rate: 0.05,
    bounce_rate: 0.02,
  };

  const createTestStore = (preloadedState?: PreloadedState<any>) => {
    return configureStore({
      reducer: {
        auth: authReducer,
        campaigns: campaignsReducer,
        contacts: contactsReducer,
        ui: uiReducer,
      },
      preloadedState: {
        campaigns: {
          list: [],
          current: mockCampaign,
          isLoading: false,
          error: null,
          pagination: {
            page: 1,
            perPage: 20,
            total: 1,
            totalPages: 1,
          },
        },
        ...preloadedState,
      },
    });
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (campaignService.getCampaignAnalytics as jest.Mock).mockResolvedValue(mockAnalytics);
  });

  it('renders loading state initially', () => {
    const store = configureStore({
      reducer: {
        auth: authReducer,
        campaigns: campaignsReducer,
        contacts: contactsReducer,
        ui: uiReducer,
      },
      preloadedState: {
        campaigns: {
          list: [],
          current: null,
          isLoading: true,
          error: null,
          pagination: { page: 1, perPage: 20, total: 0, totalPages: 0 },
        },
      },
    });

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    expect(screen.getByText(/loading campaign details/i)).toBeTruthy();
  });

  it('renders campaign details successfully', async () => {
    const store = createTestStore();

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(mockCampaign.name)).toBeTruthy();
      expect(screen.getByText(mockCampaign.subject)).toBeTruthy();
    });
  });

  it('displays campaign status badge', async () => {
    const store = createTestStore();

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/in progress/i)).toBeTruthy();
    });
  });

  it('displays analytics metrics', async () => {
    const store = createTestStore();

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/open rate/i)).toBeTruthy();
      expect(screen.getByText(/click rate/i)).toBeTruthy();
      expect(screen.getByText(/25\.0%/)).toBeTruthy(); // open rate
      expect(screen.getByText(/10\.0%/)).toBeTruthy(); // click rate
    });
  });

  it('displays campaign information section', async () => {
    const store = createTestStore();

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/campaign information/i)).toBeTruthy();
      expect(screen.getByText(/created/i)).toBeTruthy();
      expect(screen.getByText(/recipients/i)).toBeTruthy();
    });
  });

  it('displays from details section', async () => {
    const store = createTestStore();

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/from details/i)).toBeTruthy();
      expect(screen.getByText(mockCampaign.from_name)).toBeTruthy();
      expect(screen.getByText(mockCampaign.from_email)).toBeTruthy();
    });
  });

  it('renders quick action buttons', async () => {
    const store = createTestStore();

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/edit campaign/i)).toBeTruthy();
      expect(screen.getByText(/duplicate campaign/i)).toBeTruthy();
      expect(screen.getByText(/send test email/i)).toBeTruthy();
      expect(screen.getByText(/archive campaign/i)).toBeTruthy();
    });
  });

  it('handles back button press', async () => {
    const store = createTestStore();

    const { getByTestId } = render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    // The back button is wrapped in TouchableOpacity, find it by position
    const backButton = screen.getByRole('button');
    if (backButton) {
      fireEvent.press(backButton);
      expect(mockNavigation.goBack).toHaveBeenCalled();
    }
  });

  it('shows error state when campaign not found', () => {
    const store = configureStore({
      reducer: {
        auth: authReducer,
        campaigns: campaignsReducer,
        contacts: contactsReducer,
        ui: uiReducer,
      },
      preloadedState: {
        campaigns: {
          list: [],
          current: null,
          isLoading: false,
          error: 'Campaign not found',
          pagination: { page: 1, perPage: 20, total: 0, totalPages: 0 },
        },
      },
    });

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    expect(screen.getByText(/campaign not found/i)).toBeTruthy();
  });

  it('fetches analytics data on load', async () => {
    const store = createTestStore();

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(campaignService.getCampaignAnalytics).toHaveBeenCalledWith('campaign-123');
    });
  });

  it('displays detailed statistics when analytics available', async () => {
    const store = createTestStore();

    render(
      <Provider store={store}>
        <CampaignDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/detailed statistics/i)).toBeTruthy();
      expect(screen.getByText(/total sent/i)).toBeTruthy();
    });
  });
});
