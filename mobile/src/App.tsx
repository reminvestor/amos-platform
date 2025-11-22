import React, { useEffect, useState } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { Provider } from 'react-redux';
import { StatusBar } from 'expo-status-bar';
import * as SplashScreen from 'expo-splash-screen';

import { store } from '@store';
import { useAppDispatch, useAppSelector } from '@store';
import { restoreSession } from '@store/slices/authSlice';
import { RootNavigator, AuthNavigator } from './navigation';

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
    <NavigationContainer>
      <StatusBar barStyle="dark-content" />
      {isAuthenticated ? <RootNavigator /> : <AuthNavigator />}
    </NavigationContainer>
  );
}
