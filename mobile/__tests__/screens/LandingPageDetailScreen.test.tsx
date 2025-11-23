import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react-native';
import { Provider } from 'react-redux';
import { configureMockStore } from '@testing-library/redux';
import LandingPageDetailScreen from '@screens/landing-pages/LandingPageDetailScreen';
import * as landingPageService from '@services/landing-pages';

jest.mock('@services/landing-pages');
jest.mock('@react-navigation/native');

const mockNavigate = jest.fn();
const mockGoBack = jest.fn();

const mockNavigation = {
  navigate: mockNavigate,
  goBack: mockGoBack,
};

const mockRoute = {
  params: {
    landingPageId: 'page-123',
  },
};

const mockLandingPage = {
  id: 'page-123',
  title: 'Summer Sale Landing Page',
  description: 'Promote our summer sale with this beautiful landing page',
  status: 'published',
  url: 'https://amos.example.com/summer-sale',
  views: 1250,
  submissions: 87,
  conversion_rate: 0.0696,
  created_at: '2024-06-01',
  published_at: '2024-06-05',
  updated_at: '2024-11-15',
  recent_submissions: [
    {
      id: 'sub-1',
      name: 'Jane Smith',
      email: 'jane@example.com',
      submitted_at: '2024-11-20',
    },
    {
      id: 'sub-2',
      name: 'Bob Johnson',
      email: 'bob@example.com',
      submitted_at: '2024-11-19',
    },
  ],
};

describe('LandingPageDetailScreen', () => {
  let store: any;

  beforeEach(() => {
    jest.clearAllMocks();
    store = configureMockStore({
      ui: {
        theme: 'light',
        fontSize: 'medium',
        isOnline: true,
        notificationSettings: {},
      },
      auth: {
        user: { id: '1', name: 'Test User', email: 'test@example.com' },
      },
      favorites: {
        campaignIds: [],
        contactIds: [],
      },
    })();
  });

  it('renders loading state initially', () => {
    (landingPageService.getLandingPageDetail as jest.Mock).mockImplementation(
      () => new Promise(() => {})
    );

    render(
      <Provider store={store}>
        <LandingPageDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    expect(screen.getByText(/loading landing page/i)).toBeTruthy();
  });

  it('renders landing page details after loading', async () => {
    (landingPageService.getLandingPageDetail as jest.Mock).resolvedValue(
      mockLandingPage
    );

    render(
      <Provider store={store}>
        <LandingPageDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(mockLandingPage.title)).toBeTruthy();
      expect(screen.getByText(/published/i)).toBeTruthy();
    });
  });

  it('displays performance metrics', async () => {
    (landingPageService.getLandingPageDetail as jest.Mock).resolvedValue(
      mockLandingPage
    );

    render(
      <Provider store={store}>
        <LandingPageDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(mockLandingPage.views.toString())).toBeTruthy();
      expect(screen.getByText(mockLandingPage.submissions.toString())).toBeTruthy();
      expect(screen.getByText(/6.96%/)).toBeTruthy();
    });
  });

  it('displays recent submissions', async () => {
    (landingPageService.getLandingPageDetail as jest.Mock).resolvedValue(
      mockLandingPage
    );

    render(
      <Provider store={store}>
        <LandingPageDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText('Jane Smith')).toBeTruthy();
      expect(screen.getByText('jane@example.com')).toBeTruthy();
      expect(screen.getByText('Bob Johnson')).toBeTruthy();
      expect(screen.getByText('bob@example.com')).toBeTruthy();
    });
  });

  it('handles publish toggle', async () => {
    (landingPageService.getLandingPageDetail as jest.Mock).resolvedValue(
      mockLandingPage
    );
    (landingPageService.unpublishLandingPage as jest.Mock).resolvedValue({
      ...mockLandingPage,
      status: 'draft',
    });

    render(
      <Provider store={store}>
        <LandingPageDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/unpublish/i)).toBeTruthy();
    });

    const unpublishButton = screen.getByText(/unpublish/i);
    fireEvent.press(unpublishButton);

    expect(landingPageService.unpublishLandingPage).toHaveBeenCalledWith(
      mockLandingPage.id
    );
  });

  it('handles delete action', async () => {
    (landingPageService.getLandingPageDetail as jest.Mock).resolvedValue(
      mockLandingPage
    );
    (landingPageService.deleteLandingPage as jest.Mock).resolvedValue(undefined);

    render(
      <Provider store={store}>
        <LandingPageDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      const deleteButton = screen.getByTestId('delete-button');
      fireEvent.press(deleteButton);
    });

    expect(landingPageService.deleteLandingPage).toHaveBeenCalledWith(
      mockLandingPage.id
    );
  });

  it('shows error state when loading fails', async () => {
    (landingPageService.getLandingPageDetail as jest.Mock).rejectValue(
      new Error('Failed to load landing page')
    );

    render(
      <Provider store={store}>
        <LandingPageDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/failed to load landing page/i)).toBeTruthy();
    });
  });

  it('navigates back on back button press', async () => {
    (landingPageService.getLandingPageDetail as jest.Mock).resolvedValue(
      mockLandingPage
    );

    render(
      <Provider store={store}>
        <LandingPageDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(mockLandingPage.title)).toBeTruthy();
    });

    const backButton = screen.getByTestId('back-button');
    fireEvent.press(backButton);

    expect(mockGoBack).toHaveBeenCalled();
  });

  it('displays page details section', async () => {
    (landingPageService.getLandingPageDetail as jest.Mock).resolvedValue(
      mockLandingPage
    );

    render(
      <Provider store={store}>
        <LandingPageDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/details/i)).toBeTruthy();
      expect(screen.getByText(/created/i)).toBeTruthy();
      expect(screen.getByText(/published/i)).toBeTruthy();
    });
  });
});
