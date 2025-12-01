import { configureStore } from '@reduxjs/toolkit';
import { TypedUseSelectorHook, useDispatch, useSelector } from 'react-redux';

import authReducer from './slices/authSlice';
import campaignsReducer from './slices/campaignsSlice';
import contactsReducer from './slices/contactsSlice';
import uiReducer from './slices/uiSlice';
import favoritesReducer from './slices/favoritesSlice';
import tasksReducer from './slices/tasksSlice';
import agentsReducer from './slices/agentsSlice';
import chatReducer from './slices/chatSlice';

export const store = configureStore({
  reducer: {
    auth: authReducer,
    campaigns: campaignsReducer,
    contacts: contactsReducer,
    ui: uiReducer,
    favorites: favoritesReducer,
    tasks: tasksReducer,
    agents: agentsReducer,
    chat: chatReducer,
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      serializableCheck: {
        ignoredActions: ['auth/loginUser/fulfilled'],
        ignoredPaths: ['auth.user'],
      },
    }),
});

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;

// Export pre-typed hooks
export const useAppDispatch = () => useDispatch<AppDispatch>();
export const useAppSelector: TypedUseSelectorHook<RootState> = useSelector;
