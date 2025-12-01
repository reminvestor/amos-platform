import React, { useEffect, useState } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { Provider } from 'react-redux';
import { Provider as PaperProvider, MD3LightTheme } from 'react-native-paper';
import { StatusBar } from 'expo-status-bar';
import * as SplashScreen from 'expo-splash-screen';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { store } from '@store';
import { useAppDispatch, useAppSelector } from '@store';
import { restoreSession } from '@store/slices/authSlice';
import { RootNavigator, AuthNavigator } from './navigation';
import { TaskMonitorProvider } from './contexts/TaskMonitorContext';

// Custom theme extending MD3
const theme = {
  ...MD3LightTheme,
  colors: {
    ...MD3LightTheme.colors,
    primary: '#6366f1',
    primaryContainer: '#e0e7ff',
    secondary: '#8b5cf6',
    secondaryContainer: '#e0e7ff', // Changed from pinkish to indigo light (matches primary)
    surface: '#ffffff',
    surfaceVariant: '#f3f4f6',
    background: '#f9fafb',
    error: '#ef4444',
    onPrimary: '#ffffff',
    onSecondary: '#ffffff',
    onSecondaryContainer: '#4338ca', // Dark indigo text on selected segments
    onSurface: '#111827',
    onSurfaceVariant: '#6b7280',
    outline: '#d1d5db',
  },
  roundness: 2, // Reduce global roundness for more squared look
};

// Keep the splash screen visible while we fetch resources
SplashScreen.preventAutoHideAsync();

export default function App() {
  return (
    <Provider store={store}>
      <AppContent />
    </Provider>
  );
}

function AppContent() {
  const dispatch = useAppDispatch();
  const { isAuthenticated, isLoading } = useAppSelector((state) => state.auth);
  const [appReady, setAppReady] = useState(false);

  useEffect(() => {
    async function bootstrapAsync() {
      try {
        // Restore session from storage
        await dispatch(restoreSession()).unwrap();
      } catch (error) {
        // Failed to restore session, user will need to login
        console.error('Error restoring session:', error);
      } finally {
        setAppReady(true);
      }
    }

    bootstrapAsync();
  }, [dispatch]);

  useEffect(() => {
    if (appReady && !isLoading) {
      SplashScreen.hideAsync();
    }
  }, [appReady, isLoading]);

  // Show splash screen while app is loading
  if (!appReady || isLoading) {
    return null;
  }

  return (
    <SafeAreaProvider>
      <PaperProvider theme={theme}>
        <TaskMonitorProvider>
          <NavigationContainer>
            <StatusBar style="dark" />
            {isAuthenticated ? <RootNavigator /> : <AuthNavigator />}
          </NavigationContainer>
        </TaskMonitorProvider>
      </PaperProvider>
    </SafeAreaProvider>
  );
}
