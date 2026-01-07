import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  KeyboardAvoidingView,
  Platform,
  TouchableOpacity,
  Image,
} from 'react-native';
import { TextInput, Button, HelperText } from 'react-native-paper';
import { Fingerprint } from 'lucide-react-native';

const logoHeader = require('../../../assets/logo-header.png');
import { useNavigation } from '@react-navigation/native';
import { useAppDispatch, useAppSelector } from '@store';
import { loginUser } from '@store/slices/authSlice';
import { isValidEmail } from '@utils/validators';
import { getColors } from '@theme/colors';
import * as biometricService from '@services/biometric';

export default function LoginScreen() {
  const navigation = useNavigation<any>();
  const dispatch = useAppDispatch();
  const { isLoading, error, mfaRequired } = useAppSelector((state) => state.auth);
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  // Hardcoded for testing - remove in production
  const [email, setEmail] = useState('admin@demo.com');
  const [password, setPassword] = useState('password123');
  const [formError, setFormError] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [biometricAvailable, setBiometricAvailable] = useState(false);
  const [biometricName, setBiometricName] = useState('Biometric');

  // Check biometric availability on mount
  useEffect(() => {
    checkBiometricAvailability();
  }, []);

  // Navigate to MFA screen when MFA is required
  useEffect(() => {
    if (mfaRequired) {
      navigation.navigate('MFAVerification');
    }
  }, [mfaRequired, navigation]);

  const checkBiometricAvailability = async () => {
    try {
      const available = await biometricService.isBiometricLoginAvailable();
      if (available) {
        const types = await biometricService.getBiometricTypes();
        setBiometricName(biometricService.getBiometricName(types));
        setBiometricAvailable(true);
      }
    } catch (error) {
      console.error('Error checking biometric availability:', error);
    }
  };

  const handleBiometricLogin = async () => {
    try {
      const credential = await biometricService.getBiometricCredential();
      if (!credential) {
        setFormError('No saved biometric credentials found');
        return;
      }

      const authenticated = await biometricService.authenticateWithBiometrics(
        `Sign in to AMOS with ${biometricName}`
      );

      if (authenticated) {
        setEmail(credential.email);
        // Use the stored credential (encrypted token) to authenticate
        // For now, we'll need the user to enter password after biometric auth
        // In a production app, you'd implement token-based biometric auth
        setFormError(`Biometric authentication successful. Please enter your password.`);
      } else {
        setFormError('Biometric authentication failed');
      }
    } catch (error: any) {
      setFormError(error.message || 'Biometric authentication failed');
    }
  };

  const handleLogin = async () => {
    setFormError('');

    if (!email || !password) {
      setFormError('Please fill in all fields');
      return;
    }

    if (!isValidEmail(email)) {
      setFormError('Please enter a valid email');
      return;
    }

    try {
      const result = await dispatch(
        loginUser({
          email,
          password,
        })
      ).unwrap();

      // If MFA not required and login successful, save biometric credential
      if (!result.mfa_required && result.api_key) {
        const shouldSaveBiometric = await biometricService.isBiometricEnrolled();
        if (shouldSaveBiometric) {
          try {
            await biometricService.saveBiometricCredential(email, result.api_key);
          } catch (err) {
            console.error('Failed to save biometric credential:', err);
          }
        }
      }
    } catch (err: any) {
      setFormError(err.message || 'Login failed');
    }
  };

  const displayError = formError || error;

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.content}
      >
        <View style={styles.header}>
          <Image
            source={logoHeader}
            style={[
              styles.logo,
              theme === 'light' && { tintColor: '#1a1a2e' }
            ]}
            resizeMode="contain"
          />
        </View>

        <View style={styles.form}>
          <TextInput
            label="Email"
            value={email}
            onChangeText={setEmail}
            mode="outlined"
            keyboardType="email-address"
            autoCapitalize="none"
            disabled={isLoading}
            style={styles.input}
            outlineColor={colors.border}
            activeOutlineColor={colors.primary}
            textColor={colors.text}
            theme={{
              colors: {
                surfaceVariant: colors.surface,
                onSurfaceVariant: colors.textSecondary,
              }
            }}
          />

          <TextInput
            label="Password"
            value={password}
            onChangeText={setPassword}
            mode="outlined"
            secureTextEntry={!showPassword}
            disabled={isLoading}
            style={styles.input}
            outlineColor={colors.border}
            activeOutlineColor={colors.primary}
            textColor={colors.text}
            right={
              <TextInput.Icon
                icon={showPassword ? 'eye-off' : 'eye'}
                onPress={() => setShowPassword(!showPassword)}
                color={colors.textSecondary}
              />
            }
            theme={{
              colors: {
                surfaceVariant: colors.surface,
                onSurfaceVariant: colors.textSecondary,
              }
            }}
          />

          {displayError && (
            <HelperText type="error" visible={!!displayError} style={styles.errorText}>
              {displayError}
            </HelperText>
          )}

          <Button
            mode="contained"
            onPress={handleLogin}
            loading={isLoading}
            disabled={isLoading}
            style={styles.signInButton}
            contentStyle={styles.buttonContent}
            labelStyle={styles.buttonLabel}
            buttonColor={colors.primary}
          >
            Sign In
          </Button>

          {biometricAvailable && (
            <TouchableOpacity
              style={[styles.biometricButton, { borderColor: colors.border }]}
              onPress={handleBiometricLogin}
              disabled={isLoading}
            >
              <Fingerprint size={24} color={colors.primary} />
              <Text style={[styles.biometricButtonText, { color: colors.text }]}>
                Sign in with {biometricName}
              </Text>
            </TouchableOpacity>
          )}

          <Button
            mode="text"
            onPress={() => navigation.navigate('ForgotPassword')}
            style={styles.forgotPasswordButton}
            labelStyle={[styles.linkLabel, { color: colors.primary }]}
          >
            Forgot Password?
          </Button>
        </View>

        <View style={styles.footer}>
          <Text style={[styles.footerText, { color: colors.textSecondary }]}>
            Don't have an account?{' '}
            <Text style={[styles.footerLink, { color: colors.primary }]}>Sign up on the web</Text>
          </Text>
          <View style={styles.legalLinks}>
            <Button
              mode="text"
              onPress={() => navigation.navigate('Terms')}
              labelStyle={[styles.legalLabel, { color: colors.textTertiary }]}
              compact
            >
              Terms of Service
            </Button>
            <Text style={[styles.legalSeparator, { color: colors.textTertiary }]}>|</Text>
            <Button
              mode="text"
              onPress={() => navigation.navigate('Privacy')}
              labelStyle={[styles.legalLabel, { color: colors.textTertiary }]}
              compact
            >
              Privacy Policy
            </Button>
          </View>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    flex: 1,
    padding: 20,
    justifyContent: 'space-between',
  },
  header: {
    marginTop: 40,
    alignItems: 'center',
  },
  logo: {
    width: 160,
    height: 44,
    marginBottom: 16,
  },
  subtitle: {
    fontSize: 14,
  },
  form: {
    flex: 1,
    justifyContent: 'center',
  },
  input: {
    marginBottom: 12,
    backgroundColor: 'transparent',
  },
  errorText: {
    fontSize: 13,
    marginBottom: 8,
  },
  signInButton: {
    marginTop: 8,
    borderRadius: 8,
  },
  buttonContent: {
    paddingVertical: 6,
  },
  buttonLabel: {
    fontSize: 16,
    fontWeight: '600',
  },
  biometricButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    paddingVertical: 14,
    borderRadius: 8,
    borderWidth: 1,
    marginTop: 16,
  },
  biometricButtonText: {
    fontSize: 15,
    fontWeight: '500',
  },
  forgotPasswordButton: {
    marginTop: 8,
  },
  linkLabel: {
    fontSize: 13,
  },
  footer: {
    alignItems: 'center',
    marginBottom: 20,
  },
  footerText: {
    fontSize: 13,
  },
  footerLink: {
    fontWeight: '600',
  },
  legalLinks: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 4,
  },
  legalLabel: {
    fontSize: 12,
  },
  legalSeparator: {
    fontSize: 12,
  },
});
