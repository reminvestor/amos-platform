import { createSlice, createAsyncThunk, PayloadAction } from '@reduxjs/toolkit';
import { AuthState, LoginCredentials, User, MFAVerifyRequest, MFAResendRequest } from '@types';
import * as authService from '@services/auth';
import * as mfaService from '@services/mfa';

interface ExtendedAuthState extends AuthState {
  mfaSessionToken: string | null;
  mfaRequired: boolean;
}

const initialState: ExtendedAuthState = {
  user: null,
  token: null,
  isAuthenticated: false,
  isLoading: false,
  error: null,
  mfaSessionToken: null,
  mfaRequired: false,
};

// Async Thunks
export const loginUser = createAsyncThunk(
  'auth/login',
  async (credentials: LoginCredentials, { rejectWithValue }) => {
    try {
      const response = await authService.login(credentials);
      return response;
    } catch (error: any) {
      return rejectWithValue(error.response?.data || error.message);
    }
  }
);

export const logoutUser = createAsyncThunk(
  'auth/logout',
  async (_, { rejectWithValue }) => {
    try {
      await authService.logout();
      return null;
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const restoreSession = createAsyncThunk(
  'auth/restoreSession',
  async (_, { rejectWithValue }) => {
    try {
      const session = await authService.restoreSession();
      return session;
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const refreshToken = createAsyncThunk(
  'auth/refreshToken',
  async (_, { rejectWithValue }) => {
    try {
      const newToken = await authService.refreshToken();
      return newToken;
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

// MFA Verification
export const verifyMFA = createAsyncThunk(
  'auth/verifyMFA',
  async (request: MFAVerifyRequest, { rejectWithValue }) => {
    try {
      const response = await mfaService.verifyMFACode(request);
      return response;
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

// Resend MFA Code
export const resendMFACode = createAsyncThunk(
  'auth/resendMFACode',
  async (request: MFAResendRequest, { rejectWithValue }) => {
    try {
      const response = await mfaService.resendMFACode(request);
      return response;
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

const authSlice = createSlice({
  name: 'auth',
  initialState,
  reducers: {
    clearError: (state) => {
      state.error = null;
    },
    setUser: (state, action: PayloadAction<User>) => {
      state.user = action.payload;
      state.isAuthenticated = true;
    },
    setMFARequired: (state, action: PayloadAction<{ required: boolean; sessionToken: string | null }>) => {
      state.mfaRequired = action.payload.required;
      state.mfaSessionToken = action.payload.sessionToken;
    },
    clearMFA: (state) => {
      state.mfaRequired = false;
      state.mfaSessionToken = null;
    },
  },
  extraReducers: (builder) => {
    // Login
    builder
      .addCase(loginUser.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(loginUser.fulfilled, (state, action) => {
        state.isLoading = false;

        // Check if MFA is required
        if (action.payload.mfa_required && action.payload.mfa_session_token) {
          state.mfaRequired = true;
          state.mfaSessionToken = action.payload.mfa_session_token;
          state.isAuthenticated = false;
        } else {
          state.user = action.payload.user;
          state.token = action.payload.api_key;
          state.isAuthenticated = true;
          state.mfaRequired = false;
          state.mfaSessionToken = null;
        }
        state.error = null;
      })
      .addCase(loginUser.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
        state.isAuthenticated = false;
      });

    // Logout
    builder
      .addCase(logoutUser.pending, (state) => {
        state.isLoading = true;
      })
      .addCase(logoutUser.fulfilled, (state) => {
        state.isLoading = false;
        state.user = null;
        state.token = null;
        state.isAuthenticated = false;
        state.error = null;
        state.mfaRequired = false;
        state.mfaSessionToken = null;
      })
      .addCase(logoutUser.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Restore Session
    builder
      .addCase(restoreSession.pending, (state) => {
        state.isLoading = true;
      })
      .addCase(restoreSession.fulfilled, (state, action) => {
        if (action.payload) {
          state.user = action.payload.user;
          state.token = action.payload.token;
          state.isAuthenticated = true;
        }
        state.isLoading = false;
        state.error = null;
      })
      .addCase(restoreSession.rejected, (state, action) => {
        state.isLoading = false;
        state.user = null;
        state.token = null;
        state.isAuthenticated = false;
        state.error = action.payload as string;
      });

    // Refresh Token
    builder
      .addCase(refreshToken.fulfilled, (state, action) => {
        state.token = action.payload;
      })
      .addCase(refreshToken.rejected, (state) => {
        // On refresh failure, clear auth state
        state.user = null;
        state.token = null;
        state.isAuthenticated = false;
      });

    // Verify MFA
    builder
      .addCase(verifyMFA.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(verifyMFA.fulfilled, (state, action) => {
        state.isLoading = false;
        state.user = action.payload.user;
        state.token = action.payload.api_key;
        state.isAuthenticated = true;
        state.mfaRequired = false;
        state.mfaSessionToken = null;
        state.error = null;
      })
      .addCase(verifyMFA.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Resend MFA Code
    builder
      .addCase(resendMFACode.pending, (state) => {
        state.error = null;
      })
      .addCase(resendMFACode.fulfilled, (state) => {
        state.error = null;
      })
      .addCase(resendMFACode.rejected, (state, action) => {
        state.error = action.payload as string;
      });
  },
});

export const { clearError, setUser, setMFARequired, clearMFA } = authSlice.actions;
export default authSlice.reducer;
