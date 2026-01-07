import React, { useState, useCallback } from 'react';
import {
  View,
  Text,
  FlatList,
  StyleSheet,
  SafeAreaView,
  RefreshControl,
  Alert,
} from 'react-native';
import { Card, Searchbar, IconButton, Button, ActivityIndicator, Chip, Portal, Modal } from 'react-native-paper';
import { MotiView } from 'moti';
import { FileText, Eye, Percent, FileQuestion } from 'lucide-react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAppSelector } from '@store';
import { LandingPage } from '@types';
import { formatShortDate, formatPercentage } from '@utils/formatters';
import * as landingPageService from '@services/landing-pages';
import { getColors } from '@theme/colors';

interface LandingPageListScreenProps {
  navigation: any;
}

type StatusFilter = 'draft' | 'published' | undefined;

export default function LandingPageListScreen({ navigation }: LandingPageListScreenProps) {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const [pages, setPages] = useState<LandingPage[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchText, setSearchText] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>(undefined);
  const [isFilterModalVisible, setIsFilterModalVisible] = useState(false);
  const [pagination, setPagination] = useState({
    page: 1,
    perPage: 20,
    total: 0,
    hasNext: false,
  });
  const [isRefreshing, setIsRefreshing] = useState(false);

  useFocusEffect(
    useCallback(() => {
      loadPages();
    }, [])
  );

  const loadPages = async () => {
    try {
      setIsLoading(true);
      setError(null);

      const response = await landingPageService.getLandingPages({
        page: 1,
        perPage: 20,
        status: statusFilter,
      });

      setPages(response.data);
      setPagination({
        page: response.pagination.page,
        perPage: response.pagination.per_page,
        total: response.pagination.total,
        hasNext: response.pagination.page < response.pagination.total_pages,
      });
    } catch (err: any) {
      setError(err.message || 'Failed to load landing pages');
      console.error('Error loading pages:', err);
    } finally {
      setIsLoading(false);
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadPages();
    setIsRefreshing(false);
  };

  const handleLoadMore = async () => {
    if (pagination.hasNext && !isLoading) {
      try {
        const response = await landingPageService.getLandingPages({
          page: pagination.page + 1,
          perPage: 20,
          status: statusFilter,
        });

        setPages([...pages, ...response.data]);
        setPagination({
          page: response.pagination.page,
          perPage: response.pagination.per_page,
          total: response.pagination.total,
          hasNext: response.pagination.page < response.pagination.total_pages,
        });
      } catch (err) {
        console.error('Error loading more pages:', err);
      }
    }
  };

  const handlePagePress = (page: LandingPage) => {
    navigation.navigate('LandingPageDetail', { pageId: page.id });
  };

  const handlePublishToggle = async (page: LandingPage) => {
    const action = page.status === 'published' ? 'unpublish' : 'publish';
    Alert.alert(
      `${action.charAt(0).toUpperCase() + action.slice(1)} Landing Page`,
      `Are you sure you want to ${action} "${page.title}"?`,
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: action.charAt(0).toUpperCase() + action.slice(1),
          onPress: async () => {
            try {
              if (page.status === 'published') {
                await landingPageService.unpublishLandingPage(page.id);
              } else {
                await landingPageService.publishLandingPage(page.id);
              }
              await loadPages();
              Alert.alert('Success', `Landing page ${action}ed successfully`);
            } catch (err: any) {
              Alert.alert('Error', err.message || `Failed to ${action} landing page`);
            }
          },
        },
      ]
    );
  };

  const handleViewSubmissions = async (page: LandingPage) => {
    navigation.navigate('SubmissionsList', { pageId: page.id, pageTitle: page.title });
  };

  const handleDeletePage = (page: LandingPage) => {
    Alert.alert(
      'Delete Landing Page',
      `Are you sure you want to delete "${page.title}"? This action cannot be undone.`,
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: 'Delete',
          onPress: async () => {
            try {
              await landingPageService.deleteLandingPage(page.id);
              await loadPages();
              Alert.alert('Success', 'Landing page deleted successfully');
            } catch (err: any) {
              Alert.alert('Error', err.message || 'Failed to delete landing page');
            }
          },
          style: 'destructive',
        },
      ]
    );
  };

  const handleCreatePage = () => {
    Alert.alert(
      'Create Landing Page',
      'Choose how to create a landing page:',
      [
        {
          text: 'From Template',
          onPress: () => {
            navigation.navigate('TemplateSelection');
          },
        },
        {
          text: 'With AI',
          onPress: () => {
            navigation.navigate('AILandingPageCreator');
          },
        },
        { text: 'Cancel', onPress: () => {} },
      ]
    );
  };

  const showActionMenu = (page: LandingPage) => {
    const isPublished = page.status === 'published';
    Alert.alert(
      'Actions',
      '',
      [
        {
          text: isPublished ? 'Unpublish' : 'Publish',
          onPress: () => handlePublishToggle(page),
        },
        {
          text: 'View Submissions',
          onPress: () => handleViewSubmissions(page),
        },
        {
          text: 'Delete',
          onPress: () => handleDeletePage(page),
          style: 'destructive',
        },
        { text: 'Cancel', onPress: () => {} },
      ]
    );
  };

  const renderPageCard = ({ item, index }: { item: LandingPage; index: number }) => {
    const isPublished = item.status === 'published';
    const submissionBadge = (item.unread_submissions_count || 0) > 0;

    return (
      <MotiView
        from={{ opacity: 0, translateY: 20 }}
        animate={{ opacity: 1, translateY: 0 }}
        transition={{ type: 'timing', duration: 350, delay: index * 50 }}
      >
        <Card
          style={[styles.pageCard, { backgroundColor: colors.card }]}
          onPress={() => handlePagePress(item)}
          mode="outlined"
        >
          <Card.Content>
            {/* Header with status and actions */}
            <View style={styles.cardHeader}>
              <View style={styles.titleContainer}>
                <Text style={[styles.pageTitle, { color: colors.text }]} numberOfLines={2}>
                  {item.title}
                </Text>
                <View style={styles.statusBadgeContainer}>
                  <Chip
                    compact
                    mode="flat"
                    style={[
                      styles.statusChip,
                      { backgroundColor: isPublished ? colors.success + '20' : colors.textTertiary + '20' },
                    ]}
                    textStyle={[
                      styles.statusChipText,
                      { color: isPublished ? colors.success : colors.textTertiary },
                    ]}
                  >
                    {isPublished ? 'Published' : 'Draft'}
                  </Chip>
                  {submissionBadge && (
                    <View style={[styles.unreadBadge, { backgroundColor: colors.error }]}>
                      <Text style={styles.unreadBadgeText}>
                        {item.unread_submissions_count}
                      </Text>
                    </View>
                  )}
                </View>
              </View>

              <IconButton
                icon="dots-vertical"
                size={20}
                iconColor={colors.textSecondary}
                onPress={() => showActionMenu(item)}
                style={styles.menuButton}
              />
            </View>

            {/* Description */}
            {item.description && (
              <Text style={[styles.pageDescription, { color: colors.textSecondary }]} numberOfLines={2}>
                {item.description}
              </Text>
            )}

            {/* Stats */}
            <View style={[styles.statsContainer, { borderTopColor: colors.border, borderBottomColor: colors.border }]}>
              <View style={styles.statItem}>
                <FileText size={16} color={colors.primary} />
                <Text style={[styles.statLabel, { color: colors.textTertiary }]}>Submissions:</Text>
                <Text style={[styles.statValue, { color: colors.text }]}>{item.submission_count || 0}</Text>
              </View>

              <View style={styles.statItem}>
                <Eye size={16} color={colors.success} />
                <Text style={[styles.statLabel, { color: colors.textTertiary }]}>Views:</Text>
                <Text style={[styles.statValue, { color: colors.text }]}>{item.view_count || 0}</Text>
              </View>

              <View style={styles.statItem}>
                <Percent size={16} color={colors.warning} />
                <Text style={[styles.statLabel, { color: colors.textTertiary }]}>Conv:</Text>
                <Text style={[styles.statValue, { color: colors.text }]}>
                  {item.submission_count && item.view_count
                    ? formatPercentage(item.submission_count / item.view_count)
                    : 'N/A'}
                </Text>
              </View>
            </View>

            {/* Footer */}
            <View style={styles.cardFooter}>
              <Text style={[styles.footerText, { color: colors.textTertiary }]}>
                Created {formatShortDate(item.created_at)}
              </Text>
              {item.published_at && (
                <Text style={[styles.footerText, { color: colors.textTertiary }]}>
                  Updated {formatShortDate(item.published_at)}
                </Text>
              )}
            </View>
          </Card.Content>
        </Card>
      </MotiView>
    );
  };

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <FileQuestion size={64} color={colors.textTertiary} />
      <Text style={[styles.emptyTitle, { color: colors.textSecondary }]}>No landing pages yet</Text>
      <Text style={[styles.emptySubtitle, { color: colors.textTertiary }]}>
        Create your first landing page to collect submissions
      </Text>
      <Button
        mode="contained"
        onPress={handleCreatePage}
        icon="plus"
        style={styles.createButton}
        buttonColor={colors.primary}
      >
        Create Landing Page
      </Button>
    </View>
  );

  const renderFooter = () => {
    if (!isLoading || pages.length === 0) return null;
    return (
      <View style={styles.footerLoader}>
        <ActivityIndicator size="small" color={colors.primary} />
      </View>
    );
  };

  const getFilterLabel = () => {
    if (statusFilter === 'draft') return 'Draft';
    if (statusFilter === 'published') return 'Published';
    return 'All';
  };

  if (isLoading && pages.length === 0) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
          <Text style={[styles.loadingText, { color: colors.textSecondary }]}>Loading landing pages...</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      {/* Header */}
      <View style={[styles.header, { backgroundColor: colors.surface, borderBottomColor: colors.border }]}>
        <View>
          <Text style={[styles.headerTitle, { color: colors.text }]}>Landing Pages</Text>
          <Text style={[styles.headerSubtitle, { color: colors.textTertiary }]}>
            {pagination.total} total pages
          </Text>
        </View>
        <IconButton
          icon="plus"
          size={24}
          iconColor={colors.primary}
          onPress={handleCreatePage}
        />
      </View>

      {/* Search Bar */}
      <View style={styles.searchContainer}>
        <Searchbar
          placeholder="Search landing pages..."
          value={searchText}
          onChangeText={setSearchText}
          style={[styles.searchBar, { backgroundColor: colors.surface }]}
          inputStyle={{ color: colors.text }}
          iconColor={colors.textTertiary}
          placeholderTextColor={colors.textTertiary}
        />
        <IconButton
          icon="filter-variant"
          size={24}
          iconColor={statusFilter ? colors.primary : colors.textSecondary}
          onPress={() => setIsFilterModalVisible(true)}
          style={[
            styles.filterButton,
            statusFilter && { backgroundColor: colors.primary + '15' },
          ]}
        />
      </View>

      {/* Active Filter Chip */}
      {statusFilter && (
        <View style={styles.activeFilterContainer}>
          <Chip
            mode="outlined"
            onClose={() => {
              setStatusFilter(undefined);
              loadPages();
            }}
            style={{ borderColor: colors.primary }}
            textStyle={{ color: colors.primary }}
          >
            Status: {getFilterLabel()}
          </Chip>
        </View>
      )}

      {/* Error message */}
      {error && (
        <View style={[styles.errorBox, { backgroundColor: colors.errorLight, borderLeftColor: colors.error }]}>
          <Text style={[styles.errorText, { color: colors.error }]}>{error}</Text>
        </View>
      )}

      {/* Landing Pages List */}
      <FlatList
        data={pages}
        renderItem={renderPageCard}
        keyExtractor={(item) => item.id}
        ListEmptyComponent={renderEmpty}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={handleRefresh}
            tintColor={colors.primary}
          />
        }
        onEndReached={handleLoadMore}
        onEndReachedThreshold={0.5}
        ListFooterComponent={renderFooter}
        contentContainerStyle={styles.listContent}
      />

      {/* Filter Modal */}
      <Portal>
        <Modal
          visible={isFilterModalVisible}
          onDismiss={() => setIsFilterModalVisible(false)}
          contentContainerStyle={[styles.modalContent, { backgroundColor: colors.surface }]}
        >
          <View style={[styles.modalHeader, { borderBottomColor: colors.border }]}>
            <Text style={[styles.modalTitle, { color: colors.text }]}>Filter Pages</Text>
            <IconButton
              icon="close"
              size={24}
              iconColor={colors.text}
              onPress={() => setIsFilterModalVisible(false)}
            />
          </View>

          <View style={styles.filterOptions}>
            <Text style={[styles.filterLabel, { color: colors.text }]}>Status</Text>
            {[
              { value: undefined, label: 'All' },
              { value: 'draft' as StatusFilter, label: 'Draft' },
              { value: 'published' as StatusFilter, label: 'Published' },
            ].map((option) => (
              <Chip
                key={option.label}
                mode={statusFilter === option.value ? 'flat' : 'outlined'}
                selected={statusFilter === option.value}
                onPress={() => setStatusFilter(option.value)}
                style={[
                  styles.filterChip,
                  statusFilter === option.value && { backgroundColor: colors.primary + '20' },
                ]}
                textStyle={[
                  styles.filterChipText,
                  { color: statusFilter === option.value ? colors.primary : colors.textSecondary },
                ]}
              >
                {option.label}
              </Chip>
            ))}
          </View>

          <Button
            mode="contained"
            onPress={() => {
              setIsFilterModalVisible(false);
              loadPages();
            }}
            style={styles.applyFilterButton}
            buttonColor={colors.primary}
          >
            Apply Filter
          </Button>
        </Modal>
      </Portal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
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
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '700',
  },
  headerSubtitle: {
    fontSize: 12,
    marginTop: 4,
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  searchBar: {
    flex: 1,
    elevation: 0,
    borderRadius: 8,
  },
  filterButton: {
    marginLeft: 4,
  },
  activeFilterContainer: {
    paddingHorizontal: 12,
    paddingBottom: 8,
  },
  errorBox: {
    marginHorizontal: 12,
    marginVertical: 8,
    padding: 12,
    borderRadius: 6,
    borderLeftWidth: 4,
  },
  errorText: {
    fontSize: 13,
  },
  listContent: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    flexGrow: 1,
  },
  pageCard: {
    marginBottom: 12,
    borderRadius: 12,
  },
  cardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 8,
  },
  titleContainer: {
    flex: 1,
    marginRight: 8,
  },
  pageTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
  },
  statusBadgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusChip: {
    marginRight: 8,
  },
  statusChipText: {
    fontSize: 11,
    fontWeight: '600',
  },
  unreadBadge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 10,
    minWidth: 20,
    alignItems: 'center',
  },
  unreadBadgeText: {
    fontSize: 10,
    fontWeight: '600',
    color: '#fff',
  },
  menuButton: {
    margin: -8,
  },
  pageDescription: {
    fontSize: 13,
    marginBottom: 12,
    lineHeight: 18,
  },
  statsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 12,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    marginBottom: 12,
  },
  statItem: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  statLabel: {
    fontSize: 11,
    marginHorizontal: 4,
  },
  statValue: {
    fontSize: 12,
    fontWeight: '600',
  },
  cardFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  footerText: {
    fontSize: 11,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 60,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginTop: 12,
  },
  emptySubtitle: {
    fontSize: 13,
    marginTop: 6,
    textAlign: 'center',
  },
  createButton: {
    marginTop: 20,
    borderRadius: 8,
  },
  footerLoader: {
    paddingVertical: 16,
    alignItems: 'center',
  },
  modalContent: {
    margin: 20,
    borderRadius: 16,
    paddingBottom: 20,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingLeft: 16,
    paddingRight: 4,
    paddingVertical: 8,
    borderBottomWidth: 1,
  },
  modalTitle: {
    fontSize: 16,
    fontWeight: '600',
  },
  filterOptions: {
    padding: 16,
  },
  filterLabel: {
    fontSize: 12,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 12,
  },
  filterChip: {
    marginBottom: 8,
  },
  filterChipText: {
    fontSize: 14,
  },
  applyFilterButton: {
    marginHorizontal: 16,
    borderRadius: 8,
  },
});
