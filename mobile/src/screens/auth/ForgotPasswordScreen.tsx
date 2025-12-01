import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { TextInput, Button, IconButton, HelperText } from 'react-native-paper';
import { useNavigation } from '@react-navigation/native';
import { MailCheck, KeyRound } from 'lucide-react-native';
import { requestPasswordReset } from '@services/auth';
import { isValidEmail } from '@utils/validators';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';

export default function ForgotPasswordScreen() {
  const navigation = useNavigation<any>();
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const [email, setEmail] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);

  const handleResetPassword = async () => {
    setError('');

    if (!email) {
      setError('Please enter your email');
      return;
    }

    if (!isValidEmail(email)) {
      setError('Please enter a valid email');
      return;
    }

    setIsLoading(true);

    try {
      await requestPasswordReset(email);
      setSuccess(true);
    } catch (err: any) {
      setError(err.message || 'Failed to send reset email');
    } finally {
      setIsLoading(false);
    }
  };

  if (success) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.successContainer}>
          <View style={[styles.iconContainer, { backgroundColor: colors.successLight }]}>
            <MailCheck size={48} color={colors.success} />
          </View>
          <Text style={[styles.successTitle, { color: colors.text }]}>Check your email</Text>
          <Text style={[styles.successText, { color: colors.textSecondary }]}>
            We've sent a password reset link to {email}
          </Text>
          <Button
            mode="contained"
            onPress={() => navigation.goBack()}
            style={styles.button}
            contentStyle={styles.buttonContent}
            labelStyle={styles.buttonLabel}
            buttonColor={colors.primary}
          >
            Back to Login
          </Button>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.content}
      >
        <IconButton
          icon="arrow-left"
          size={24}
          iconColor={colors.text}
          onPress={() => navigation.goBack()}
          style={styles.backButton}
        />

        <View style={styles.header}>
          <View style={[styles.iconContainer, { backgroundColor: colors.primaryLight }]}>
            <KeyRound size={48} color={colors.primary} />
          </View>
          <Text style={[styles.title, { color: colors.text }]}>Forgot Password?</Text>
          <Text style={[styles.subtitle, { color: colors.textSecondary }]}>
            Enter your email and we'll send you a link to reset your password.
          </Text>
        </View>

        <View style={styles.form}>
          <TextInput
            label="Email"
            value={email}
            onChangeText={setEmail}
            mode="outlined"
            keyboardType="email-address"
            autoCapitalize="none"
            autoFocus
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

          {error && (
            <HelperText type="error" visible={!!error} style={styles.errorText}>
              {error}
            </HelperText>
          )}

          <Button
            mode="contained"
            onPress={handleResetPassword}
            loading={isLoading}
            disabled={isLoading}
            style={styles.submitButton}
            contentStyle={styles.buttonContent}
            labelStyle={styles.buttonLabel}
            buttonColor={colors.primary}
          >
            Send Reset Link
          </Button>
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
  },
  backButton: {
    marginLeft: -8,
    marginBottom: 12,
  },
  header: {
    alignItems: 'center',
    marginBottom: 40,
  },
  iconContainer: {
    width: 100,
    height: 100,
    borderRadius: 50,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    textAlign: 'center',
    paddingHorizontal: 20,
  },
  form: {
    flex: 1,
  },
  input: {
    marginBottom: 8,
    backgroundColor: 'transparent',
  },
  errorText: {
    fontSize: 13,
    marginBottom: 8,
  },
  button: {
    borderRadius: 8,
    marginTop: 20,
  },
  submitButton: {
    borderRadius: 8,
    marginTop: 12,
  },
  buttonContent: {
    paddingVertical: 6,
  },
  buttonLabel: {
    fontSize: 16,
    fontWeight: '600',
  },
  successContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  successTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  successText: {
    fontSize: 14,
    textAlign: 'center',
    marginBottom: 30,
    paddingHorizontal: 20,
  },
});
