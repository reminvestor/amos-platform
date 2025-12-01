import { createSlice, PayloadAction } from '@reduxjs/toolkit';
import { NotificationSettings } from '@types';

interface UIState {
  theme: 'light' | 'dark';
  fontSize: 'small' | 'medium' | 'large';
  isOnline: boolean;
  notificationSettings: NotificationSettings;
}

const initialState: UIState = {
  theme: 'dark',
  fontSize: 'medium',
  isOnline: true,
  notificationSettings: {
    campaignStatus: true,
    formSubmissions: true,
    alerts: true,
    general: true,
  },
};

const uiSlice = createSlice({
  name: 'ui',
  initialState,
  reducers: {
    setTheme: (state, action: PayloadAction<'light' | 'dark'>) => {
      state.theme = action.payload;
    },
    setFontSize: (state, action: PayloadAction<'small' | 'medium' | 'large'>) => {
      state.fontSize = action.payload;
    },
    setOnlineStatus: (state, action: PayloadAction<boolean>) => {
      state.isOnline = action.payload;
    },
    updateNotificationSettings: (state, action: PayloadAction<Partial<NotificationSettings>>) => {
      state.notificationSettings = {
        ...state.notificationSettings,
        ...action.payload,
      };
    },
  },
});

export const { setTheme, setFontSize, setOnlineStatus, updateNotificationSettings } =
  uiSlice.actions;
export default uiSlice.reducer;
