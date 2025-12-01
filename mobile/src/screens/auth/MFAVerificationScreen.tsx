import React, { useState, useRef, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  KeyboardAvoidingView,
  Platform,
  TouchableOpacity,
  ActivityIndicator,
} from 'react-native';
import OTPTextInput from 'react-native-otp-textinput';
import { Button, HelperText } from 'react-native-paper';
import { Shield, RefreshCw } from 'lucide-react-native';
import { useAppDispatch, useAppSelector } from '@store';
import { verifyMFA, resendMFACode } from '@store/slices/authSlice';
import { getColors } from '@theme/colors';

export default function MFAVerificationScreen() {
  const dispatch = useAppDispatch();
  const { isLoading, error, mfaSessionToken } = useAppSelector((state) => state.auth);
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const [code, setCode] = useState('');
  const [formError, setFormError] = useState('');
  const [isResending, setIsResending] = useState(false);
  const [resendCooldown, setResendCooldown] = useState(0);
  const otpInputRef = useRef<any>(null);

  // Resend cooldown timer
  useEffect(() => {
    if (resendCooldown > 0) {
      const timer = setTimeout(() => setResendCooldown(resendCooldown - 1), 1000);
      return () => clearTimeout(timer);
    }
  }, [resendCooldown]);

  const handleVerify = async () => {
    setFormError('');

    if (!code || code.length < 6) {
      setFormError('Please enter a valid 6-digit code');
      return;
    }

    if (!mfaSessionToken) {
      setFormError('MFA session expired. Please log in again.');
      return;
    }

    try {
      await dispatch(
        verifyMFA({
          mfa_session_token: mfaSessionToken,
          code,
        })
      ).unwrap();
    } catch (err: any) {
      setFormError(err.message || 'Verification failed');
      otpInputRef.current?.clear();
      setCode('');
    }
  };

  const handleResend = async () => {
    if (!mfaSessionToken || resendCooldown > 0) {
      return;
    }

    setFormError('');
    setIsResending(true);

    try {
      await dispatch(resendMFACode({ mfa_session_token: mfaSessionToken })).unwrap();
      setResendCooldown(60); // 60 second cooldown
      otpInputRef.current?.clear();
      setCode('');
    } catch (err: any) {
      setFormError(err.message || 'Failed to resend code');
    } finally {
      setIsResending(false);
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
          <View style={[styles.iconContainer, { backgroundColor: colors.primaryLight }]}>
            <Shield size={48} color={colors.primary} />
          </View>
          <Text style={[styles.title, { color: colors.text }]}>Two-Factor Authentication</Text>
          <Text style={[styles.subtitle, { color: colors.textSecondary }]}>
            Enter the 6-digit code from your authenticator app
          </Text>
        </View>

        <View style={styles.form}>
          <OTPTextInput
            ref={otpInputRef}
            handleTextChange={setCode}
            inputCount={6}
            keyboardType="number-pad"
            autoFocus
            tintColor={colors.primary}
            offTintColor={colors.border}
            textInputStyle={[
              styles.otpInput,
              {
                borderColor: colors.border,
                color: colors.text,
                backgroundColor: colors.surface,
              },
            ]}
            containerStyle={styles.otpContainer}
          />

          {displayError && (
            <HelperText type="error" visible={!!displayError} style={styles.errorText}>
              {displayError}
            </HelperText>
          )}

          <Button
            mode="contained"
            onPress={handleVerify}
            loading={isLoading}
            disabled={isLoading || code.length !== 6}
            style={styles.verifyButton}
            contentStyle={styles.buttonContent}
            labelStyle={styles.buttonLabel}
            buttonColor={colors.primary}
          >
            Verify Code
          </Button>

          <View style={styles.resendContainer}>
            <Text style={[styles.resendText, { color: colors.textSecondary }]}>
              Didn't receive the code?
            </Text>
            <TouchableOpacity
              onPress={handleResend}
              disabled={isResending || resendCooldown > 0}
              style={styles.resendButton}
            >
              {isResending ? (
                <ActivityIndicator size="small" color={colors.primary} />
              ) : (
                <View style={styles.resendButtonContent}>
                  <RefreshCw size={16} color={resendCooldown > 0 ? colors.textTertiary : colors.primary} />
                  <Text
                    style={[
                      styles.resendButtonText,
                      { color: resendCooldown > 0 ? colors.textTertiary : colors.primary },
                    ]}
                  >
                    {resendCooldown > 0 ? `Resend in ${resendCooldown}s` : 'Resend Code'}
                  </Text>
                </View>
              )}
            </TouchableOpacity>
          </View>
        </View>

        <View style={styles.footer}>
          <Text style={[styles.footerText, { color: colors.textTertiary }]}>
            For your security, this code expires after 5 minutes
          </Text>
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
  iconContainer: {
    width: 96,
    height: 96,
    borderRadius: 48,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 12,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 14,
    textAlign: 'center',
    paddingHorizontal: 20,
  },
  form: {
    flex: 1,
    justifyContent: 'center',
    paddingVertical: 40,
  },
  otpContainer: {
    marginBottom: 24,
  },
  otpInput: {
    borderRadius: 12,
    borderWidth: 2,
    fontSize: 24,
    fontWeight: '600',
    height: 56,
    width: 48,
  },
  errorText: {
    fontSize: 13,
    marginBottom: 16,
    textAlign: 'center',
  },
  verifyButton: {
    borderRadius: 8,
    marginBottom: 24,
  },
  buttonContent: {
    paddingVertical: 6,
  },
  buttonLabel: {
    fontSize: 16,
    fontWeight: '600',
  },
  resendContainer: {
    alignItems: 'center',
  },
  resendText: {
    fontSize: 13,
    marginBottom: 8,
  },
  resendButton: {
    padding: 8,
  },
  resendButtonContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  resendButtonText: {
    fontSize: 14,
    fontWeight: '600',
  },
  footer: {
    alignItems: 'center',
    marginBottom: 20,
  },
  footerText: {
    fontSize: 12,
    textAlign: 'center',
  },
});
