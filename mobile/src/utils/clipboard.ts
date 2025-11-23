import * as Clipboard from 'expo-clipboard';
import { Alert } from 'react-native';

export const copyToClipboard = async (text: string, label: string = 'Text') => {
  try {
    await Clipboard.setStringAsync(text);
    Alert.alert('Copied', `${label} copied to clipboard`);
    return true;
  } catch (error) {
    Alert.alert('Error', 'Failed to copy to clipboard');
    return false;
  }
};

export const pasteFromClipboard = async () => {
  try {
    const text = await Clipboard.getStringAsync();
    return text;
  } catch (error) {
    console.log('Error pasting from clipboard:', error);
    return null;
  }
};
