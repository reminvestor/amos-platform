import React, { useState } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  Switch,
  TouchableOpacity,
  Alert,
  ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useAppDispatch, useAppSelector } from '@store';
import { setTheme, setFontSize, updateNotificationSettings } from '@store/slices/uiSlice';
import { logout } from '@store/slices/authSlice';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import { BottomSheet } from '@components/BottomSheet';

interface SettingsScreenProps {
  navigation: any;
}

export default function SettingsScreen({ navigation }: SettingsScreenProps) {
  const insets = useSafeAreaInsets();
  const dispatch = useAppDispatch();

  const { theme, fontSize, notificationSettings } = useAppSelector((state) => state.ui);
  const { user, isLoading } = useAppSelector((state) => state.auth);
  const colors = getColors(theme);

  const [fontSizeModalVisible, setFontSizeModalVisible] = useState(false);
  const [loggingOut, setLoggingOut] = useState(false);

  const handleThemeToggle = (value: boolean) => {
    const newTheme = value ? 'dark' : 'light';
    dispatch(setTheme(newTheme));
  };

  const handleFontSizeSelect = (size: 'small' | 'medium' | 'large') => {
    dispatch(setFontSize(size));
    setFontSizeModalVisible(false);
  };

  const handleNotificationToggle = (key: keyof typeof notificationSettings, value: boolean) => {
    dispatch(updateNotificationSettings({ [key]: value }));
  };

  const handleLogout = async () => {
    Alert.alert('Logout', 'Are you sure you want to logout?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Logout',
        style: 'destructive',
        onPress: async () => {
          setLoggingOut(true);
          try {
            await dispatch(logout()).unwrap();
            navigation.reset({
              index: 0,
              routes: [{ name: 'Auth' }],
            });
          } catch (error) {
            Alert.alert('Error', 'Failed to logout. Please try again.');
            setLoggingOut(false);
          }
        },
      },
    ]);
  };

  const handleDeleteAccount = () => {
    Alert.alert(
      'Delete Account',
      'This action cannot be undone. All your data will be permanently deleted.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => Alert.alert('Not Implemented', 'Account deletion will be implemented soon.'),
        },
      ]
    );
  };

  const fontSizes = [
    { label: 'Small', value: 'small' as const },
    { label: 'Medium', value: 'medium' as const },
    { label: 'Large', value: 'large' as const },
  ];

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView
        contentContainerStyle={[styles.content, { paddingTop: insets.top + 16 }]}
        showsVerticalScrollIndicator={false}
      >
        {/* Profile Section */}
        <View style={[styles.section, { borderBottomColor: colors.border }]}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Profile</StyledText>

          <TouchableOpacity
            style={[styles.profileCard, { backgroundColor: colors.surface, borderColor: colors.border }]}
            activeOpacity={0.7}
            onPress={() => Alert.alert('Not Implemented', 'Profile editing coming soon')}
          >
            <View style={styles.profileInfo}>
              <View style={[styles.avatar, { backgroundColor: colors.primary }]}>
                <StyledText style={{ color: '#FFFFFF', fontSize: 20, fontWeight: 'bold' }}>
                  {user?.name?.charAt(0).toUpperCase()}
                </StyledText>
              </View>
              <View>
                <StyledText style={[styles.profileName, { color: colors.text }]}>
                  {user?.name || 'User'}
                </StyledText>
                <StyledText style={[styles.profileEmail, { color: colors.textSecondary }]}>
                  {user?.email}
                </StyledText>
              </View>
            </View>
            <MaterialCommunityIcons name="chevron-right" size={24} color={colors.textTertiary} />
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.settingRow, { borderBottomColor: colors.border }]}
            onPress={() => Alert.alert('Not Implemented', 'Password change coming soon')}
          >
            <View style={styles.settingLeft}>
              <MaterialCommunityIcons name="lock" size={20} color={colors.primary} />
              <StyledText style={[styles.settingLabel, { color: colors.text }]}>Change Password</StyledText>
            </View>
            <MaterialCommunityIcons name="chevron-right" size={20} color={colors.textTertiary} />
          </TouchableOpacity>
        </View>

        {/* Appearance Section */}
        <View style={[styles.section, { borderBottomColor: colors.border }]}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Appearance</StyledText>

          <View style={[styles.settingRow, { borderBottomColor: colors.border }]}>
            <View style={styles.settingLeft}>
              <MaterialCommunityIcons
                name={theme === 'dark' ? 'moon-waning-crescent' : 'white-balance-sunny'}
                size={20}
                color={colors.primary}
              />
              <StyledText style={[styles.settingLabel, { color: colors.text }]}>Dark Mode</StyledText>
            </View>
            <Switch
              value={theme === 'dark'}
              onValueChange={handleThemeToggle}
              trackColor={{ false: colors.border, true: colors.primary }}
              thumbColor={theme === 'dark' ? '#0A84FF' : '#FFFFFF'}
            />
          </View>

          <TouchableOpacity
            style={[styles.settingRow, { borderBottomColor: colors.border }]}
            onPress={() => setFontSizeModalVisible(true)}
          >
            <View style={styles.settingLeft}>
              <MaterialCommunityIcons name="format-font-size-increase" size={20} color={colors.primary} />
              <StyledText style={[styles.settingLabel, { color: colors.text }]}>Font Size</StyledText>
            </View>
            <View style={styles.settingRight}>
              <StyledText style={[styles.settingValue, { color: colors.textSecondary }]}>
                {fontSize.charAt(0).toUpperCase() + fontSize.slice(1)}
              </StyledText>
              <MaterialCommunityIcons name="chevron-right" size={20} color={colors.textTertiary} />
            </View>
          </TouchableOpacity>
        </View>

        {/* Notifications Section */}
        <View style={[styles.section, { borderBottomColor: colors.border }]}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Notifications</StyledText>

          <View style={[styles.settingRow, { borderBottomColor: colors.border }]}>
            <View style={styles.settingLeft}>
              <MaterialCommunityIcons name="bell" size={20} color={colors.primary} />
              <StyledText style={[styles.settingLabel, { color: colors.text }]}>All Notifications</StyledText>
            </View>
            <Switch
              value={notificationSettings.general}
              onValueChange={(value) => handleNotificationToggle('general', value)}
              trackColor={{ false: colors.border, true: colors.primary }}
              thumbColor={notificationSettings.general ? '#0A84FF' : '#FFFFFF'}
            />
          </View>

          {notificationSettings.general && (
            <>
              <View style={[styles.settingRow, { borderBottomColor: colors.border }]}>
                <View style={styles.settingLeft}>
                  <MaterialCommunityIcons name="email" size={20} color={colors.info} />
                  <StyledText style={[styles.settingLabel, { color: colors.text }]}>Campaign Status</StyledText>
                </View>
                <Switch
                  value={notificationSettings.campaignStatus}
                  onValueChange={(value) => handleNotificationToggle('campaignStatus', value)}
                  trackColor={{ false: colors.border, true: colors.primary }}
                  thumbColor={notificationSettings.campaignStatus ? '#0A84FF' : '#FFFFFF'}
                />
              </View>

              <View style={[styles.settingRow, { borderBottomColor: colors.border }]}>
                <View style={styles.settingLeft}>
                  <MaterialCommunityIcons name="form-textarea" size={20} color={colors.success} />
                  <StyledText style={[styles.settingLabel, { color: colors.text }]}>Form Submissions</StyledText>
                </View>
                <Switch
                  value={notificationSettings.formSubmissions}
                  onValueChange={(value) => handleNotificationToggle('formSubmissions', value)}
                  trackColor={{ false: colors.border, true: colors.primary }}
                  thumbColor={notificationSettings.formSubmissions ? '#0A84FF' : '#FFFFFF'}
                />
              </View>

              <View style={[styles.settingRow, { borderBottomColor: colors.border }]}>
                <View style={styles.settingLeft}>
                  <MaterialCommunityIcons name="alert-circle" size={20} color={colors.warning} />
                  <StyledText style={[styles.settingLabel, { color: colors.text }]}>Alerts</StyledText>
                </View>
                <Switch
                  value={notificationSettings.alerts}
                  onValueChange={(value) => handleNotificationToggle('alerts', value)}
                  trackColor={{ false: colors.border, true: colors.primary }}
                  thumbColor={notificationSettings.alerts ? '#0A84FF' : '#FFFFFF'}
                />
              </View>
            </>
          )}
        </View>

        {/* About Section */}
        <View style={[styles.section, { borderBottomColor: colors.border }]}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>About</StyledText>

          <View style={[styles.settingRow, { borderBottomColor: colors.border }]}>
            <StyledText style={[styles.settingLabel, { color: colors.text }]}>App Version</StyledText>
            <StyledText style={[styles.settingValue, { color: colors.textSecondary }]}>1.0.0</StyledText>
          </View>

          <TouchableOpacity
            style={[styles.settingRow, { borderBottomColor: colors.border }]}
            onPress={() => Alert.alert('Not Implemented', 'Terms will open in browser')}
          >
            <View style={styles.settingLeft}>
              <MaterialCommunityIcons name="file-document" size={20} color={colors.primary} />
              <StyledText style={[styles.settingLabel, { color: colors.text }]}>Terms of Service</StyledText>
            </View>
            <MaterialCommunityIcons name="chevron-right" size={20} color={colors.textTertiary} />
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.settingRow]}
            onPress={() => Alert.alert('Not Implemented', 'Privacy policy will open in browser')}
          >
            <View style={styles.settingLeft}>
              <MaterialCommunityIcons name="shield-lock" size={20} color={colors.primary} />
              <StyledText style={[styles.settingLabel, { color: colors.text }]}>Privacy Policy</StyledText>
            </View>
            <MaterialCommunityIcons name="chevron-right" size={20} color={colors.textTertiary} />
          </TouchableOpacity>
        </View>

        {/* Danger Zone */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Account</StyledText>

          <TouchableOpacity
            style={[styles.settingRow, { borderBottomColor: colors.border }]}
            onPress={handleLogout}
            disabled={loggingOut}
          >
            <View style={styles.settingLeft}>
              {loggingOut ? (
                <ActivityIndicator size={20} color={colors.error} />
              ) : (
                <MaterialCommunityIcons name="logout" size={20} color={colors.error} />
              )}
              <StyledText style={[styles.settingLabel, { color: colors.error }]}>Logout</StyledText>
            </View>
            {!loggingOut && <MaterialCommunityIcons name="chevron-right" size={20} color={colors.textTertiary} />}
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.settingRow]}
            onPress={handleDeleteAccount}
          >
            <View style={styles.settingLeft}>
              <MaterialCommunityIcons name="delete" size={20} color={colors.error} />
              <StyledText style={[styles.settingLabel, { color: colors.error }]}>Delete Account</StyledText>
            </View>
            <MaterialCommunityIcons name="chevron-right" size={20} color={colors.textTertiary} />
          </TouchableOpacity>
        </View>

        <View style={{ height: insets.bottom + 32 }} />
      </ScrollView>

      {/* Font Size Modal */}
      <BottomSheet
        visible={fontSizeModalVisible}
        onClose={() => setFontSizeModalVisible(false)}
        title="Font Size"
      >
        <View style={{ paddingBottom: 16 }}>
          {fontSizes.map((size) => (
            <TouchableOpacity
              key={size.value}
              style={[
                styles.modalOption,
                { backgroundColor: fontSize === size.value ? colors.primaryLight : 'transparent' },
              ]}
              onPress={() => handleFontSizeSelect(size.value)}
            >
              <StyledText
                style={[
                  styles.modalOptionText,
                  {
                    color: fontSize === size.value ? colors.primary : colors.text,
                    fontSize: size.value === 'small' ? 14 : size.value === 'large' ? 18 : 16,
                  },
                ]}
              >
                {size.label}
              </StyledText>
              {fontSize === size.value && (
                <MaterialCommunityIcons name="check" size={20} color={colors.primary} />
              )}
            </TouchableOpacity>
          ))}
        </View>
      </BottomSheet>
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
  section: {
    marginBottom: 24,
    borderBottomWidth: 1,
    paddingBottom: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 12,
  },
  profileCard: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 16,
    borderRadius: 8,
    borderWidth: 1,
    marginBottom: 12,
    justifyContent: 'space-between',
  },
  profileInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  profileName: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 4,
  },
  profileEmail: {
    fontSize: 13,
  },
  settingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  settingLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  settingRight: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  settingLabel: {
    fontSize: 16,
    marginLeft: 12,
    fontWeight: '500',
  },
  settingValue: {
    fontSize: 14,
    marginRight: 8,
  },
  modalOption: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 8,
    marginBottom: 8,
  },
  modalOptionText: {
    fontWeight: '500',
  },
});
