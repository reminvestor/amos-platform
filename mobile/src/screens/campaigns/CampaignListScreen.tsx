import React, { useState, useEffect } from 'react';
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
import { fetchCampaigns, pauseCampaign, resumeCampaign } from '@store/slices/campaignsSlice';
import { Campaign } from '@types';
import { formatShortDate, formatPercentage, formatContactCount, formatCampaignStatus } from '@utils/formatters';
import { FavoriteButton } from '@components/FavoriteButton';
import { getColors } from '@theme/colors';
import { addSearchHistory } from '@utils/searchHistory';
import { getDateRangePresets, formatDateRange, type DateRange } from '@utils/dateFilters';

interface CampaignListScreenProps {
  navigation: any;
}

export default function CampaignListScreen({ navigation }: CampaignListScreenProps) {
  const dispatch = useAppDispatch();
  const { list, isLoading, error, pagination } = useAppSelector((state) => state.campaigns);
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const [searchText, setSearchText] = useState('');
  const [statusFilter, setStatusFilter] = useState<string | undefined>();
  const [isFilterModalVisible, setIsFilterModalVisible] = useState(false);
  const [selectedDateRange, setSelectedDateRange] = useState<string | undefined>();
  const dateRangePresets = getDateRangePresets();

  // Load campaigns when screen is focused
  useFocusEffect(
    React.useCallback(() => {
      loadCampaigns();
    }, [])
  );

  const loadCampaigns = async () => {
    if (searchText.trim()) {
      await addSearchHistory(searchText, 'campaigns');
    }
    await dispatch(
      fetchCampaigns({
        page: 1,
        perPage: 20,
        search: searchText,
        status: statusFilter,
      })
    );
  };

  const handleRefresh = () => {
    loadCampaigns();
  };

  const handleLoadMore = () => {
    if (pagination.hasNext && !isLoading) {
      dispatch(
        fetchCampaigns({
          page: pagination.page + 1,
          perPage: 20,
          search: searchText,
          status: statusFilter,
        })
      );
    }
  };

  const handleCampaignPress = (campaign: Campaign) => {
    navigation.navigate('CampaignDetail', { campaignId: campaign.id });
  };

  const handlePauseCampaign = async (campaign: Campaign) => {
    if (campaign.status !== 'in_progress') {
      Alert.alert('Error', 'Only in-progress campaigns can be paused');
      return;
    }

    Alert.alert(
      'Pause Campaign',
      `Are you sure you want to pause "${campaign.name}"?`,
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: 'Pause',
          onPress: async () => {
            try {
              await dispatch(pauseCampaign(campaign.id));
              Alert.alert('Success', 'Campaign paused');
            } catch (error) {
              Alert.alert('Error', 'Failed to pause campaign');
            }
          },
        },
      ]
    );
  };

  const handleResumeCampaign = async (campaign: Campaign) => {
    if (campaign.status !== 'paused') {
      Alert.alert('Error', 'Only paused campaigns can be resumed');
      return;
    }

    Alert.alert(
      'Resume Campaign',
      `Are you sure you want to resume "${campaign.name}"?`,
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: 'Resume',
          onPress: async () => {
            try {
              await dispatch(resumeCampaign(campaign.id));
              Alert.alert('Success', 'Campaign resumed');
            } catch (error) {
              Alert.alert('Error', 'Failed to resume campaign');
            }
          },
        },
      ]
    );
  };

  const renderCampaignCard = ({ item }: { item: Campaign }) => {
    const statusInfo = formatCampaignStatus(item.status);
    const openRate = item.open_rate ? formatPercentage(item.open_rate) : 'N/A';
    const clickRate = item.click_rate ? formatPercentage(item.click_rate) : 'N/A';

    return (
      <TouchableOpacity
        style={styles.campaignCard}
        onPress={() => handleCampaignPress(item)}
      >
        {/* Header */}
        <View style={styles.cardHeader}>
          <View style={styles.titleContainer}>
            <Text style={styles.campaignName} numberOfLines={2}>
              {item.name}
            </Text>
            <View
              style={[
                styles.statusBadge,
                { backgroundColor: statusInfo.color },
              ]}
            >
              <Text style={styles.statusText}>{statusInfo.label}</Text>
            </View>
          </View>

          {/* Action Menu */}
          <View style={styles.actionMenu}>
            <FavoriteButton id={item.id} type="campaign" size={20} />

            {item.status === 'in_progress' && (
              <TouchableOpacity
                onPress={() => handlePauseCampaign(item)}
                style={styles.actionButton}
              >
                <MaterialCommunityIcons name="pause" size={20} color="#F5A623" />
              </TouchableOpacity>
            )}

            {item.status === 'paused' && (
              <TouchableOpacity
                onPress={() => handleResumeCampaign(item)}
                style={styles.actionButton}
              >
                <MaterialCommunityIcons name="play" size={20} color="#4A90E2" />
              </TouchableOpacity>
            )}
          </View>
        </View>

        {/* Subject */}
        <Text style={styles.subject} numberOfLines={1}>
          {item.subject}
        </Text>

        {/* Details */}
        <View style={styles.detailsRow}>
          <View style={styles.detailItem}>
            <MaterialCommunityIcons name="account-multiple" size={16} color="#666" />
            <Text style={styles.detailText}>
              {formatContactCount(item.contact_count || 0)}
            </Text>
          </View>

          {item.open_rate !== undefined && (
            <View style={styles.detailItem}>
              <MaterialCommunityIcons name="email-open" size={16} color="#666" />
              <Text style={styles.detailText}>{openRate}</Text>
            </View>
          )}

          {item.click_rate !== undefined && (
            <View style={styles.detailItem}>
              <MaterialCommunityIcons name="cursor-default-click" size={16} color="#666" />
              <Text style={styles.detailText}>{clickRate}</Text>
            </View>
          )}
        </View>

        {/* Footer */}
        <Text style={styles.createdAt}>
          Created {formatShortDate(item.created_at)}
        </Text>
      </TouchableOpacity>
    );
  };

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <MaterialCommunityIcons name="email-outline" size={64} color="#ccc" />
      <Text style={styles.emptyTitle}>No campaigns yet</Text>
      <Text style={styles.emptySubtitle}>
        Create your first campaign from the web app
      </Text>
    </View>
  );

  const renderFooter = () => {
    if (!isLoading || list.length === 0) return null;
    return (
      <View style={styles.footerLoader}>
        <ActivityIndicator size="small" color="#4A90E2" />
      </View>
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      {/* Search and Filter Bar */}
      <View style={styles.searchBar}>
        <MaterialCommunityIcons name="magnify" size={20} color="#999" />
        <TextInput
          style={styles.searchInput}
          placeholder="Search campaigns..."
          placeholderTextColor="#999"
          value={searchText}
          onChangeText={setSearchText}
          onSubmitEditing={loadCampaigns}
        />
        <TouchableOpacity
          onPress={() => setIsFilterModalVisible(true)}
          style={styles.filterButton}
        >
          <MaterialCommunityIcons name="filter" size={20} color="#4A90E2" />
        </TouchableOpacity>
      </View>

      {/* Error message */}
      {error && (
        <View style={styles.errorBox}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}

      {/* Campaigns List */}
      <FlatList
        data={list}
        renderItem={renderCampaignCard}
        keyExtractor={(item) => item.id}
        ListEmptyComponent={renderEmpty}
        refreshControl={
          <RefreshControl
            refreshing={isLoading && list.length > 0}
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
              <Text style={styles.modalTitle}>Filter Campaigns</Text>
              <TouchableOpacity onPress={() => setIsFilterModalVisible(false)}>
                <MaterialCommunityIcons name="close" size={24} color="#333" />
              </TouchableOpacity>
            </View>

            {/* Status Filters */}
            <Text style={styles.filterSectionTitle}>Campaign Status</Text>
            <View style={styles.filterOptions}>
              {['draft', 'scheduled', 'in_progress', 'completed', 'paused', 'stopped'].map(
                (status) => (
                  <TouchableOpacity
                    key={status}
                    style={[
                      styles.filterOption,
                      statusFilter === status && styles.filterOptionSelected,
                    ]}
                    onPress={() => {
                      setStatusFilter(statusFilter === status ? undefined : status);
                    }}
                  >
                    <Text
                      style={[
                        styles.filterOptionText,
                        statusFilter === status && styles.filterOptionTextSelected,
                      ]}
                    >
                      {status.charAt(0).toUpperCase() + status.slice(1).replace('_', ' ')}
                    </Text>
                  </TouchableOpacity>
                )
              )}
            </View>

            {/* Date Range Filters */}
            <Text style={styles.filterSectionTitle}>Created Date</Text>
            <View style={styles.filterOptions}>
              {Object.entries(dateRangePresets).map(([key, range]) => (
                <TouchableOpacity
                  key={key}
                  style={[
                    styles.filterOption,
                    selectedDateRange === key && styles.filterOptionSelected,
                  ]}
                  onPress={() => {
                    setSelectedDateRange(selectedDateRange === key ? undefined : key);
                  }}
                >
                  <Text
                    style={[
                      styles.filterOptionText,
                      selectedDateRange === key && styles.filterOptionTextSelected,
                    ]}
                  >
                    {range.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            <TouchableOpacity
              style={styles.applyFilterButton}
              onPress={() => {
                setIsFilterModalVisible(false);
                loadCampaigns();
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
    backgroundColor: '#fff',
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    marginVertical: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    backgroundColor: '#f0f0f0',
    borderRadius: 8,
  },
  searchInput: {
    flex: 1,
    marginHorizontal: 8,
    fontSize: 14,
    color: '#333',
  },
  filterButton: {
    padding: 4,
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
  campaignCard: {
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
  campaignName: {
    fontSize: 16,
    fontWeight: '600',
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
  actionMenu: {
    flexDirection: 'row',
  },
  actionButton: {
    padding: 8,
  },
  subject: {
    fontSize: 13,
    color: '#666',
    marginBottom: 12,
  },
  detailsRow: {
    flexDirection: 'row',
    marginBottom: 12,
  },
  detailItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginRight: 16,
  },
  detailText: {
    fontSize: 12,
    color: '#666',
    marginLeft: 4,
  },
  createdAt: {
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
  filterSectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#666',
    marginHorizontal: 16,
    marginTop: 16,
    marginBottom: 8,
  },
  filterOptions: {
    paddingHorizontal: 16,
    paddingTop: 8,
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
