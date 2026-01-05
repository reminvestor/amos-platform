import AsyncStorage from '@react-native-async-storage/async-storage';

const SEARCH_HISTORY_KEY_CAMPAIGNS = '@search_history_campaigns';
const SEARCH_HISTORY_KEY_CONTACTS = '@search_history_contacts';
const SEARCH_HISTORY_KEY_LANDING_PAGES = '@search_history_landing_pages';
const MAX_HISTORY_ITEMS = 10;

interface SearchHistoryItem {
  query: string;
  timestamp: number;
}

export const addSearchHistory = async (
  query: string,
  type: 'campaigns' | 'contacts' | 'landing_pages'
) => {
  if (!query.trim()) return;

  try {
    const key = getKeyForType(type);
    const history = await getSearchHistory(type);

    // Remove duplicate if exists
    const filtered = history.filter((item) => item.query.toLowerCase() !== query.toLowerCase());

    // Add new search to beginning
    const updated = [
      {
        query: query.trim(),
        timestamp: Date.now(),
      },
      ...filtered,
    ].slice(0, MAX_HISTORY_ITEMS);

    await AsyncStorage.setItem(key, JSON.stringify(updated));
  } catch (error) {
    console.log('Error saving search history:', error);
  }
};

export const getSearchHistory = async (
  type: 'campaigns' | 'contacts' | 'landing_pages'
): Promise<SearchHistoryItem[]> => {
  try {
    const key = getKeyForType(type);
    const data = await AsyncStorage.getItem(key);
    return data ? JSON.parse(data) : [];
  } catch (error) {
    console.log('Error getting search history:', error);
    return [];
  }
};

export const clearSearchHistory = async (
  type: 'campaigns' | 'contacts' | 'landing_pages'
) => {
  try {
    const key = getKeyForType(type);
    await AsyncStorage.removeItem(key);
  } catch (error) {
    console.log('Error clearing search history:', error);
  }
};

export const clearAllSearchHistory = async () => {
  try {
    await Promise.all([
      AsyncStorage.removeItem(SEARCH_HISTORY_KEY_CAMPAIGNS),
      AsyncStorage.removeItem(SEARCH_HISTORY_KEY_CONTACTS),
      AsyncStorage.removeItem(SEARCH_HISTORY_KEY_LANDING_PAGES),
    ]);
  } catch (error) {
    console.log('Error clearing all search history:', error);
  }
};

export const removeSearchHistoryItem = async (
  query: string,
  type: 'campaigns' | 'contacts' | 'landing_pages'
) => {
  try {
    const key = getKeyForType(type);
    const history = await getSearchHistory(type);
    const filtered = history.filter((item) => item.query !== query);
    await AsyncStorage.setItem(key, JSON.stringify(filtered));
  } catch (error) {
    console.log('Error removing search history item:', error);
  }
};

const getKeyForType = (
  type: 'campaigns' | 'contacts' | 'landing_pages'
): string => {
  switch (type) {
    case 'campaigns':
      return SEARCH_HISTORY_KEY_CAMPAIGNS;
    case 'contacts':
      return SEARCH_HISTORY_KEY_CONTACTS;
    case 'landing_pages':
      return SEARCH_HISTORY_KEY_LANDING_PAGES;
    default:
      return SEARCH_HISTORY_KEY_CAMPAIGNS;
  }
};
