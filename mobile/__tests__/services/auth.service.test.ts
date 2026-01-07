import * as authService from '@services/auth';
import * as storage from '@utils/storage';
import { apiClient } from '@services/api';

jest.mock('@services/api');
jest.mock('@utils/storage');

describe('Auth Service', () => {
  const mockUser = {
    id: '1',
    email: 'test@example.com',
    name: 'Test User',
    role: 'marketer' as const,
    entity_id: 'entity-1',
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('login', () => {
    it('should login user with valid credentials', async () => {
      const credentials = { email: 'test@example.com', password: 'password' };
      const mockResponse = {
        user: mockUser,
        api_key: 'token-123',
        token: 'token-123',
      };

      (apiClient.post as jest.Mock).mockResolvedValue(mockResponse);
      (storage.saveSession as jest.Mock).mockResolvedValue(undefined);

      const result = await authService.login(credentials);

      expect(apiClient.post).toHaveBeenCalledWith(
        '/api/auth/login',
        expect.objectContaining({
          email: credentials.email,
          password: credentials.password,
        })
      );
      expect(storage.saveSession).toHaveBeenCalled();
      expect(result).toEqual(mockResponse);
    });

    it('should handle login error', async () => {
      const credentials = { email: 'test@example.com', password: 'wrong' };
      const mockError = {
        response: {
          status: 401,
          data: { message: 'Invalid credentials' },
        },
      };

      (apiClient.post as jest.Mock).mockRejectedValue(mockError);

      await expect(authService.login(credentials)).rejects.toMatchObject({
        message: 'Invalid credentials',
        status: 401,
      });
    });
  });

  describe('logout', () => {
    it('should logout user and clear session', async () => {
      (storage.clearSession as jest.Mock).mockResolvedValue(undefined);

      await authService.logout();

      expect(storage.clearSession).toHaveBeenCalled();
    });

    it('should clear session even if logout fails', async () => {
      (apiClient.post as jest.Mock).mockRejectedValue(new Error('Network error'));
      (storage.clearSession as jest.Mock).mockResolvedValue(undefined);

      await authService.logout();

      expect(storage.clearSession).toHaveBeenCalled();
    });
  });

  describe('restoreSession', () => {
    it('should restore valid session', async () => {
      const mockSession = {
        token: 'token-123',
        user: mockUser,
        expiresAt: Date.now() + 86400000, // tomorrow
      };

      (storage.getSession as jest.Mock).mockResolvedValue(mockSession);

      const result = await authService.restoreSession();

      expect(result).toEqual({
        user: mockUser,
        token: 'token-123',
        expiresAt: mockSession.expiresAt,
      });
    });

    it('should return null for expired session', async () => {
      const mockSession = {
        token: 'token-123',
        user: mockUser,
        expiresAt: Date.now() - 1000, // expired
      };

      (storage.getSession as jest.Mock).mockResolvedValue(mockSession);
      (storage.clearSession as jest.Mock).mockResolvedValue(undefined);

      const result = await authService.restoreSession();

      expect(result).toBeNull();
      expect(storage.clearSession).toHaveBeenCalled();
    });

    it('should return null if no session stored', async () => {
      (storage.getSession as jest.Mock).mockResolvedValue(null);

      const result = await authService.restoreSession();

      expect(result).toBeNull();
    });
  });

  describe('getCurrentUser', () => {
    it('should fetch current user profile', async () => {
      (apiClient.get as jest.Mock).mockResolvedValue(mockUser);

      const result = await authService.getCurrentUser();

      expect(apiClient.get).toHaveBeenCalledWith('/api/v1/users/profile');
      expect(result).toEqual(mockUser);
    });

    it('should handle fetch error', async () => {
      const mockError = {
        response: {
          status: 401,
          data: { message: 'Unauthorized' },
        },
      };

      (apiClient.get as jest.Mock).mockRejectedValue(mockError);

      await expect(authService.getCurrentUser()).rejects.toMatchObject({
        message: 'Unauthorized',
        status: 401,
      });
    });
  });

  describe('updateUserProfile', () => {
    it('should update user profile', async () => {
      const updates = { name: 'Updated Name' };
      const updatedUser = { ...mockUser, ...updates };

      (apiClient.patch as jest.Mock).mockResolvedValue(updatedUser);

      const result = await authService.updateUserProfile(updates);

      expect(apiClient.patch).toHaveBeenCalledWith('/api/v1/users/profile', updates);
      expect(result).toEqual(updatedUser);
    });
  });

  describe('requestPasswordReset', () => {
    it('should send password reset request', async () => {
      (apiClient.post as jest.Mock).mockResolvedValue({});

      await authService.requestPasswordReset('test@example.com');

      expect(apiClient.post).toHaveBeenCalledWith('/api/auth/forgot_password', {
        email: 'test@example.com',
      });
    });

    it('should handle reset request error', async () => {
      const mockError = {
        response: {
          status: 404,
          data: { message: 'User not found' },
        },
      };

      (apiClient.post as jest.Mock).mockRejectedValue(mockError);

      await expect(authService.requestPasswordReset('notfound@example.com')).rejects.toMatchObject({
        message: 'User not found',
        status: 404,
      });
    });
  });

  describe('resetPassword', () => {
    it('should reset password with token', async () => {
      (apiClient.post as jest.Mock).mockResolvedValue({});

      await authService.resetPassword('reset-token', 'newPassword123!');

      expect(apiClient.post).toHaveBeenCalledWith('/api/auth/reset_password', {
        token: 'reset-token',
        password: 'newPassword123!',
      });
    });
  });
});
