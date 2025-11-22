import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  SafeAreaView,
  ActivityIndicator,
  Alert,
  FlatList,
  Modal,
  RefreshControl,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAppDispatch, useAppSelector } from '@store';
import { fetchCampaignDetail } from '@store/slices/campaignsSlice';
import { Campaign } from '@types';
import { formatShortDate, formatPercentage, formatContactCount, formatCurrency } from '@utils/formatters';
import * as campaignService from '@services/campaigns';

interface CampaignDetailScreenProps {
  navigation: any;
  route: any;
}

export default function CampaignDetailScreen({ navigation, route }: CampaignDetailScreenProps) {
  const { campaignId } = route.params;
  const dispatch = useAppDispatch();
  const campaign = useAppSelector((state) => state.campaigns.current);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [analytics, setAnalytics] = useState<any>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isActionMenuVisible, setIsActionMenuVisible] = useState(false);

  useFocusEffect(
    useCallback(() => {
      loadCampaignDetail();
    }, [campaignId])
  );

  const loadCampaignDetail = async () => {
    try {
      setIsLoading(true);
      setError(null);

      // Fetch campaign detail from Redux
      await dispatch(fetchCampaignDetail(campaignId));

      // Fetch analytics separately
      try {
        const analyticsData = await campaignService.getCampaignAnalytics(campaignId);
        setAnalytics(analyticsData);
      } catch (err) {
        console.warn('Failed to fetch analytics:', err);
      }
    } catch (err: any) {
      setError(err.message || 'Failed to load campaign');
      console.error('Error loading campaign detail:', err);
    } finally {
      setIsLoading(false);
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadCampaignDetail();
    setIsRefreshing(false);
  };

  const handleEdit = () => {
    setIsActionMenuVisible(false);
    Alert.alert('Edit Campaign', 'Navigate to edit campaign screen (coming soon)');
  };

  const handleDuplicate = () => {
    setIsActionMenuVisible(false);
    Alert.alert(
      'Duplicate Campaign',
      'Are you sure you want to duplicate this campaign?',
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: 'Duplicate',
          onPress: async () => {
            try {
              await campaignService.duplicateCampaign(campaignId);
              Alert.alert('Success', 'Campaign duplicated successfully');
              navigation.goBack();
            } catch (err: any) {
              Alert.alert('Error', err.message || 'Failed to duplicate campaign');
            }
          },
        },
      ]
    );
  };

  const handleArchive = () => {
    setIsActionMenuVisible(false);
    Alert.alert(
      'Archive Campaign',
      'Are you sure you want to archive this campaign?',
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: 'Archive',
          onPress: async () => {
            try {
              await campaignService.updateCampaign(campaignId, { status: 'archived' });
              Alert.alert('Success', 'Campaign archived');
              navigation.goBack();
            } catch (err: any) {
              Alert.alert('Error', err.message || 'Failed to archive campaign');
            }
          },
          style: 'destructive',
        },
      ]
    );
  };

  const handleTestSend = () => {
    setIsActionMenuVisible(false);
    Alert.prompt(
      'Test Send',
      'Enter email address to send test email:',
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: 'Send',
          onPress: async (email) => {
            if (!email) return;
            try {
              await campaignService.testSendCampaign(campaignId, email);
              Alert.alert('Success', 'Test email sent');
            } catch (err: any) {
              Alert.alert('Error', err.message || 'Failed to send test email');
            }
          },
        },
      ]
    );
  };

  if (isLoading) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color="#4A90E2" />
          <Text style={styles.loadingText}>Loading campaign details...</Text>
        </View>
      </SafeAreaView>
    );
  }

  if (!campaign || error) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.centerContainer}>
          <MaterialCommunityIcons name="alert-circle" size={64} color="#c33" />
          <Text style={styles.errorTitle}>{error || 'Campaign not found'}</Text>
          <TouchableOpacity
            style={styles.retryButton}
            onPress={loadCampaignDetail}
          >
            <Text style={styles.retryButtonText}>Try Again</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  const openRate = campaign.open_rate ? formatPercentage(campaign.open_rate) : 'N/A';
  const clickRate = campaign.click_rate ? formatPercentage(campaign.click_rate) : 'N/A';
  const conversionRate = analytics?.conversion_rate ? formatPercentage(analytics.conversion_rate) : 'N/A';

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView
        contentContainerStyle={styles.scrollContent}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={handleRefresh}
            tintColor="#4A90E2"
          />
        }
      >
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity
            style={styles.backButton}
            onPress={() => navigation.goBack()}
          >
            <MaterialCommunityIcons name="chevron-left" size={24} color="#333" />
          </TouchableOpacity>
          <View style={styles.headerContent}>
            <Text style={styles.campaignName} numberOfLines={2}>
              {campaign.name}
            </Text>
            <View style={[styles.statusBadge, { backgroundColor: getStatusColor(campaign.status) }]}>
              <Text style={styles.statusText}>{formatStatus(campaign.status)}</Text>
            </View>
          </View>
          <TouchableOpacity
            style={styles.menuButton}
            onPress={() => setIsActionMenuVisible(true)}
          >
            <MaterialCommunityIcons name="dots-vertical" size={24} color="#333" />
          </TouchableOpacity>
        </View>

        {/* Campaign Info */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Campaign Information</Text>
          <View style={styles.infoGrid}>
            <InfoCard
              icon="calendar"
              label="Created"
              value={formatShortDate(campaign.created_at)}
            />
            <InfoCard
              icon="account-multiple"
              label="Recipients"
              value={formatContactCount(campaign.contact_count || 0)}
            />
            <InfoCard
              icon="clock-outline"
              label="Scheduled"
              value={campaign.scheduled_at ? formatShortDate(campaign.scheduled_at) : 'Not scheduled'}
            />
            <InfoCard
              icon="send"
              label="Sent"
              value={analytics?.sent_count ? formatContactCount(analytics.sent_count) : '0'}
            />
          </View>
        </View>

        {/* Performance Metrics */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Performance Metrics</Text>
          <View style={styles.metricsGrid}>
            <MetricCard
              label="Open Rate"
              value={openRate}
              icon="email-open"
              color="#4A90E2"
            />
            <MetricCard
              label="Click Rate"
              value={clickRate}
              icon="cursor-default-click"
              color="#27AE60"
            />
            <MetricCard
              label="Conversion Rate"
              value={conversionRate}
              icon="trending-up"
              color="#F5A623"
            />
            <MetricCard
              label="Bounce Rate"
              value={analytics?.bounce_rate ? formatPercentage(analytics.bounce_rate) : 'N/A'}
              icon="alert-circle"
              color="#E74C3C"
            />
          </View>
        </View>

        {/* Subject Line */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Subject Line</Text>
          <View style={styles.subjectBox}>
            <Text style={styles.subjectText}>{campaign.subject}</Text>
          </View>
        </View>

        {/* From Details */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>From Details</Text>
          <DetailRow label="From Name" value={campaign.from_name || 'Not set'} />
          <DetailRow label="From Email" value={campaign.from_email || 'Not set'} />
          <DetailRow label="Reply-To" value={campaign.reply_to_email || 'Not set'} />
        </View>

        {/* Statistics */}
        {analytics && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Detailed Statistics</Text>
            <DetailRow
              label="Total Sent"
              value={formatContactCount(analytics.sent_count || 0)}
            />
            <DetailRow
              label="Opens"
              value={`${formatContactCount(analytics.opens || 0)} (${formatPercentage(campaign.open_rate || 0)})`}
            />
            <DetailRow
              label="Clicks"
              value={`${formatContactCount(analytics.clicks || 0)} (${formatPercentage(campaign.click_rate || 0)})`}
            />
            <DetailRow
              label="Bounces"
              value={`${formatContactCount(analytics.bounces || 0)} (${formatPercentage(analytics.bounce_rate || 0)})`}
            />
            <DetailRow
              label="Unsubscribes"
              value={formatContactCount(analytics.unsubscribes || 0)}
            />
            <DetailRow
              label="Complaints"
              value={formatContactCount(analytics.complaints || 0)}
            />
          </View>
        )}

        {/* Action Buttons */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Quick Actions</Text>
          <ActionButton
            icon="pencil"
            label="Edit Campaign"
            onPress={handleEdit}
            variant="primary"
          />
          <ActionButton
            icon="content-duplicate"
            label="Duplicate Campaign"
            onPress={handleDuplicate}
            variant="secondary"
          />
          <ActionButton
            icon="email-send"
            label="Send Test Email"
            onPress={handleTestSend}
            variant="secondary"
          />
          <ActionButton
            icon="archive"
            label="Archive Campaign"
            onPress={handleArchive}
            variant="danger"
          />
        </View>
      </ScrollView>

      {/* Action Menu Modal */}
      <Modal
        visible={isActionMenuVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setIsActionMenuVisible(false)}
      >
        <TouchableOpacity
          style={styles.modalOverlay}
          activeOpacity={1}
          onPress={() => setIsActionMenuVisible(false)}
        >
          <View style={styles.menuContainer}>
            <TouchableOpacity
              style={styles.menuItem}
              onPress={handleEdit}
            >
              <MaterialCommunityIcons name="pencil" size={20} color="#4A90E2" />
              <Text style={styles.menuItemText}>Edit Campaign</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.menuItem}
              onPress={handleDuplicate}
            >
              <MaterialCommunityIcons name="content-duplicate" size={20} color="#27AE60" />
              <Text style={styles.menuItemText}>Duplicate Campaign</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.menuItem}
              onPress={handleTestSend}
            >
              <MaterialCommunityIcons name="email-send" size={20} color="#F5A623" />
              <Text style={styles.menuItemText}>Send Test Email</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.menuItem, styles.menuItemDanger]}
              onPress={handleArchive}
            >
              <MaterialCommunityIcons name="trash-can" size={20} color="#E74C3C" />
              <Text style={[styles.menuItemText, styles.menuItemTextDanger]}>
                Delete Campaign
              </Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.menuItem}
              onPress={() => setIsActionMenuVisible(false)}
            >
              <Text style={styles.menuItemCancel}>Cancel</Text>
            </TouchableOpacity>
          </View>
        </TouchableOpacity>
      </Modal>
    </SafeAreaView>
  );
}

// Helper Components
const InfoCard = ({ icon, label, value }: { icon: string; label: string; value: string }) => (
  <View style={styles.infoCard}>
    <MaterialCommunityIcons name={icon} size={24} color="#4A90E2" />
    <Text style={styles.infoLabel}>{label}</Text>
    <Text style={styles.infoValue} numberOfLines={2}>
      {value}
    </Text>
  </View>
);

const MetricCard = ({
  label,
  value,
  icon,
  color,
}: {
  label: string;
  value: string;
  icon: string;
  color: string;
}) => (
  <View style={styles.metricCard}>
    <View style={[styles.metricIconContainer, { backgroundColor: color + '20' }]}>
      <MaterialCommunityIcons name={icon} size={24} color={color} />
    </View>
    <Text style={styles.metricLabel}>{label}</Text>
    <Text style={[styles.metricValue, { color }]}>{value}</Text>
  </View>
);

const DetailRow = ({ label, value }: { label: string; value: string }) => (
  <View style={styles.detailRow}>
    <Text style={styles.detailLabel}>{label}</Text>
    <Text style={styles.detailValue}>{value}</Text>
  </View>
);

const ActionButton = ({
  icon,
  label,
  onPress,
  variant = 'primary',
}: {
  icon: string;
  label: string;
  onPress: () => void;
  variant?: 'primary' | 'secondary' | 'danger';
}) => (
  <TouchableOpacity
    style={[
      styles.actionButton,
      variant === 'primary' && styles.actionButtonPrimary,
      variant === 'secondary' && styles.actionButtonSecondary,
      variant === 'danger' && styles.actionButtonDanger,
    ]}
    onPress={onPress}
  >
    <MaterialCommunityIcons
      name={icon}
      size={18}
      color={variant === 'secondary' ? '#4A90E2' : '#fff'}
    />
    <Text
      style={[
        styles.actionButtonText,
        variant === 'secondary' && styles.actionButtonTextSecondary,
      ]}
    >
      {label}
    </Text>
  </TouchableOpacity>
);

// Helper Functions
function getStatusColor(status: string): string {
  const colors: Record<string, string> = {
    draft: '#95A5A6',
    scheduled: '#3498DB',
    in_progress: '#27AE60',
    completed: '#2ECC71',
    paused: '#F39C12',
    stopped: '#E74C3C',
  };
  return colors[status] || '#95A5A6';
}

function formatStatus(status: string): string {
  return status.charAt(0).toUpperCase() + status.slice(1).replace('_', ' ');
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f9f9f9',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  loadingText: {
    marginTop: 12,
    fontSize: 14,
    color: '#666',
  },
  errorTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginTop: 12,
    textAlign: 'center',
  },
  retryButton: {
    marginTop: 20,
    paddingHorizontal: 24,
    paddingVertical: 12,
    backgroundColor: '#4A90E2',
    borderRadius: 8,
  },
  retryButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  scrollContent: {
    paddingHorizontal: 16,
    paddingBottom: 24,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  backButton: {
    padding: 8,
    marginRight: 8,
  },
  headerContent: {
    flex: 1,
  },
  campaignName: {
    fontSize: 18,
    fontWeight: '700',
    color: '#333',
    marginBottom: 6,
  },
  statusBadge: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
    alignSelf: 'flex-start',
  },
  statusText: {
    fontSize: 11,
    fontWeight: '600',
    color: '#fff',
  },
  menuButton: {
    padding: 8,
    marginLeft: 8,
  },
  section: {
    marginTop: 24,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '700',
    color: '#333',
    marginBottom: 12,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  infoGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginHorizontal: -8,
  },
  infoCard: {
    width: '50%',
    paddingHorizontal: 8,
    marginBottom: 16,
  },
  infoCardContent: {
    backgroundColor: '#fff',
    padding: 12,
    borderRadius: 8,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#eee',
  },
  infoLabel: {
    fontSize: 11,
    color: '#999',
    marginTop: 8,
    textTransform: 'uppercase',
    letterSpacing: 0.3,
  },
  infoValue: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
    marginTop: 4,
    textAlign: 'center',
  },
  metricsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginHorizontal: -8,
  },
  metricCard: {
    width: '50%',
    paddingHorizontal: 8,
    marginBottom: 16,
  },
  metricCardContent: {
    backgroundColor: '#fff',
    padding: 12,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#eee',
  },
  metricIconContainer: {
    width: 48,
    height: 48,
    borderRadius: 8,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  metricLabel: {
    fontSize: 12,
    color: '#999',
    marginBottom: 4,
  },
  metricValue: {
    fontSize: 18,
    fontWeight: '700',
  },
  subjectBox: {
    backgroundColor: '#fff',
    padding: 12,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#eee',
  },
  subjectText: {
    fontSize: 14,
    color: '#333',
    lineHeight: 20,
  },
  detailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  detailLabel: {
    fontSize: 13,
    color: '#666',
    flex: 1,
  },
  detailValue: {
    fontSize: 13,
    color: '#333',
    fontWeight: '600',
    flex: 1,
    textAlign: 'right',
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 8,
    marginBottom: 10,
  },
  actionButtonPrimary: {
    backgroundColor: '#4A90E2',
  },
  actionButtonSecondary: {
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#4A90E2',
  },
  actionButtonDanger: {
    backgroundColor: '#E74C3C',
  },
  actionButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#fff',
    marginLeft: 8,
  },
  actionButtonTextSecondary: {
    color: '#4A90E2',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  menuContainer: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    paddingBottom: 24,
    paddingTop: 12,
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  menuItemDanger: {
    backgroundColor: '#fee',
  },
  menuItemText: {
    fontSize: 14,
    color: '#333',
    marginLeft: 12,
    fontWeight: '500',
  },
  menuItemTextDanger: {
    color: '#E74C3C',
  },
  menuItemCancel: {
    fontSize: 14,
    color: '#999',
    fontWeight: '600',
    textAlign: 'center',
  },
});
