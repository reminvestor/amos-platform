import React, { useState } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  Alert,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UserPlus, Check } from 'lucide-react-native';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import * as contactService from '@services/contacts';

interface AddContactScreenProps {
  navigation: any;
  route: any;
}

export default function AddContactScreen({ navigation, route }: AddContactScreenProps) {
  const insets = useSafeAreaInsets();
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [formData, setFormData] = useState({
    first_name: '',
    last_name: '',
    email: '',
    phone: '',
    company: '',
    notes: '',
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const validateForm = () => {
    const newErrors: Record<string, string> = {};

    if (!formData.email.trim()) {
      newErrors.email = 'Email is required';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
      newErrors.email = 'Please enter a valid email';
    }

    if (!formData.first_name.trim() && !formData.last_name.trim()) {
      newErrors.first_name = 'Please enter a name';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async () => {
    if (!validateForm()) return;

    setIsSubmitting(true);
    try {
      await contactService.createContact({
        name: `${formData.first_name} ${formData.last_name}`.trim(),
        email: formData.email.trim(),
        phone: formData.phone.trim() || undefined,
        company: formData.company.trim() || undefined,
        notes: formData.notes.trim() || undefined,
        status: 'active',
      });

      Alert.alert('Success', 'Contact created successfully', [
        {
          text: 'OK',
          onPress: () => navigation.goBack(),
        },
      ]);
    } catch (error: any) {
      Alert.alert('Error', error.message || 'Failed to create contact');
    } finally {
      setIsSubmitting(false);
    }
  };

  const renderInput = (
    label: string,
    key: keyof typeof formData,
    options?: {
      placeholder?: string;
      keyboardType?: 'default' | 'email-address' | 'phone-pad';
      autoCapitalize?: 'none' | 'sentences' | 'words';
      multiline?: boolean;
    }
  ) => (
    <View style={styles.inputGroup}>
      <StyledText style={[styles.label, { color: colors.text }]}>{label}</StyledText>
      <TextInput
        style={[
          styles.input,
          {
            backgroundColor: colors.surface,
            borderColor: errors[key] ? colors.error : colors.border,
            color: colors.text,
          },
          options?.multiline && styles.multilineInput,
        ]}
        placeholder={options?.placeholder || `Enter ${label.toLowerCase()}`}
        placeholderTextColor={colors.textTertiary}
        value={formData[key]}
        onChangeText={(text) => {
          setFormData((prev) => ({ ...prev, [key]: text }));
          if (errors[key]) {
            setErrors((prev) => ({ ...prev, [key]: '' }));
          }
        }}
        keyboardType={options?.keyboardType || 'default'}
        autoCapitalize={options?.autoCapitalize || 'words'}
        multiline={options?.multiline}
        numberOfLines={options?.multiline ? 4 : 1}
      />
      {errors[key] && (
        <StyledText style={[styles.errorText, { color: colors.error }]}>
          {errors[key]}
        </StyledText>
      )}
    </View>
  );

  return (
    <KeyboardAvoidingView
      style={[styles.container, { backgroundColor: colors.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      keyboardVerticalOffset={100}
    >
      <ScrollView
        contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 100 }]}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
      >
        {/* Avatar placeholder */}
        <View style={styles.avatarSection}>
          <View style={[styles.avatar, { backgroundColor: colors.primaryLight }]}>
            <UserPlus size={40} color={colors.primary} />
          </View>
          <StyledText style={[styles.avatarHint, { color: colors.textSecondary }]}>
            New Contact
          </StyledText>
        </View>

        {/* Form */}
        <View style={[styles.formSection, { backgroundColor: colors.surface, borderColor: colors.border }]}>
          <View style={styles.row}>
            <View style={styles.halfInput}>
              {renderInput('First Name', 'first_name', { placeholder: 'John' })}
            </View>
            <View style={styles.halfInput}>
              {renderInput('Last Name', 'last_name', { placeholder: 'Doe' })}
            </View>
          </View>

          {renderInput('Email', 'email', {
            placeholder: 'john@example.com',
            keyboardType: 'email-address',
            autoCapitalize: 'none',
          })}

          {renderInput('Phone', 'phone', {
            placeholder: '+1 (555) 123-4567',
            keyboardType: 'phone-pad',
          })}

          {renderInput('Company', 'company', {
            placeholder: 'Company name',
          })}

          {renderInput('Notes', 'notes', {
            placeholder: 'Add any additional notes...',
            multiline: true,
            autoCapitalize: 'sentences',
          })}
        </View>
      </ScrollView>

      {/* Submit button */}
      <View style={[styles.footer, { backgroundColor: colors.background, paddingBottom: insets.bottom + 16 }]}>
        <TouchableOpacity
          style={[styles.submitButton, { backgroundColor: colors.primary }]}
          onPress={handleSubmit}
          disabled={isSubmitting}
        >
          {isSubmitting ? (
            <ActivityIndicator color="#FFFFFF" />
          ) : (
            <>
              <Check size={20} color="#FFFFFF" />
              <StyledText style={styles.submitButtonText}>Create Contact</StyledText>
            </>
          )}
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: 16,
  },
  avatarSection: {
    alignItems: 'center',
    marginBottom: 24,
    paddingTop: 8,
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  avatarHint: {
    fontSize: 14,
  },
  formSection: {
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
  },
  row: {
    flexDirection: 'row',
    marginHorizontal: -8,
  },
  halfInput: {
    flex: 1,
    paddingHorizontal: 8,
  },
  inputGroup: {
    marginBottom: 16,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 8,
  },
  input: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 12,
    fontSize: 16,
  },
  multilineInput: {
    minHeight: 100,
    textAlignVertical: 'top',
  },
  errorText: {
    fontSize: 12,
    marginTop: 4,
  },
  footer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: '#eee',
  },
  submitButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 14,
    borderRadius: 8,
  },
  submitButtonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
    marginLeft: 8,
  },
});
