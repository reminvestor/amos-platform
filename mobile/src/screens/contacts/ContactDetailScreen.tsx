import React, { useState, useEffect } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
  RefreshControl,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAppDispatch, useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import { FavoriteButton } from '@components/FavoriteButton';
import { copyToClipboard } from '@utils/clipboard';
import { formatShortDate, formatContactStatus } from '@utils/formatters';
import * as contactService from '@services/contacts';
import { Contact } from '@types';

interface ContactDetailScreenProps {
  navigation: any;
  route: any;
}

export default function ContactDetailScreen({ navigation, route }: ContactDetailScreenProps) {
  const insets = useSafeAreaInsets();
  const { contactId } = route.params;
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const [contact, setContact] = useState<Contact | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    React.useCallback(() => {
      loadContact();
    }, [contactId])
  );

  const loadContact = async () => {
    try {
      setIsLoading(true);
      setError(null);
      const data = await contactService.getContact(contactId);
      setContact(data);
    } catch (err: any) {
      setError(err.message || 'Failed to load contact');
    } finally {
      setIsLoading(false);
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadContact();
    setIsRefreshing(false);
  };

  const handleDelete = () => {
    Alert.alert(
      'Delete Contact',
      `Are you sure you want to delete ${contact?.name || 'this contact'}?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          onPress: async () => {
            try {
              await contactService.deleteContact(contactId);
              Alert.alert('Success', 'Contact deleted');
              navigation.goBack();
            } catch (err: any) {
              Alert.alert('Error', err.message || 'Failed to delete contact');
            }
          },
          style: 'destructive',
        },
      ]
    );
  };

  const handleUpdateStatus = async (newStatus: string) => {
    try {
      await contactService.updateContact(contactId, { status: newStatus });
      setContact((prev) => (prev ? { ...prev, status: newStatus } : null));
      Alert.alert('Success', 'Contact status updated');
    } catch (err: any) {
      Alert.alert('Error', err.message || 'Failed to update status');
    }
  };

  if (isLoading) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
          <StyledText style={[styles.loadingText, { color: colors.text }]}>
            Loading contact...
          </StyledText>
        </View>
      </View>
    );
  }

  if (error || !contact) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <MaterialCommunityIcons name="alert-circle" size={64} color={colors.error} />
          <StyledText style={[styles.errorTitle, { color: colors.text }]}>
            Failed to Load Contact
          </StyledText>
          <StyledText style={[styles.errorMessage, { color: colors.textSecondary }]}>
            {error}
          </StyledText>
          <TouchableOpacity
            style={[styles.retryButton, { backgroundColor: colors.primary }]}
            onPress={loadContact}
          >
            <StyledText style={styles.retryButtonText}>Try Again</StyledText>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  const statusInfo = formatContactStatus(contact.status);

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={handleRefresh}
            tintColor={colors.primary}
          />
        }
      >
        {/* Header with back button */}
        <View style={[styles.header, { paddingTop: insets.top }]}>
          <TouchableOpacity onPress={() => navigation.goBack()}>
            <MaterialCommunityIcons name="arrow-left" size={24} color={colors.primary} />
          </TouchableOpacity>
          <View style={styles.headerActions}>
            <FavoriteButton id={contactId} type="contact" size={20} />
            <TouchableOpacity onPress={handleDelete}>
              <MaterialCommunityIcons name="delete" size={20} color={colors.error} />
            </TouchableOpacity>
          </View>
        </View>

        {/* Contact Info Card */}
        <View style={[styles.profileCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
          <View style={[styles.avatar, { backgroundColor: colors.primary }]}>
            <StyledText style={styles.avatarText}>
              {(contact.name || contact.email).charAt(0).toUpperCase()}
            </StyledText>
          </View>

          <View style={styles.profileInfo}>
            <StyledText style={[styles.name, { color: colors.text }]}>
              {contact.name || 'Unknown'}
            </StyledText>
            <TouchableOpacity
              style={styles.emailRow}
              onPress={() => copyToClipboard(contact.email, 'Email')}
            >
              <StyledText style={[styles.email, { color: colors.textSecondary }]}>
                {contact.email}
              </StyledText>
              <MaterialCommunityIcons name="content-copy" size={14} color={colors.primary} />
            </TouchableOpacity>
            <View
              style={[
                styles.statusBadge,
                { backgroundColor: statusInfo.color },
              ]}
            >
              <StyledText style={styles.statusText}>{statusInfo.label}</StyledText>
            </View>
          </View>
        </View>

        {/* Contact Details */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Contact Information</StyledText>

          {contact.phone && (
            <View style={[styles.detailRow, { borderBottomColor: colors.border }]}>
              <MaterialCommunityIcons name="phone" size={18} color={colors.primary} />
              <TouchableOpacity
                style={styles.detailContent}
                onPress={() => copyToClipboard(contact.phone!, 'Phone')}
              >
                <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
                  Phone
                </StyledText>
                <StyledText style={[styles.detailValue, { color: colors.text }]}>
                  {contact.phone}
                </StyledText>
              </TouchableOpacity>
            </View>
          )}

          <View style={[styles.detailRow, { borderBottomColor: colors.border }]}>
            <MaterialCommunityIcons name="calendar" size={18} color={colors.primary} />
            <View style={styles.detailContent}>
              <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
                Added Date
              </StyledText>
              <StyledText style={[styles.detailValue, { color: colors.text }]}>
                {formatShortDate(contact.created_at)}
              </StyledText>
            </View>
          </View>

          {contact.last_engaged_at && (
            <View style={[styles.detailRow, { borderBottomColor: colors.border }]}>
              <MaterialCommunityIcons name="clock" size={18} color={colors.primary} />
              <View style={styles.detailContent}>
                <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
                  Last Engaged
                </StyledText>
                <StyledText style={[styles.detailValue, { color: colors.text }]}>
                  {formatShortDate(contact.last_engaged_at)}
                </StyledText>
              </View>
            </View>
          )}

          {contact.bounce_status && (
            <View style={styles.detailRow}>
              <MaterialCommunityIcons name="alert" size={18} color={colors.warning} />
              <View style={styles.detailContent}>
                <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
                  Bounce Status
                </StyledText>
                <StyledText style={[styles.detailValue, { color: colors.text }]}>
                  {contact.bounce_status}
                </StyledText>
              </View>
            </View>
          )}
        </View>

        {/* Tags */}
        {contact.tags && contact.tags.length > 0 && (
          <View style={styles.section}>
            <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Tags</StyledText>
            <View style={styles.tagsContainer}>
              {contact.tags.map((tag, index) => (
                <View
                  key={index}
                  style={[
                    styles.tag,
                    { backgroundColor: colors.primaryLight, borderColor: colors.primary },
                  ]}
                >
                  <StyledText style={[styles.tagText, { color: colors.primary }]}>
                    {tag}
                  </StyledText>
                </View>
              ))}
            </View>
          </View>
        )}

        {/* Status Management */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Status</StyledText>

          {['active', 'inactive', 'unsubscribed', 'bounced'].map((status) => (
            <TouchableOpacity
              key={status}
              style={[
                styles.statusOption,
                {
                  backgroundColor: contact.status === status ? colors.primaryLight : colors.surface,
                  borderColor: contact.status === status ? colors.primary : colors.border,
                },
              ]}
              onPress={() => handleUpdateStatus(status)}
            >
              <MaterialCommunityIcons
                name={
                  status === 'active'
                    ? 'check-circle'
                    : status === 'inactive'
                    ? 'pause-circle'
                    : status === 'unsubscribed'
                    ? 'close-circle'
                    : 'alert-circle'
                }
                size={20}
                color={contact.status === status ? colors.primary : colors.textSecondary}
              />
              <StyledText
                style={[
                  styles.statusOptionText,
                  {
                    color: contact.status === status ? colors.primary : colors.text,
                  },
                ]}
              >
                {status.charAt(0).toUpperCase() + status.slice(1)}
              </StyledText>
              {contact.status === status && (
                <MaterialCommunityIcons name="check" size={20} color={colors.primary} />
              )}
            </TouchableOpacity>
          ))}
        </View>

        <View style={{ height: insets.bottom + 32 }} />
      </ScrollView>
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
    paddingHorizontal: 0,
    paddingBottom: 16,
    marginHorizontal: -16,
    marginBottom: 16,
    paddingLeft: 16,
    paddingRight: 16,
  },
  headerActions: {
    flexDirection: 'row',
    gap: 12,
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    marginTop: 12,
    fontSize: 14,
  },
  errorTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginTop: 16,
    marginBottom: 8,
  },
  errorMessage: {
    fontSize: 14,
    textAlign: 'center',
    marginBottom: 24,
  },
  retryButton: {
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
  },
  retryButtonText: {
    color: '#fff',
    fontWeight: '600',
  },
  profileCard: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 20,
    borderRadius: 12,
    borderWidth: 1,
    marginBottom: 24,
  },
  avatar: {
    width: 56,
    height: 56,
    borderRadius: 28,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 16,
  },
  avatarText: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '700',
  },
  profileInfo: {
    flex: 1,
  },
  name: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 4,
  },
  email: {
    fontSize: 13,
    flex: 1,
  },
  emailRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
    gap: 6,
  },
  statusBadge: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  statusText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '600',
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 12,
  },
  detailRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  detailContent: {
    flex: 1,
    marginLeft: 12,
  },
  detailLabel: {
    fontSize: 12,
    marginBottom: 4,
  },
  detailValue: {
    fontSize: 14,
    fontWeight: '500',
  },
  tagsContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  tag: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    borderWidth: 1,
  },
  tagText: {
    fontSize: 12,
    fontWeight: '500',
  },
  statusOption: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderRadius: 8,
    borderWidth: 1,
    marginBottom: 8,
  },
  statusOptionText: {
    flex: 1,
    marginLeft: 12,
    fontSize: 14,
    fontWeight: '500',
  },
});
