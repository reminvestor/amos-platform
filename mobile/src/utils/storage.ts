import AsyncStorage from '@react-native-async-storage/async-storage';
import { StoredSession, User } from '@types';
import { Config } from '@config';

/**
 * Save user session to local storage
 */
export async function saveSession(session: StoredSession): Promise<void> {
  try {
    await AsyncStorage.setItem(Config.storage.sessionKey, JSON.stringify(session));
  } catch (error) {
    console.error('Error saving session:', error);
    throw error;
  }
}

/**
 * Get user session from local storage
 */
export async function getSession(): Promise<StoredSession | null> {
  try {
    const sessionStr = await AsyncStorage.getItem(Config.storage.sessionKey);
    if (!sessionStr) {
      return null;
    }
    return JSON.parse(sessionStr);
  } catch (error) {
    console.error('Error getting session:', error);
    return null;
  }
}

/**
 * Get stored token
 */
export async function getToken(): Promise<string | null> {
  try {
    const session = await getSession();
    return session?.token || null;
  } catch (error) {
    console.error('Error getting token:', error);
    return null;
  }
}

/**
 * Clear session from storage
 */
export async function clearSession(): Promise<void> {
  try {
    await AsyncStorage.removeItem(Config.storage.sessionKey);
  } catch (error) {
    console.error('Error clearing session:', error);
    throw error;
  }
}

/**
 * Save app settings
 */
export async function saveSettings(settings: Record<string, any>): Promise<void> {
  try {
    await AsyncStorage.setItem(Config.storage.settingsKey, JSON.stringify(settings));
  } catch (error) {
    console.error('Error saving settings:', error);
    throw error;
  }
}

/**
 * Get app settings
 */
export async function getSettings(): Promise<Record<string, any>> {
  try {
    const settingsStr = await AsyncStorage.getItem(Config.storage.settingsKey);
    return settingsStr ? JSON.parse(settingsStr) : {};
  } catch (error) {
    console.error('Error getting settings:', error);
    return {};
  }
}

/**
 * Save cached data
 */
export async function saveCache(key: string, data: any, ttl?: number): Promise<void> {
  try {
    const cacheData = {
      data,
      timestamp: Date.now(),
      ttl: ttl || Config.cache.campaigns,
    };
    const cacheKey = `${Config.storage.cacheKey}_${key}`;
    await AsyncStorage.setItem(cacheKey, JSON.stringify(cacheData));
  } catch (error) {
    console.error('Error saving cache:', error);
    throw error;
  }
}

/**
 * Get cached data
 */
export async function getCache<T>(key: string): Promise<T | null> {
  try {
    const cacheKey = `${Config.storage.cacheKey}_${key}`;
    const cacheStr = await AsyncStorage.getItem(cacheKey);

    if (!cacheStr) {
      return null;
    }

    const cacheData = JSON.parse(cacheStr);
    const now = Date.now();
    const age = (now - cacheData.timestamp) / 1000; // age in seconds

    // Check if cache has expired
    if (age > cacheData.ttl) {
      await AsyncStorage.removeItem(cacheKey);
      return null;
    }

    return cacheData.data;
  } catch (error) {
    console.error('Error getting cache:', error);
    return null;
  }
}

/**
 * Clear specific cache
 */
export async function clearCache(key: string): Promise<void> {
  try {
    const cacheKey = `${Config.storage.cacheKey}_${key}`;
    await AsyncStorage.removeItem(cacheKey);
  } catch (error) {
    console.error('Error clearing cache:', error);
    throw error;
  }
}

/**
 * Clear all cache
 */
export async function clearAllCache(): Promise<void> {
  try {
    const allKeys = await AsyncStorage.getAllKeys();
    const cacheKeys = allKeys.filter((key) => key.startsWith(Config.storage.cacheKey));
    await AsyncStorage.multiRemove(cacheKeys);
  } catch (error) {
    console.error('Error clearing all cache:', error);
    throw error;
  }
}

/**
 * Check if device is online
 */
export async function isOnline(): Promise<boolean> {
  // This would use react-native-netinfo in a real app
  return true;
}

/**
 * Save queue item for offline operation
 */
export async function queueOfflineRequest(
  key: string,
  request: { method: string; url: string; data?: any }
): Promise<void> {
  try {
    const queue = await getOfflineQueue();
    queue.push({ id: Date.now().toString(), ...request });
    await AsyncStorage.setItem(
      '@offline_queue',
      JSON.stringify(queue)
    );
  } catch (error) {
    console.error('Error queuing offline request:', error);
    throw error;
  }
}

/**
 * Get offline queue
 */
export async function getOfflineQueue(): Promise<any[]> {
  try {
    const queueStr = await AsyncStorage.getItem('@offline_queue');
    return queueStr ? JSON.parse(queueStr) : [];
  } catch (error) {
    console.error('Error getting offline queue:', error);
    return [];
  }
}

/**
 * Clear offline queue
 */
export async function clearOfflineQueue(): Promise<void> {
  try {
    await AsyncStorage.removeItem('@offline_queue');
  } catch (error) {
    console.error('Error clearing offline queue:', error);
    throw error;
  }
}
