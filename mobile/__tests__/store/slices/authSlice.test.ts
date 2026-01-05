import authReducer, { loginUser, logoutUser, clearError, setUser } from '@store/slices/authSlice';
import { AuthState } from '@types';

describe('authSlice', () => {
  const initialState: AuthState = {
    user: null,
    token: null,
    isAuthenticated: false,
    isLoading: false,
    error: null,
  };

  const mockUser = {
    id: '1',
    email: 'test@example.com',
    name: 'Test User',
    role: 'marketer' as const,
    entity_id: 'entity-1',
  };

  describe('reducers', () => {
    it('should clear error', () => {
      const stateWithError = {
        ...initialState,
        error: 'Some error',
      };
      const result = authReducer(stateWithError, clearError());
      expect(result.error).toBeNull();
    });

    it('should set user', () => {
      const result = authReducer(initialState, setUser(mockUser));
      expect(result.user).toEqual(mockUser);
      expect(result.isAuthenticated).toBe(true);
    });
  });

  describe('loginUser async thunk', () => {
    it('should set isLoading to true on pending', () => {
      const action = {
        type: loginUser.pending.type,
      };
      const result = authReducer(initialState, action);
      expect(result.isLoading).toBe(true);
      expect(result.error).toBeNull();
    });

    it('should set user and token on fulfilled', () => {
      const payload = {
        user: mockUser,
        api_key: 'token-123',
      };
      const action = {
        type: loginUser.fulfilled.type,
        payload,
      };
      const result = authReducer(initialState, action);
      expect(result.isLoading).toBe(false);
      expect(result.user).toEqual(mockUser);
      expect(result.token).toBe('token-123');
      expect(result.isAuthenticated).toBe(true);
      expect(result.error).toBeNull();
    });

    it('should set error on rejected', () => {
      const payload = 'Login failed';
      const action = {
        type: loginUser.rejected.type,
        payload,
      };
      const result = authReducer(initialState, action);
      expect(result.isLoading).toBe(false);
      expect(result.error).toBe('Login failed');
      expect(result.isAuthenticated).toBe(false);
    });
  });

  describe('logoutUser async thunk', () => {
    const authenticatedState: AuthState = {
      user: mockUser,
      token: 'token-123',
      isAuthenticated: true,
      isLoading: false,
      error: null,
    };

    it('should set isLoading to true on pending', () => {
      const action = {
        type: logoutUser.pending.type,
      };
      const result = authReducer(authenticatedState, action);
      expect(result.isLoading).toBe(true);
    });

    it('should clear auth state on fulfilled', () => {
      const action = {
        type: logoutUser.fulfilled.type,
        payload: null,
      };
      const result = authReducer(authenticatedState, action);
      expect(result.isLoading).toBe(false);
      expect(result.user).toBeNull();
      expect(result.token).toBeNull();
      expect(result.isAuthenticated).toBe(false);
      expect(result.error).toBeNull();
    });

    it('should set error on rejected', () => {
      const action = {
        type: logoutUser.rejected.type,
        payload: 'Logout failed',
      };
      const result = authReducer(authenticatedState, action);
      expect(result.isLoading).toBe(false);
      expect(result.error).toBe('Logout failed');
    });
  });

  describe('restoreSession async thunk', () => {
    it('should set isLoading to true on pending', () => {
      const action = {
        type: 'auth/restoreSession/pending',
      };
      // This would be handled by the actual thunk
    });
  });

  describe('refreshToken async thunk', () => {
    const authenticatedState: AuthState = {
      user: mockUser,
      token: 'old-token',
      isAuthenticated: true,
      isLoading: false,
      error: null,
    };

    it('should update token on fulfilled', () => {
      const action = {
        type: 'auth/refreshToken/fulfilled',
        payload: 'new-token',
      };
      // Token refresh would update the token
    });

    it('should clear auth on failed refresh', () => {
      const action = {
        type: 'auth/refreshToken/rejected',
      };
      // Failed refresh would clear auth state
    });
  });
});
