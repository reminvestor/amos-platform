import React, { useState, useEffect } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
  TextInput,
  Modal,
  Switch,
  Platform,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import DateTimePicker from '@react-native-community/datetimepicker';
import { useAppDispatch, useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import { BottomSheet } from '@components/BottomSheet';
import * as campaignService from '@services/campaigns';
import { Campaign } from '@types';

interface CampaignEditScreenProps {
  navigation: any;
  route: any;
}

interface CampaignFormData {
  name: string;
  subject: string;
  fromName: string;
  fromEmail: string;
  body: string;
  template?: string;
  scheduledDate?: Date;
  isScheduled: boolean;
}

export default function CampaignEditScreen({ navigation, route }: CampaignEditScreenProps) {
  const insets = useSafeAreaInsets();
  const dispatch = useAppDispatch();
  const { campaignId } = route.params || {};
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const [formData, setFormData] = useState<CampaignFormData>({
    name: '',
    subject: '',
    fromName: '',
    fromEmail: '',
    body: '',
    isScheduled: false,
  });

  const [isLoading, setIsLoading] = useState(!!campaignId);
  const [isSaving, setIsSaving] = useState(false);
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showTimePicker, setShowTimePicker] = useState(false);
  const [templateModalVisible, setTemplateModalVisible] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});

  const templates = [
    { id: 'welcome', label: 'Welcome Series', icon: 'email' },
    { id: 'promotional', label: 'Promotional', icon: 'tag' },
    { id: 'newsletter', label: 'Newsletter', icon: 'newspaper' },
    { id: 'transactional', label: 'Transactional', icon: 'receipt' },
  ];

  useEffect(() => {
    if (campaignId) {
      loadCampaign();
    }
  }, [campaignId]);

  const loadCampaign = async () => {
    try {
      const campaign = await campaignService.getCampaignDetail(campaignId);
      setFormData({
        name: campaign.name,
        subject: campaign.subject,
        fromName: campaign.from_name || '',
        fromEmail: campaign.from_email || '',
        body: campaign.body || '',
        isScheduled: campaign.status === 'scheduled',
        scheduledDate: campaign.scheduled_at ? new Date(campaign.scheduled_at) : undefined,
      });
    } catch (error: any) {
      Alert.alert('Error', 'Failed to load campaign');
      navigation.goBack();
    } finally {
      setIsLoading(false);
    }
  };

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.name.trim()) newErrors.name = 'Campaign name is required';
    if (!formData.subject.trim()) newErrors.subject = 'Subject line is required';
    if (!formData.fromName.trim()) newErrors.fromName = 'From name is required';
    if (!formData.fromEmail.trim()) newErrors.fromEmail = 'From email is required';
    if (!formData.body.trim()) newErrors.body = 'Email body is required';

    if (formData.isScheduled && !formData.scheduledDate) {
      newErrors.scheduledDate = 'Schedule date/time is required';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSaveCampaign = async () => {
    if (!validateForm()) {
      Alert.alert('Validation Error', 'Please fill in all required fields');
      return;
    }

    setIsSaving(true);
    try {
      const payload: any = {
        name: formData.name,
        subject: formData.subject,
        from_name: formData.fromName,
        from_email: formData.fromEmail,
        body: formData.body,
        template: formData.template,
      };

      if (formData.isScheduled && formData.scheduledDate) {
        payload.scheduled_at = formData.scheduledDate.toISOString();
      }

      if (campaignId) {
        await campaignService.updateCampaign(campaignId, payload);
        Alert.alert('Success', 'Campaign updated successfully');
      } else {
        await campaignService.createCampaign(payload);
        Alert.alert('Success', 'Campaign created successfully');
      }

      navigation.goBack();
    } catch (error: any) {
      Alert.alert('Error', error.message || 'Failed to save campaign');
    } finally {
      setIsSaving(false);
    }
  };

  const handleDateChange = (event: any, selectedDate?: Date) => {
    if (Platform.OS === 'android') {
      setShowDatePicker(false);
    }
    if (selectedDate) {
      setFormData((prev) => ({
        ...prev,
        scheduledDate: selectedDate,
      }));
    }
  };

  const handleTimeChange = (event: any, selectedDate?: Date) => {
    if (Platform.OS === 'android') {
      setShowTimePicker(false);
    }
    if (selectedDate) {
      setFormData((prev) => ({
        ...prev,
        scheduledDate: selectedDate,
      }));
    }
  };

  if (isLoading) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      </View>
    );
  }

  const formattedDate = formData.scheduledDate
    ? formData.scheduledDate.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : 'Select date';

  const formattedTime = formData.scheduledDate
    ? formData.scheduledDate.toLocaleTimeString('en-US', {
        hour: '2-digit',
        minute: '2-digit',
      })
    : 'Select time';

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View style={[styles.header, { paddingTop: insets.top }]}>
          <TouchableOpacity onPress={() => navigation.goBack()}>
            <MaterialCommunityIcons name="arrow-left" size={24} color={colors.primary} />
          </TouchableOpacity>
          <StyledText style={[styles.headerTitle, { color: colors.text }]}>
            {campaignId ? 'Edit Campaign' : 'Create Campaign'}
          </StyledText>
          <View style={{ width: 24 }} />
        </View>

        {/* Campaign Name */}
        <View style={styles.section}>
          <StyledText style={[styles.label, { color: colors.text }]}>Campaign Name *</StyledText>
          <View
            style={[
              styles.input,
              {
                backgroundColor: colors.surface,
                borderColor: errors.name ? colors.error : colors.border,
              },
            ]}
          >
            <TextInput
              style={[styles.inputText, { color: colors.text }]}
              placeholder="e.g., Spring Promotion"
              placeholderTextColor={colors.textTertiary}
              value={formData.name}
              onChangeText={(text) => {
                setFormData((prev) => ({ ...prev, name: text }));
                setErrors((prev) => ({ ...prev, name: '' }));
              }}
            />
          </View>
          {errors.name && (
            <StyledText style={[styles.errorText, { color: colors.error }]}>
              {errors.name}
            </StyledText>
          )}
        </View>

        {/* Subject Line */}
        <View style={styles.section}>
          <StyledText style={[styles.label, { color: colors.text }]}>Subject Line *</StyledText>
          <View
            style={[
              styles.input,
              {
                backgroundColor: colors.surface,
                borderColor: errors.subject ? colors.error : colors.border,
              },
            ]}
          >
            <TextInput
              style={[styles.inputText, { color: colors.text }]}
              placeholder="What will your subscribers see?"
              placeholderTextColor={colors.textTertiary}
              value={formData.subject}
              onChangeText={(text) => {
                setFormData((prev) => ({ ...prev, subject: text }));
                setErrors((prev) => ({ ...prev, subject: '' }));
              }}
            />
          </View>
          {errors.subject && (
            <StyledText style={[styles.errorText, { color: colors.error }]}>
              {errors.subject}
            </StyledText>
          )}
        </View>

        {/* From Name & Email */}
        <View style={styles.section}>
          <StyledText style={[styles.label, { color: colors.text }]}>From Name *</StyledText>
          <View
            style={[
              styles.input,
              {
                backgroundColor: colors.surface,
                borderColor: errors.fromName ? colors.error : colors.border,
              },
            ]}
          >
            <TextInput
              style={[styles.inputText, { color: colors.text }]}
              placeholder="Your company name"
              placeholderTextColor={colors.textTertiary}
              value={formData.fromName}
              onChangeText={(text) => {
                setFormData((prev) => ({ ...prev, fromName: text }));
                setErrors((prev) => ({ ...prev, fromName: '' }));
              }}
            />
          </View>
          {errors.fromName && (
            <StyledText style={[styles.errorText, { color: colors.error }]}>
              {errors.fromName}
            </StyledText>
          )}
        </View>

        <View style={styles.section}>
          <StyledText style={[styles.label, { color: colors.text }]}>From Email *</StyledText>
          <View
            style={[
              styles.input,
              {
                backgroundColor: colors.surface,
                borderColor: errors.fromEmail ? colors.error : colors.border,
              },
            ]}
          >
            <TextInput
              style={[styles.inputText, { color: colors.text }]}
              placeholder="noreply@yourcompany.com"
              placeholderTextColor={colors.textTertiary}
              keyboardType="email-address"
              value={formData.fromEmail}
              onChangeText={(text) => {
                setFormData((prev) => ({ ...prev, fromEmail: text }));
                setErrors((prev) => ({ ...prev, fromEmail: '' }));
              }}
            />
          </View>
          {errors.fromEmail && (
            <StyledText style={[styles.errorText, { color: colors.error }]}>
              {errors.fromEmail}
            </StyledText>
          )}
        </View>

        {/* Email Body */}
        <View style={styles.section}>
          <StyledText style={[styles.label, { color: colors.text }]}>Email Body *</StyledText>
          <View
            style={[
              styles.textAreaInput,
              {
                backgroundColor: colors.surface,
                borderColor: errors.body ? colors.error : colors.border,
              },
            ]}
          >
            <TextInput
              style={[styles.inputText, styles.textAreaText, { color: colors.text }]}
              placeholder="Write your email content here..."
              placeholderTextColor={colors.textTertiary}
              multiline
              numberOfLines={6}
              value={formData.body}
              onChangeText={(text) => {
                setFormData((prev) => ({ ...prev, body: text }));
                setErrors((prev) => ({ ...prev, body: '' }));
              }}
              textAlignVertical="top"
            />
          </View>
          {errors.body && (
            <StyledText style={[styles.errorText, { color: colors.error }]}>
              {errors.body}
            </StyledText>
          )}
        </View>

        {/* Template Selection */}
        <View style={styles.section}>
          <StyledText style={[styles.label, { color: colors.text }]}>Template (Optional)</StyledText>
          <TouchableOpacity
            style={[styles.templateButton, { backgroundColor: colors.surface, borderColor: colors.border }]}
            onPress={() => setTemplateModalVisible(true)}
          >
            <MaterialCommunityIcons name="template" size={18} color={colors.primary} />
            <StyledText style={[styles.templateButtonText, { color: colors.text }]}>
              {formData.template
                ? templates.find((t) => t.id === formData.template)?.label || 'Select Template'
                : 'Choose a template'}
            </StyledText>
            <MaterialCommunityIcons name="chevron-right" size={18} color={colors.textTertiary} />
          </TouchableOpacity>
        </View>

        {/* Schedule Section */}
        <View style={styles.section}>
          <View style={styles.scheduleHeader}>
            <StyledText style={[styles.label, { color: colors.text }]}>Schedule Campaign</StyledText>
            <Switch
              value={formData.isScheduled}
              onValueChange={(value) =>
                setFormData((prev) => ({ ...prev, isScheduled: value }))
              }
              trackColor={{ false: colors.border, true: colors.primary }}
              thumbColor={formData.isScheduled ? '#0A84FF' : '#FFFFFF'}
            />
          </View>

          {formData.isScheduled && (
            <>
              <TouchableOpacity
                style={[styles.dateButton, { backgroundColor: colors.surface, borderColor: colors.border }]}
                onPress={() => setShowDatePicker(true)}
              >
                <MaterialCommunityIcons name="calendar" size={18} color={colors.primary} />
                <StyledText style={[styles.dateButtonText, { color: colors.text }]}>
                  {formattedDate}
                </StyledText>
              </TouchableOpacity>

              <TouchableOpacity
                style={[styles.dateButton, { backgroundColor: colors.surface, borderColor: colors.border }]}
                onPress={() => setShowTimePicker(true)}
              >
                <MaterialCommunityIcons name="clock" size={18} color={colors.primary} />
                <StyledText style={[styles.dateButtonText, { color: colors.text }]}>
                  {formattedTime}
                </StyledText>
              </TouchableOpacity>

              {errors.scheduledDate && (
                <StyledText style={[styles.errorText, { color: colors.error }]}>
                  {errors.scheduledDate}
                </StyledText>
              )}
            </>
          )}
        </View>

        <View style={{ height: insets.bottom + 120 }} />
      </ScrollView>

      {/* Action Buttons */}
      <View
        style={[
          styles.footer,
          {
            backgroundColor: colors.surface,
            borderTopColor: colors.border,
            paddingBottom: insets.bottom + 16,
          },
        ]}
      >
        <TouchableOpacity
          style={[styles.cancelButton, { backgroundColor: colors.muted }]}
          onPress={() => navigation.goBack()}
          disabled={isSaving}
        >
          <StyledText style={[styles.cancelButtonText, { color: colors.text }]}>Cancel</StyledText>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.saveButton, { backgroundColor: colors.primary }]}
          onPress={handleSaveCampaign}
          disabled={isSaving}
        >
          {isSaving ? (
            <ActivityIndicator size="small" color="#fff" />
          ) : (
            <>
              <MaterialCommunityIcons name="content-save" size={18} color="#fff" />
              <StyledText style={styles.saveButtonText}>
                {campaignId ? 'Update' : 'Create'} Campaign
              </StyledText>
            </>
          )}
        </TouchableOpacity>
      </View>

      {/* Template Modal */}
      <BottomSheet
        visible={templateModalVisible}
        onClose={() => setTemplateModalVisible(false)}
        title="Choose Template"
      >
        <View style={{ paddingBottom: 16 }}>
          {templates.map((template) => (
            <TouchableOpacity
              key={template.id}
              style={[
                styles.templateOption,
                {
                  backgroundColor: formData.template === template.id ? colors.primaryLight : 'transparent',
                },
              ]}
              onPress={() => {
                setFormData((prev) => ({ ...prev, template: template.id }));
                setTemplateModalVisible(false);
              }}
            >
              <MaterialCommunityIcons name={template.icon} size={20} color={colors.primary} />
              <StyledText
                style={[
                  styles.templateOptionText,
                  {
                    color: formData.template === template.id ? colors.primary : colors.text,
                  },
                ]}
              >
                {template.label}
              </StyledText>
              {formData.template === template.id && (
                <MaterialCommunityIcons name="check" size={20} color={colors.primary} />
              )}
            </TouchableOpacity>
          ))}
        </View>
      </BottomSheet>

      {/* Date Picker */}
      {showDatePicker && (
        <DateTimePicker
          value={formData.scheduledDate || new Date()}
          mode="date"
          display={Platform.OS === 'ios' ? 'spinner' : 'default'}
          onChange={handleDateChange}
          minimumDate={new Date()}
        />
      )}

      {/* Time Picker */}
      {showTimePicker && (
        <DateTimePicker
          value={formData.scheduledDate || new Date()}
          mode="time"
          display={Platform.OS === 'ios' ? 'spinner' : 'default'}
          onChange={handleTimeChange}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 32,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingBottom: 16,
    marginBottom: 16,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  section: {
    marginBottom: 20,
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
    paddingVertical: 10,
  },
  inputText: {
    fontSize: 14,
  },
  textAreaInput: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  textAreaText: {
    minHeight: 120,
  },
  errorText: {
    fontSize: 12,
    marginTop: 6,
  },
  templateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderWidth: 1,
    borderRadius: 8,
    gap: 8,
  },
  templateButtonText: {
    flex: 1,
    fontSize: 14,
  },
  scheduleHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  dateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderWidth: 1,
    borderRadius: 8,
    gap: 8,
    marginBottom: 12,
  },
  dateButtonText: {
    flex: 1,
    fontSize: 14,
  },
  templateOption: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderRadius: 8,
    marginBottom: 8,
    gap: 12,
  },
  templateOptionText: {
    flex: 1,
    fontSize: 14,
    fontWeight: '500',
  },
  footer: {
    flexDirection: 'row',
    gap: 12,
    paddingHorizontal: 16,
    paddingTop: 16,
    borderTopWidth: 1,
  },
  cancelButton: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  cancelButtonText: {
    fontWeight: '600',
    fontSize: 14,
  },
  saveButton: {
    flex: 1,
    flexDirection: 'row',
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  saveButtonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
});
