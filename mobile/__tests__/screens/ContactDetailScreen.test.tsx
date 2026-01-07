import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react-native';
import { Provider } from 'react-redux';
import { configureMockStore } from '@testing-library/redux';
import ContactDetailScreen from '@screens/contacts/ContactDetailScreen';
import * as contactService from '@services/contacts';

jest.mock('@services/contacts');
jest.mock('@react-navigation/native');

const mockNavigate = jest.fn();
const mockGoBack = jest.fn();

const mockNavigation = {
  navigate: mockNavigate,
  goBack: mockGoBack,
};

const mockRoute = {
  params: {
    contactId: 'contact-123',
  },
};

const mockContact = {
  id: 'contact-123',
  name: 'John Doe',
  email: 'john@example.com',
  phone: '+1234567890',
  status: 'active',
  created_at: '2024-01-01',
  last_engaged_at: '2024-11-20',
  bounce_status: null,
  tags: ['vip', 'customer'],
};

describe('ContactDetailScreen', () => {
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
    (contactService.getContact as jest.Mock).mockImplementation(
      () => new Promise(() => {})
    );

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    expect(screen.getByText(/loading contact/i)).toBeTruthy();
  });

  it('renders contact details after loading', async () => {
    (contactService.getContact as jest.Mock).mockResolvedValue(mockContact);

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(mockContact.name)).toBeTruthy();
      expect(screen.getByText(mockContact.email)).toBeTruthy();
    });
  });

  it('displays contact information sections', async () => {
    (contactService.getContact as jest.Mock).resolvedValue(mockContact);

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/contact information/i)).toBeTruthy();
      expect(screen.getByText(mockContact.phone)).toBeTruthy();
    });
  });

  it('displays tags when present', async () => {
    (contactService.getContact as jest.Mock).resolvedValue(mockContact);

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText('vip')).toBeTruthy();
      expect(screen.getByText('customer')).toBeTruthy();
    });
  });

  it('displays status management section', async () => {
    (contactService.getContact as jest.Mock).resolvedValue(mockContact);

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/status/i)).toBeTruthy();
      expect(screen.getByText('Active')).toBeTruthy();
    });
  });

  it('handles delete action', async () => {
    (contactService.getContact as jest.Mock).resolvedValue(mockContact);
    (contactService.deleteContact as jest.Mock).resolvedValue(undefined);

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      const deleteButton = screen.getByTestId('delete-button');
      fireEvent.press(deleteButton);
    });

    // Alert would be shown, confirming deletion
    expect(contactService.deleteContact).toHaveBeenCalledWith(mockContact.id);
  });

  it('handles status update', async () => {
    (contactService.getContact as jest.Mock).resolvedValue(mockContact);
    (contactService.updateContact as jest.Mock).resolvedValue({
      ...mockContact,
      status: 'inactive',
    });

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      const inactiveButton = screen.getByText('Inactive');
      fireEvent.press(inactiveButton);
    });

    expect(contactService.updateContact).toHaveBeenCalled();
  });

  it('shows error state when loading fails', async () => {
    (contactService.getContact as jest.Mock).rejectValue(
      new Error('Failed to load contact')
    );

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(/failed to load contact/i)).toBeTruthy();
    });
  });

  it('has retry button in error state', async () => {
    (contactService.getContact as jest.Mock).rejectValue(
      new Error('Failed to load contact')
    );

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      const retryButton = screen.getByText(/try again/i);
      expect(retryButton).toBeTruthy();
    });
  });

  it('navigates back on back button press', async () => {
    (contactService.getContact as jest.Mock).resolvedValue(mockContact);

    render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(mockContact.name)).toBeTruthy();
    });

    const backButton = screen.getByTestId('back-button');
    fireEvent.press(backButton);

    expect(mockGoBack).toHaveBeenCalled();
  });

  it('supports pull-to-refresh', async () => {
    (contactService.getContact as jest.Mock).resolvedValue(mockContact);

    const { getByTestId } = render(
      <Provider store={store}>
        <ContactDetailScreen navigation={mockNavigation} route={mockRoute} />
      </Provider>
    );

    await waitFor(() => {
      expect(screen.getByText(mockContact.name)).toBeTruthy();
    });

    // Simulate refresh
    const refreshControl = getByTestId('refresh-control');
    fireEvent(refreshControl, 'refresh');

    expect(contactService.getContact).toHaveBeenCalled();
  });
});
