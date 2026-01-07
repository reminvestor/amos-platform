import * as LocalAuthentication from 'expo-local-authentication';
import * as storage from '@utils/storage';
import type { BiometricAuthData } from '@types';

const BIOMETRIC_KEY = '@amos_biometric_auth';

/**
 * Check if biometric hardware is available
 */
export async function isBiometricSupported(): Promise<boolean> {
  try {
    const compatible = await LocalAuthentication.hasHardwareAsync();
    return compatible;
  } catch (error) {
    console.error('Error checking biometric support:', error);
    return false;
  }
}

/**
 * Check if user has enrolled biometric credentials
 */
export async function isBiometricEnrolled(): Promise<boolean> {
  try {
    const enrolled = await LocalAuthentication.isEnrolledAsync();
    return enrolled;
  } catch (error) {
    console.error('Error checking biometric enrollment:', error);
    return false;
  }
}

/**
 * Get available biometric types
 */
export async function getBiometricTypes(): Promise<LocalAuthentication.AuthenticationType[]> {
  try {
    const types = await LocalAuthentication.supportedAuthenticationTypesAsync();
    return types;
  } catch (error) {
    console.error('Error getting biometric types:', error);
    return [];
  }
}

/**
 * Get user-friendly name for biometric type
 */
export function getBiometricName(types: LocalAuthentication.AuthenticationType[]): string {
  if (types.includes(LocalAuthentication.AuthenticationType.FACIAL_RECOGNITION)) {
    return 'Face ID';
  }
  if (types.includes(LocalAuthentication.AuthenticationType.FINGERPRINT)) {
    return 'Touch ID';
  }
  if (types.includes(LocalAuthentication.AuthenticationType.IRIS)) {
    return 'Iris Recognition';
  }
  return 'Biometric';
}

/**
 * Authenticate with biometrics
 */
export async function authenticateWithBiometrics(promptMessage?: string): Promise<boolean> {
  try {
    const result = await LocalAuthentication.authenticateAsync({
      promptMessage: promptMessage || 'Authenticate to continue',
      fallbackLabel: 'Use passcode',
      disableDeviceFallback: false,
      cancelLabel: 'Cancel',
    });

    return result.success;
  } catch (error) {
    console.error('Biometric authentication error:', error);
    return false;
  }
}

/**
 * Save biometric auth data (encrypted credential)
 */
export async function saveBiometricCredential(email: string, credential: string): Promise<void> {
  try {
    const data: BiometricAuthData = { email, credential };
    await storage.saveItem(BIOMETRIC_KEY, JSON.stringify(data));
  } catch (error) {
    console.error('Error saving biometric credential:', error);
    throw error;
  }
}

/**
 * Get saved biometric auth data
 */
export async function getBiometricCredential(): Promise<BiometricAuthData | null> {
  try {
    const data = await storage.getItem(BIOMETRIC_KEY);
    if (!data) {
      return null;
    }
    return JSON.parse(data) as BiometricAuthData;
  } catch (error) {
    console.error('Error getting biometric credential:', error);
    return null;
  }
}

/**
 * Clear saved biometric auth data
 */
export async function clearBiometricCredential(): Promise<void> {
  try {
    await storage.removeItem(BIOMETRIC_KEY);
  } catch (error) {
    console.error('Error clearing biometric credential:', error);
    throw error;
  }
}

/**
 * Check if biometric login is available for user
 */
export async function isBiometricLoginAvailable(): Promise<boolean> {
  try {
    const supported = await isBiometricSupported();
    const enrolled = await isBiometricEnrolled();
    const credential = await getBiometricCredential();

    return supported && enrolled && credential !== null;
  } catch (error) {
    console.error('Error checking biometric login availability:', error);
    return false;
  }
}
