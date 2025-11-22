import React, { useState, useCallback } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  SafeAreaView,
  ActivityIndicator,
  RefreshControl,
  TextInput,
  Modal,
  Alert,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAppDispatch, useAppSelector } from '@store';
import { LandingPage } from '@types';
import { formatShortDate, formatPercentage } from '@utils/formatters';
import * as landingPageService from '@services/landing-pages';

interface LandingPageListScreenProps {
  navigation: any;
}

type StatusFilter = 'draft' | 'published' | undefined;

export default function LandingPageListScreen({ navigation }: LandingPageListScreenProps) {
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

  const renderPageCard = ({ item }: { item: LandingPage }) => {
    const isPublished = item.status === 'published';
    const submissionBadge = (item.unread_submissions_count || 0) > 0;

    return (
      <TouchableOpacity
        style={styles.pageCard}
        onPress={() => handlePagePress(item)}
      >
        {/* Header with status and actions */}
        <View style={styles.cardHeader}>
          <View style={styles.titleContainer}>
            <Text style={styles.pageTitle} numberOfLines={2}>
              {item.title}
            </Text>
            <View style={styles.statusBadgeContainer}>
              <View
                style={[
                  styles.statusBadge,
                  { backgroundColor: isPublished ? '#27AE60' : '#95A5A6' },
                ]}
              >
                <Text style={styles.statusText}>
                  {isPublished ? 'Published' : 'Draft'}
                </Text>
              </View>
              {submissionBadge && (
                <View style={styles.unreadBadge}>
                  <Text style={styles.unreadBadgeText}>
                    {item.unread_submissions_count}
                  </Text>
                </View>
              )}
            </View>
          </View>

          {/* Action Menu Button */}
          <TouchableOpacity
            style={styles.menuButton}
            onPress={() => {
              Alert.alert(
                'Actions',
                '',
                [
                  {
                    text: isPublished ? 'Unpublish' : 'Publish',
                    onPress: () => handlePublishToggle(item),
                  },
                  {
                    text: 'View Submissions',
                    onPress: () => handleViewSubmissions(item),
                  },
                  {
                    text: 'Delete',
                    onPress: () => handleDeletePage(item),
                    style: 'destructive',
                  },
                  { text: 'Cancel', onPress: () => {} },
                ]
              );
            }}
          >
            <MaterialCommunityIcons name="dots-vertical" size={20} color="#666" />
          </TouchableOpacity>
        </View>

        {/* Description */}
        {item.description && (
          <Text style={styles.pageDescription} numberOfLines={2}>
            {item.description}
          </Text>
        )}

        {/* Stats */}
        <View style={styles.statsContainer}>
          <View style={styles.statItem}>
            <MaterialCommunityIcons name="form-textbox" size={16} color="#4A90E2" />
            <Text style={styles.statLabel}>Submissions:</Text>
            <Text style={styles.statValue}>{item.submission_count || 0}</Text>
          </View>

          <View style={styles.statItem}>
            <MaterialCommunityIcons name="eye" size={16} color="#27AE60" />
            <Text style={styles.statLabel}>Views:</Text>
            <Text style={styles.statValue}>{item.view_count || 0}</Text>
          </View>

          <View style={styles.statItem}>
            <MaterialCommunityIcons name="percent" size={16} color="#F5A623" />
            <Text style={styles.statLabel}>Conversion:</Text>
            <Text style={styles.statValue}>
              {item.submission_count && item.view_count
                ? formatPercentage(item.submission_count / item.view_count)
                : 'N/A'}
            </Text>
          </View>
        </View>

        {/* Footer */}
        <View style={styles.cardFooter}>
          <Text style={styles.footerText}>
            Created {formatShortDate(item.created_at)}
          </Text>
          {item.published_at && (
            <Text style={styles.footerText}>
              Updated {formatShortDate(item.published_at)}
            </Text>
          )}
        </View>
      </TouchableOpacity>
    );
  };

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <MaterialCommunityIcons name="file-document-outline" size={64} color="#ccc" />
      <Text style={styles.emptyTitle}>No landing pages yet</Text>
      <Text style={styles.emptySubtitle}>
        Create your first landing page to collect submissions
      </Text>
      <TouchableOpacity style={styles.createButton} onPress={handleCreatePage}>
        <MaterialCommunityIcons name="plus" size={20} color="#fff" />
        <Text style={styles.createButtonText}>Create Landing Page</Text>
      </TouchableOpacity>
    </View>
  );

  const renderFooter = () => {
    if (!isLoading || pages.length === 0) return null;
    return (
      <View style={styles.footerLoader}>
        <ActivityIndicator size="small" color="#4A90E2" />
      </View>
    );
  };

  if (isLoading && pages.length === 0) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color="#4A90E2" />
          <Text style={styles.loadingText}>Loading landing pages...</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <View>
          <Text style={styles.headerTitle}>Landing Pages</Text>
          <Text style={styles.headerSubtitle}>
            {pagination.total} total pages
          </Text>
        </View>
        <TouchableOpacity style={styles.createButtonHeader} onPress={handleCreatePage}>
          <MaterialCommunityIcons name="plus" size={24} color="#4A90E2" />
        </TouchableOpacity>
      </View>

      {/* Search Bar */}
      <View style={styles.searchBar}>
        <MaterialCommunityIcons name="magnify" size={20} color="#999" />
        <TextInput
          style={styles.searchInput}
          placeholder="Search landing pages..."
          placeholderTextColor="#999"
          value={searchText}
          onChangeText={setSearchText}
        />
        <TouchableOpacity onPress={() => setIsFilterModalVisible(true)}>
          <MaterialCommunityIcons name="filter" size={20} color="#4A90E2" />
        </TouchableOpacity>
      </View>

      {/* Error message */}
      {error && (
        <View style={styles.errorBox}>
          <Text style={styles.errorText}>{error}</Text>
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
            tintColor="#4A90E2"
          />
        }
        onEndReached={handleLoadMore}
        onEndReachedThreshold={0.5}
        ListFooterComponent={renderFooter}
        contentContainerStyle={styles.listContent}
      />

      {/* Filter Modal */}
      <Modal
        visible={isFilterModalVisible}
        transparent
        animationType="slide"
        onRequestClose={() => setIsFilterModalVisible(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Filter Pages</Text>
              <TouchableOpacity onPress={() => setIsFilterModalVisible(false)}>
                <MaterialCommunityIcons name="close" size={24} color="#333" />
              </TouchableOpacity>
            </View>

            <View style={styles.filterOptions}>
              <Text style={styles.filterLabel}>Status</Text>
              {[
                { value: undefined, label: 'All' },
                { value: 'draft', label: 'Draft' },
                { value: 'published', label: 'Published' },
              ].map((option) => (
                <TouchableOpacity
                  key={option.label}
                  style={[
                    styles.filterOption,
                    statusFilter === option.value && styles.filterOptionSelected,
                  ]}
                  onPress={() => {
                    setStatusFilter(statusFilter === option.value ? undefined : option.value as StatusFilter);
                  }}
                >
                  <Text
                    style={[
                      styles.filterOptionText,
                      statusFilter === option.value && styles.filterOptionTextSelected,
                    ]}
                  >
                    {option.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            <TouchableOpacity
              style={styles.applyFilterButton}
              onPress={() => {
                setIsFilterModalVisible(false);
                loadPages();
              }}
            >
              <Text style={styles.applyFilterButtonText}>Apply Filter</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
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
  },
  loadingText: {
    marginTop: 12,
    fontSize: 14,
    color: '#666',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: '#333',
  },
  headerSubtitle: {
    fontSize: 12,
    color: '#999',
    marginTop: 4,
  },
  createButtonHeader: {
    padding: 8,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    marginVertical: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    backgroundColor: '#fff',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#eee',
  },
  searchInput: {
    flex: 1,
    marginHorizontal: 8,
    fontSize: 14,
    color: '#333',
  },
  errorBox: {
    backgroundColor: '#fee',
    marginHorizontal: 16,
    marginVertical: 8,
    padding: 12,
    borderRadius: 6,
    borderLeftWidth: 4,
    borderLeftColor: '#c33',
  },
  errorText: {
    color: '#c33',
    fontSize: 13,
  },
  listContent: {
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  pageCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#eee',
    padding: 16,
    marginBottom: 12,
  },
  cardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 12,
  },
  titleContainer: {
    flex: 1,
    marginRight: 8,
  },
  pageTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: '#333',
    marginBottom: 8,
  },
  statusBadgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusBadge: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
    marginRight: 8,
  },
  statusText: {
    fontSize: 11,
    fontWeight: '600',
    color: '#fff',
  },
  unreadBadge: {
    backgroundColor: '#E74C3C',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 3,
  },
  unreadBadgeText: {
    fontSize: 10,
    fontWeight: '600',
    color: '#fff',
  },
  menuButton: {
    padding: 8,
    marginRight: -8,
  },
  pageDescription: {
    fontSize: 13,
    color: '#666',
    marginBottom: 12,
    lineHeight: 18,
  },
  statsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 12,
    borderTopWidth: 1,
    borderTopColor: '#eee',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
    marginBottom: 12,
  },
  statItem: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  statLabel: {
    fontSize: 12,
    color: '#999',
    marginHorizontal: 4,
  },
  statValue: {
    fontSize: 13,
    fontWeight: '600',
    color: '#333',
  },
  cardFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  footerText: {
    fontSize: 12,
    color: '#999',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#666',
    marginTop: 12,
  },
  emptySubtitle: {
    fontSize: 13,
    color: '#999',
    marginTop: 6,
    textAlign: 'center',
  },
  createButton: {
    marginTop: 20,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingVertical: 12,
    backgroundColor: '#4A90E2',
    borderRadius: 8,
  },
  createButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    marginLeft: 8,
  },
  footerLoader: {
    paddingVertical: 16,
    alignItems: 'center',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  modalContent: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    paddingBottom: 24,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  modalTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
  },
  filterOptions: {
    paddingHorizontal: 16,
    paddingTop: 16,
  },
  filterLabel: {
    fontSize: 12,
    fontWeight: '700',
    color: '#333',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 8,
  },
  filterOption: {
    paddingVertical: 12,
    paddingHorizontal: 12,
    marginBottom: 8,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#ddd',
  },
  filterOptionSelected: {
    backgroundColor: '#E8F1FF',
    borderColor: '#4A90E2',
  },
  filterOptionText: {
    fontSize: 14,
    color: '#666',
  },
  filterOptionTextSelected: {
    color: '#4A90E2',
    fontWeight: '600',
  },
  applyFilterButton: {
    marginHorizontal: 16,
    marginTop: 16,
    paddingVertical: 12,
    backgroundColor: '#4A90E2',
    borderRadius: 8,
    alignItems: 'center',
  },
  applyFilterButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
});
