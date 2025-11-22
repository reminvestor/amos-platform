import Constants from 'expo-constants';

const API_BASE_URL = process.env.EXPO_PUBLIC_API_BASE_URL || 'https://api.example.com';
const APP_ENV = process.env.EXPO_PUBLIC_APP_ENV || 'development';
const LOG_LEVEL = process.env.EXPO_PUBLIC_LOG_LEVEL || 'debug';

export const Config = {
  // API Configuration
  api: {
    baseURL: API_BASE_URL,
    timeout: 30000,
    defaultParams: {
      per_page: 20,
    },
  },

  // Environment
  env: APP_ENV,
  isDevelopment: APP_ENV === 'development',
  isProduction: APP_ENV === 'production',

  // Logging
  logging: {
    level: LOG_LEVEL as 'debug' | 'info' | 'warn' | 'error',
  },

  // Feature Flags
  features: {
    voiceInput: process.env.EXPO_PUBLIC_ENABLE_VOICE_INPUT !== 'false',
    pushNotifications: process.env.EXPO_PUBLIC_ENABLE_PUSH_NOTIFICATIONS !== 'false',
    offlineMode: process.env.EXPO_PUBLIC_ENABLE_OFFLINE_MODE !== 'false',
  },

  // Storage
  storage: {
    sessionKey: '@amos_session',
    settingsKey: '@amos_settings',
    cacheKey: '@amos_cache',
  },

  // Pagination
  pagination: {
    defaultPerPage: 20,
    maxPerPage: 100,
  },

  // Timeouts (in milliseconds)
  timeouts: {
    api: 30000,
    fileUpload: 60000,
    videoUpload: 120000,
    operationTimeout: 5000,
  },

  // Cache TTL (in seconds)
  cache: {
    campaigns: 300, // 5 minutes
    contacts: 300,
    landingPages: 600, // 10 minutes
    user: 1800, // 30 minutes
  },

  // UI Constants
  ui: {
    defaultFontSize: 'medium',
    defaultTheme: 'light',
  },

  // Voice Configuration
  voice: {
    language: 'en-US',
    maxDuration: 60, // seconds
  },

  // Version Info
  version: {
    app: Constants.expoConfig?.version || '0.1.0',
    build: Constants.expoConfig?.plugins?.length || 0,
  },
};

export default Config;
