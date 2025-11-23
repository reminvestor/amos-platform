import React, { useState, useEffect } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
  RefreshControl,
  FlatList,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import { FavoriteButton } from '@components/FavoriteButton';
import { copyToClipboard } from '@utils/clipboard';
import { formatShortDate } from '@utils/formatters';
import * as landingPageService from '@services/landing-pages';

interface LandingPageDetailScreenProps {
  navigation: any;
  route: any;
}

interface LandingPageDetail {
  id: string;
  title: string;
  description?: string;
  status: 'draft' | 'published';
  url?: string;
  views: number;
  submissions: number;
  conversion_rate: number;
  created_at: string;
  updated_at: string;
  published_at?: string;
  recent_submissions: Array<{
    id: string;
    name: string;
    email: string;
    submitted_at: string;
  }>;
}

export default function LandingPageDetailScreen({
  navigation,
  route,
}: LandingPageDetailScreenProps) {
  const insets = useSafeAreaInsets();
  const { landingPageId } = route.params;
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const [page, setPage] = useState<LandingPageDetail | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    React.useCallback(() => {
      loadLandingPage();
    }, [landingPageId])
  );

  const loadLandingPage = async () => {
    try {
      setIsLoading(true);
      setError(null);
      const data = await landingPageService.getLandingPageDetail(landingPageId);
      setPage(data as any);
    } catch (err: any) {
      setError(err.message || 'Failed to load landing page');
    } finally {
      setIsLoading(false);
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadLandingPage();
    setIsRefreshing(false);
  };

  const handleDelete = () => {
    Alert.alert(
      'Delete Landing Page',
      `Are you sure you want to delete "${page?.title}"?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          onPress: async () => {
            try {
              await landingPageService.deleteLandingPage(landingPageId);
              Alert.alert('Success', 'Landing page deleted');
              navigation.goBack();
            } catch (err: any) {
              Alert.alert('Error', err.message || 'Failed to delete landing page');
            }
          },
          style: 'destructive',
        },
      ]
    );
  };

  const handleTogglePublish = async () => {
    try {
      const isCurrentlyPublished = page?.status === 'published';
      const action = isCurrentlyPublished ? 'unpublish' : 'publish';

      if (isCurrentlyPublished) {
        await landingPageService.unpublishLandingPage(landingPageId);
      } else {
        await landingPageService.publishLandingPage(landingPageId);
      }

      setPage((prev) =>
        prev
          ? {
              ...prev,
              status: isCurrentlyPublished ? 'draft' : 'published',
            }
          : null
      );

      Alert.alert('Success', `Landing page ${action}ed successfully`);
    } catch (err: any) {
      Alert.alert('Error', err.message || 'Failed to update landing page');
    }
  };

  if (isLoading) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
          <StyledText style={[styles.loadingText, { color: colors.text }]}>
            Loading landing page...
          </StyledText>
        </View>
      </View>
    );
  }

  if (error || !page) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <MaterialCommunityIcons name="alert-circle" size={64} color={colors.error} />
          <StyledText style={[styles.errorTitle, { color: colors.text }]}>
            Failed to Load Landing Page
          </StyledText>
          <StyledText style={[styles.errorMessage, { color: colors.textSecondary }]}>
            {error}
          </StyledText>
          <TouchableOpacity
            style={[styles.retryButton, { backgroundColor: colors.primary }]}
            onPress={loadLandingPage}
          >
            <StyledText style={styles.retryButtonText}>Try Again</StyledText>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  const statusColor = page.status === 'published' ? colors.success : colors.warning;

  const renderSubmission = ({ item }: { item: any }) => (
    <View style={[styles.submissionItem, { borderBottomColor: colors.border }]}>
      <View style={styles.submissionContent}>
        <StyledText style={[styles.submissionName, { color: colors.text }]}>
          {item.name}
        </StyledText>
        <TouchableOpacity onPress={() => copyToClipboard(item.email, 'Email')}>
          <StyledText style={[styles.submissionEmail, { color: colors.textSecondary }]}>
            {item.email}
          </StyledText>
        </TouchableOpacity>
      </View>
      <StyledText style={[styles.submissionTime, { color: colors.textTertiary }]}>
        {formatShortDate(item.submitted_at)}
      </StyledText>
    </View>
  );

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
        {/* Header */}
        <View style={[styles.header, { paddingTop: insets.top }]}>
          <TouchableOpacity onPress={() => navigation.goBack()}>
            <MaterialCommunityIcons name="arrow-left" size={24} color={colors.primary} />
          </TouchableOpacity>
          <View style={styles.headerActions}>
            <FavoriteButton id={landingPageId} type="campaign" size={20} />
            <TouchableOpacity onPress={handleDelete}>
              <MaterialCommunityIcons name="delete" size={20} color={colors.error} />
            </TouchableOpacity>
          </View>
        </View>

        {/* Page Info Card */}
        <View style={[styles.pageCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
          <View style={styles.pageHeader}>
            <View style={styles.pageInfo}>
              <StyledText style={[styles.pageTitle, { color: colors.text }]}>
                {page.title}
              </StyledText>
              <View
                style={[
                  styles.statusBadge,
                  { backgroundColor: statusColor },
                ]}
              >
                <StyledText style={styles.statusText}>
                  {page.status === 'published' ? 'Published' : 'Draft'}
                </StyledText>
              </View>
            </View>
            <TouchableOpacity
              style={[
                styles.publishButton,
                { backgroundColor: statusColor },
              ]}
              onPress={handleTogglePublish}
            >
              <MaterialCommunityIcons
                name={page.status === 'published' ? 'cloud-check' : 'cloud-upload'}
                size={18}
                color="#fff"
              />
              <StyledText style={styles.publishButtonText}>
                {page.status === 'published' ? 'Unpublish' : 'Publish'}
              </StyledText>
            </TouchableOpacity>
          </View>

          {page.description && (
            <StyledText style={[styles.pageDescription, { color: colors.textSecondary }]}>
              {page.description}
            </StyledText>
          )}

          {page.url && (
            <TouchableOpacity
              style={styles.urlContainer}
              onPress={() => copyToClipboard(page.url!, 'URL')}
            >
              <MaterialCommunityIcons name="link" size={14} color={colors.primary} />
              <StyledText style={[styles.pageUrl, { color: colors.primary }]}>
                {page.url}
              </StyledText>
            </TouchableOpacity>
          )}
        </View>

        {/* Metrics */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Performance</StyledText>

          <View style={styles.metricsGrid}>
            <View style={[styles.metricCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
              <MaterialCommunityIcons name="eye" size={24} color={colors.primary} />
              <StyledText style={[styles.metricValue, { color: colors.text }]}>
                {page.views}
              </StyledText>
              <StyledText style={[styles.metricLabel, { color: colors.textSecondary }]}>
                Views
              </StyledText>
            </View>

            <View style={[styles.metricCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
              <MaterialCommunityIcons name="form-textarea" size={24} color={colors.success} />
              <StyledText style={[styles.metricValue, { color: colors.text }]}>
                {page.submissions}
              </StyledText>
              <StyledText style={[styles.metricLabel, { color: colors.textSecondary }]}>
                Submissions
              </StyledText>
            </View>

            <View style={[styles.metricCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
              <MaterialCommunityIcons name="percent" size={24} color={colors.info} />
              <StyledText style={[styles.metricValue, { color: colors.text }]}>
                {(page.conversion_rate * 100).toFixed(1)}%
              </StyledText>
              <StyledText style={[styles.metricLabel, { color: colors.textSecondary }]}>
                Conversion
              </StyledText>
            </View>
          </View>
        </View>

        {/* Page Details */}
        <View style={styles.section}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>Details</StyledText>

          <View style={[styles.detailRow, { borderBottomColor: colors.border }]}>
            <MaterialCommunityIcons name="calendar" size={18} color={colors.primary} />
            <View style={styles.detailContent}>
              <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
                Created
              </StyledText>
              <StyledText style={[styles.detailValue, { color: colors.text }]}>
                {formatShortDate(page.created_at)}
              </StyledText>
            </View>
          </View>

          {page.published_at && (
            <View style={[styles.detailRow, { borderBottomColor: colors.border }]}>
              <MaterialCommunityIcons name="cloud-check" size={18} color={colors.success} />
              <View style={styles.detailContent}>
                <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
                  Published
                </StyledText>
                <StyledText style={[styles.detailValue, { color: colors.text }]}>
                  {formatShortDate(page.published_at)}
                </StyledText>
              </View>
            </View>
          )}

          <View style={styles.detailRow}>
            <MaterialCommunityIcons name="pencil" size={18} color={colors.primary} />
            <View style={styles.detailContent}>
              <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
                Last Updated
              </StyledText>
              <StyledText style={[styles.detailValue, { color: colors.text }]}>
                {formatShortDate(page.updated_at)}
              </StyledText>
            </View>
          </View>
        </View>

        {/* Recent Submissions */}
        {page.recent_submissions && page.recent_submissions.length > 0 && (
          <View style={styles.section}>
            <StyledText style={[styles.sectionTitle, { color: colors.text }]}>
              Recent Submissions
            </StyledText>

            <FlatList
              data={page.recent_submissions}
              renderItem={renderSubmission}
              keyExtractor={(item) => item.id}
              scrollEnabled={false}
              nestedScrollEnabled={false}
            />
          </View>
        )}

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
  pageCard: {
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderRadius: 12,
    borderWidth: 1,
    marginBottom: 24,
  },
  pageHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 12,
  },
  pageInfo: {
    flex: 1,
  },
  pageTitle: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 8,
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
  publishButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 6,
    gap: 6,
  },
  publishButtonText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
  pageDescription: {
    fontSize: 14,
    lineHeight: 20,
    marginBottom: 12,
  },
  urlContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  pageUrl: {
    fontSize: 12,
    textDecorationLine: 'underline',
    flex: 1,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 12,
  },
  metricsGrid: {
    flexDirection: 'row',
    gap: 12,
  },
  metricCard: {
    flex: 1,
    paddingHorizontal: 12,
    paddingVertical: 16,
    borderRadius: 8,
    borderWidth: 1,
    alignItems: 'center',
  },
  metricValue: {
    fontSize: 20,
    fontWeight: '700',
    marginTop: 8,
    marginBottom: 4,
  },
  metricLabel: {
    fontSize: 12,
    textAlign: 'center',
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
  submissionItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  submissionContent: {
    flex: 1,
  },
  submissionName: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 2,
  },
  submissionEmail: {
    fontSize: 12,
  },
  submissionTime: {
    fontSize: 12,
    marginLeft: 8,
  },
});
