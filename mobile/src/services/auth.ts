import { apiClient } from './api';
import * as storage from '@utils/storage';
import { LoginCredentials, User } from '@types';

export interface LoginResponse {
  user: User;
  api_key: string;
  token: string;
}

export interface SessionResponse {
  user: User;
  token: string;
  expiresAt: number;
}

/**
 * Login with email and password
 */
export async function login(credentials: LoginCredentials): Promise<LoginResponse> {
  try {
    const response = await apiClient.post<LoginResponse>('/api/auth/login', {
      email: credentials.email,
      password: credentials.password,
    });

    // Store session
    if (response.token) {
      await storage.saveSession({
        token: response.api_key || response.token,
        user: response.user,
        expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days
      });
    }

    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Login failed',
      status: error.response?.status,
      details: error.response?.data,
    };
  }
}

/**
 * Logout user
 */
export async function logout(): Promise<void> {
  try {
    // Optional: Call backend logout endpoint
    // await apiClient.post('/api/auth/logout');

    // Clear local session
    await storage.clearSession();
  } catch (error) {
    // Always clear session even if logout fails
    await storage.clearSession();
    throw error;
  }
}

/**
 * Restore session from storage
 */
export async function restoreSession(): Promise<SessionResponse | null> {
  try {
    const session = await storage.getSession();

    if (!session) {
      return null;
    }

    // Check if session expired
    if (Date.now() > session.expiresAt) {
      await storage.clearSession();
      return null;
    }

    return {
      user: session.user,
      token: session.token,
      expiresAt: session.expiresAt,
    };
  } catch (error) {
    console.error('Error restoring session:', error);
    return null;
  }
}

/**
 * Refresh authentication token
 */
export async function refreshToken(): Promise<string> {
  try {
    const response = await apiClient.post<{ token: string }>('/api/auth/refresh_token', {});
    const newToken = response.token;

    // Update stored token
    const session = await storage.getSession();
    if (session) {
      await storage.saveSession({
        ...session,
        token: newToken,
      });
    }

    return newToken;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Token refresh failed',
      status: error.response?.status,
    };
  }
}

/**
 * Request password reset
 */
export async function requestPasswordReset(email: string): Promise<void> {
  try {
    await apiClient.post('/api/auth/forgot_password', { email });
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Password reset request failed',
      status: error.response?.status,
    };
  }
}

/**
 * Reset password with token
 */
export async function resetPassword(token: string, password: string): Promise<void> {
  try {
    await apiClient.post('/api/auth/reset_password', {
      token,
      password,
    });
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Password reset failed',
      status: error.response?.status,
    };
  }
}

/**
 * Get current user profile
 */
export async function getCurrentUser(): Promise<User> {
  try {
    const response = await apiClient.get<User>('/api/v1/users/profile');
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch user',
      status: error.response?.status,
    };
  }
}

/**
 * Update user profile
 */
export async function updateUserProfile(data: Partial<User>): Promise<User> {
  try {
    const response = await apiClient.patch<User>('/api/v1/users/profile', data);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to update profile',
      status: error.response?.status,
    };
  }
}
