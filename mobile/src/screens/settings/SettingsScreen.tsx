import React, { useState } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  Alert,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { List, Switch, Button, ActivityIndicator, Avatar, Divider, RadioButton } from 'react-native-paper';
import { ChevronRight, Lock, Moon, Sun, ALargeSmall, Bell, Mail, FormInput, AlertCircle, FileText, ShieldCheck, LogOut } from 'lucide-react-native';
import { useAppDispatch, useAppSelector } from '@store';
import { setTheme, setFontSize, updateNotificationSettings } from '@store/slices/uiSlice';
import { logoutUser } from '@store/slices/authSlice';
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
  const { user } = useAppSelector((state) => state.auth);
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
            await dispatch(logoutUser()).unwrap();
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
        <List.Section>
          <List.Subheader style={[styles.sectionTitle, { color: colors.text }]}>Profile</List.Subheader>

          <List.Item
            title={user?.name || 'User'}
            description={user?.email}
            titleStyle={[styles.profileName, { color: colors.text }]}
            descriptionStyle={{ color: colors.textSecondary }}
            left={() => (
              <Avatar.Text
                size={48}
                label={user?.name?.charAt(0).toUpperCase() || 'U'}
                style={{ backgroundColor: colors.primary }}
              />
            )}
            right={() => <ChevronRight size={20} color={colors.textTertiary} style={styles.iconRight} />}
            onPress={() => Alert.alert('Not Implemented', 'Profile editing coming soon')}
            style={[styles.listItem, { backgroundColor: colors.surface }]}
          />

          <List.Item
            title="Change Password"
            titleStyle={{ color: colors.text }}
            left={() => <Lock size={24} color={colors.primary} style={styles.iconLeft} />}
            right={() => <ChevronRight size={20} color={colors.textTertiary} style={styles.iconRight} />}
            onPress={() => Alert.alert('Not Implemented', 'Password change coming soon')}
            style={styles.listItem}
          />
        </List.Section>

        <Divider style={{ backgroundColor: colors.border }} />

        {/* Appearance Section */}
        <List.Section>
          <List.Subheader style={[styles.sectionTitle, { color: colors.text }]}>Appearance</List.Subheader>

          <List.Item
            title="Dark Mode"
            titleStyle={{ color: colors.text }}
            left={() => (
              theme === 'dark' ? <Moon size={24} color={colors.primary} style={styles.iconLeft} /> : <Sun size={24} color={colors.primary} style={styles.iconLeft} />
            )}
            right={() => (
              <Switch
                value={theme === 'dark'}
                onValueChange={handleThemeToggle}
                color={colors.primary}
              />
            )}
            style={styles.listItem}
          />

          <List.Item
            title="Font Size"
            description={fontSize.charAt(0).toUpperCase() + fontSize.slice(1)}
            titleStyle={{ color: colors.text }}
            descriptionStyle={{ color: colors.textSecondary }}
            left={() => <ALargeSmall size={24} color={colors.primary} style={styles.iconLeft} />}
            right={() => <ChevronRight size={20} color={colors.textTertiary} style={styles.iconRight} />}
            onPress={() => setFontSizeModalVisible(true)}
            style={styles.listItem}
          />
        </List.Section>

        <Divider style={{ backgroundColor: colors.border }} />

        {/* Notifications Section */}
        <List.Section>
          <List.Subheader style={[styles.sectionTitle, { color: colors.text }]}>Notifications</List.Subheader>

          <List.Item
            title="All Notifications"
            titleStyle={{ color: colors.text }}
            left={() => <Bell size={24} color={colors.primary} style={styles.iconLeft} />}
            right={() => (
              <Switch
                value={notificationSettings.general}
                onValueChange={(value) => handleNotificationToggle('general', value)}
                color={colors.primary}
              />
            )}
            style={styles.listItem}
          />

          {notificationSettings.general && (
            <>
              <List.Item
                title="Campaign Status"
                titleStyle={{ color: colors.text }}
                left={() => <Mail size={24} color={colors.info} style={styles.iconLeft} />}
                right={() => (
                  <Switch
                    value={notificationSettings.campaignStatus}
                    onValueChange={(value) => handleNotificationToggle('campaignStatus', value)}
                    color={colors.primary}
                  />
                )}
                style={styles.listItem}
              />

              <List.Item
                title="Form Submissions"
                titleStyle={{ color: colors.text }}
                left={() => <FormInput size={24} color={colors.success} style={styles.iconLeft} />}
                right={() => (
                  <Switch
                    value={notificationSettings.formSubmissions}
                    onValueChange={(value) => handleNotificationToggle('formSubmissions', value)}
                    color={colors.primary}
                  />
                )}
                style={styles.listItem}
              />

              <List.Item
                title="Alerts"
                titleStyle={{ color: colors.text }}
                left={() => <AlertCircle size={24} color={colors.warning} style={styles.iconLeft} />}
                right={() => (
                  <Switch
                    value={notificationSettings.alerts}
                    onValueChange={(value) => handleNotificationToggle('alerts', value)}
                    color={colors.primary}
                  />
                )}
                style={styles.listItem}
              />
            </>
          )}
        </List.Section>

        <Divider style={{ backgroundColor: colors.border }} />

        {/* About Section */}
        <List.Section>
          <List.Subheader style={[styles.sectionTitle, { color: colors.text }]}>About</List.Subheader>

          <List.Item
            title="App Version"
            titleStyle={{ color: colors.text }}
            right={() => <StyledText style={{ color: colors.textSecondary }}>1.0.0</StyledText>}
            style={styles.listItem}
          />

          <List.Item
            title="Terms of Service"
            titleStyle={{ color: colors.text }}
            left={() => <FileText size={24} color={colors.primary} style={styles.iconLeft} />}
            right={() => <ChevronRight size={20} color={colors.textTertiary} style={styles.iconRight} />}
            onPress={() => navigation.navigate('Terms')}
            style={styles.listItem}
          />

          <List.Item
            title="Privacy Policy"
            titleStyle={{ color: colors.text }}
            left={() => <ShieldCheck size={24} color={colors.primary} style={styles.iconLeft} />}
            right={() => <ChevronRight size={20} color={colors.textTertiary} style={styles.iconRight} />}
            onPress={() => navigation.navigate('Privacy')}
            style={styles.listItem}
          />
        </List.Section>

        <Divider style={{ backgroundColor: colors.border }} />

        {/* Account Section */}
        <List.Section>
          <List.Subheader style={[styles.sectionTitle, { color: colors.text }]}>Account</List.Subheader>

          <List.Item
            title="Logout"
            titleStyle={{ color: colors.error }}
            left={() =>
              loggingOut ? (
                <ActivityIndicator size={20} color={colors.error} style={{ marginLeft: 8 }} />
              ) : (
                <LogOut size={24} color={colors.error} style={styles.iconLeft} />
              )
            }
            right={() => !loggingOut && <ChevronRight size={20} color={colors.textTertiary} style={styles.iconRight} />}
            onPress={handleLogout}
            disabled={loggingOut}
            style={styles.listItem}
          />
        </List.Section>

        <View style={{ height: insets.bottom + 32 }} />
      </ScrollView>

      {/* Font Size Modal */}
      <BottomSheet
        visible={fontSizeModalVisible}
        onClose={() => setFontSizeModalVisible(false)}
        title="Font Size"
      >
        <RadioButton.Group onValueChange={(value) => handleFontSizeSelect(value as 'small' | 'medium' | 'large')} value={fontSize}>
          {fontSizes.map((size) => (
            <RadioButton.Item
              key={size.value}
              label={size.label}
              value={size.value}
              labelStyle={[
                styles.radioLabel,
                { color: colors.text, fontSize: size.value === 'small' ? 14 : size.value === 'large' ? 18 : 16 }
              ]}
              color={colors.primary}
              style={[
                styles.radioItem,
                fontSize === size.value && { backgroundColor: colors.primaryLight }
              ]}
            />
          ))}
        </RadioButton.Group>
      </BottomSheet>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    paddingHorizontal: 8,
    paddingBottom: 32,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
  },
  profileName: {
    fontSize: 16,
    fontWeight: '600',
  },
  listItem: {
    paddingVertical: 4,
  },
  radioItem: {
    borderRadius: 8,
    marginBottom: 8,
  },
  radioLabel: {
    fontWeight: '500',
  },
  iconLeft: {
    marginLeft: 8,
    marginRight: 8,
  },
  iconRight: {
    marginRight: 8,
  },
});
