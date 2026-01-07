import React, { useState } from 'react';
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
import { Users, MailOpen, MousePointerClick, Mail } from 'lucide-react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAppDispatch, useAppSelector } from '@store';
import { fetchCampaigns, pauseCampaign, resumeCampaign } from '@store/slices/campaignsSlice';
import { Campaign } from '@types';
import { formatShortDate, formatPercentage, formatContactCount, formatCampaignStatus } from '@utils/formatters';
import { FavoriteButton } from '@components/FavoriteButton';
import { getColors } from '@theme/colors';
import { addSearchHistory } from '@utils/searchHistory';
import { getDateRangePresets } from '@utils/dateFilters';

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

  const getStatusColor = (status: string) => {
    const statusInfo = formatCampaignStatus(status);
    return statusInfo.color;
  };

  const renderCampaignCard = ({ item, index }: { item: Campaign; index: number }) => {
    const statusInfo = formatCampaignStatus(item.status);
    const openRate = item.open_rate ? formatPercentage(item.open_rate) : 'N/A';
    const clickRate = item.click_rate ? formatPercentage(item.click_rate) : 'N/A';

    return (
      <MotiView
        from={{ opacity: 0, translateY: 20 }}
        animate={{ opacity: 1, translateY: 0 }}
        transition={{ type: 'timing', duration: 350, delay: index * 50 }}
      >
        <Card
          style={[styles.campaignCard, { backgroundColor: colors.card }]}
          onPress={() => handleCampaignPress(item)}
          mode="outlined"
        >
          <Card.Content>
            {/* Header */}
            <View style={styles.cardHeader}>
              <View style={styles.titleContainer}>
                <Text style={[styles.campaignName, { color: colors.text }]} numberOfLines={2}>
                  {item.name}
                </Text>
                <Chip
                  compact
                  mode="flat"
                  style={[styles.statusChip, { backgroundColor: statusInfo.color + '20' }]}
                  textStyle={[styles.statusChipText, { color: statusInfo.color }]}
                >
                  {statusInfo.label}
                </Chip>
              </View>

              {/* Action Menu */}
              <View style={styles.actionMenu}>
                <FavoriteButton id={item.id} type="campaign" size={20} />

                {item.status === 'in_progress' && (
                  <IconButton
                    icon="pause"
                    size={20}
                    iconColor={colors.warning}
                    onPress={() => handlePauseCampaign(item)}
                    style={styles.actionButton}
                  />
                )}

                {item.status === 'paused' && (
                  <IconButton
                    icon="play"
                    size={20}
                    iconColor={colors.primary}
                    onPress={() => handleResumeCampaign(item)}
                    style={styles.actionButton}
                  />
                )}
              </View>
            </View>

            {/* Subject */}
            <Text style={[styles.subject, { color: colors.textSecondary }]} numberOfLines={1}>
              {item.subject}
            </Text>

            {/* Details */}
            <View style={styles.detailsRow}>
              <View style={styles.detailItem}>
                <Users size={16} color={colors.textSecondary} />
                <Text style={[styles.detailText, { color: colors.textSecondary }]}>
                  {formatContactCount(item.contact_count || 0)}
                </Text>
              </View>

              {item.open_rate !== undefined && (
                <View style={styles.detailItem}>
                  <MailOpen size={16} color={colors.success} />
                  <Text style={[styles.detailText, { color: colors.textSecondary }]}>{openRate}</Text>
                </View>
              )}

              {item.click_rate !== undefined && (
                <View style={styles.detailItem}>
                  <MousePointerClick size={16} color={colors.primary} />
                  <Text style={[styles.detailText, { color: colors.textSecondary }]}>{clickRate}</Text>
                </View>
              )}
            </View>

            {/* Footer */}
            <Text style={[styles.createdAt, { color: colors.textTertiary }]}>
              Created {formatShortDate(item.created_at)}
            </Text>
          </Card.Content>
        </Card>
      </MotiView>
    );
  };

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <Mail size={64} color={colors.textTertiary} />
      <Text style={[styles.emptyTitle, { color: colors.textSecondary }]}>No campaigns yet</Text>
      <Text style={[styles.emptySubtitle, { color: colors.textTertiary }]}>
        Create your first campaign from the web app
      </Text>
    </View>
  );

  const renderFooter = () => {
    if (!isLoading || list.length === 0) return null;
    return (
      <View style={styles.footerLoader}>
        <ActivityIndicator size="small" color={colors.primary} />
      </View>
    );
  };

  const getFilterLabel = () => {
    if (!statusFilter) return null;
    return statusFilter.charAt(0).toUpperCase() + statusFilter.slice(1).replace('_', ' ');
  };

  const getDateRangeLabel = () => {
    if (!selectedDateRange) return null;
    return dateRangePresets[selectedDateRange]?.label;
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      {/* Search and Filter Bar */}
      <View style={styles.searchContainer}>
        <Searchbar
          placeholder="Search campaigns..."
          value={searchText}
          onChangeText={setSearchText}
          onSubmitEditing={loadCampaigns}
          style={[styles.searchBar, { backgroundColor: colors.surface }]}
          inputStyle={{ color: colors.text }}
          iconColor={colors.textTertiary}
          placeholderTextColor={colors.textTertiary}
        />
        <IconButton
          icon="filter-variant"
          size={24}
          iconColor={(statusFilter || selectedDateRange) ? colors.primary : colors.textSecondary}
          onPress={() => setIsFilterModalVisible(true)}
          style={[
            styles.filterButton,
            (statusFilter || selectedDateRange) && { backgroundColor: colors.primary + '15' },
          ]}
        />
      </View>

      {/* Active Filter Chips */}
      {(statusFilter || selectedDateRange) && (
        <View style={styles.activeFilterContainer}>
          {statusFilter && (
            <Chip
              mode="outlined"
              onClose={() => {
                setStatusFilter(undefined);
                loadCampaigns();
              }}
              style={[styles.activeFilterChip, { borderColor: colors.primary }]}
              textStyle={{ color: colors.primary }}
            >
              Status: {getFilterLabel()}
            </Chip>
          )}
          {selectedDateRange && (
            <Chip
              mode="outlined"
              onClose={() => {
                setSelectedDateRange(undefined);
                loadCampaigns();
              }}
              style={[styles.activeFilterChip, { borderColor: colors.primary }]}
              textStyle={{ color: colors.primary }}
            >
              {getDateRangeLabel()}
            </Chip>
          )}
        </View>
      )}

      {/* Error message */}
      {error && (
        <View style={[styles.errorBox, { backgroundColor: colors.errorLight, borderLeftColor: colors.error }]}>
          <Text style={[styles.errorText, { color: colors.error }]}>{error}</Text>
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
            <Text style={[styles.modalTitle, { color: colors.text }]}>Filter Campaigns</Text>
            <IconButton
              icon="close"
              size={24}
              iconColor={colors.text}
              onPress={() => setIsFilterModalVisible(false)}
            />
          </View>

          {/* Status Filters */}
          <View style={styles.filterSection}>
            <Text style={[styles.filterSectionTitle, { color: colors.text }]}>Campaign Status</Text>
            <View style={styles.chipContainer}>
              {['draft', 'scheduled', 'in_progress', 'completed', 'paused', 'stopped'].map(
                (status) => (
                  <Chip
                    key={status}
                    mode={statusFilter === status ? 'flat' : 'outlined'}
                    selected={statusFilter === status}
                    onPress={() => setStatusFilter(statusFilter === status ? undefined : status)}
                    style={[
                      styles.filterChip,
                      statusFilter === status && { backgroundColor: colors.primary + '20' },
                    ]}
                    textStyle={[
                      styles.filterChipText,
                      { color: statusFilter === status ? colors.primary : colors.textSecondary },
                    ]}
                  >
                    {status.charAt(0).toUpperCase() + status.slice(1).replace('_', ' ')}
                  </Chip>
                )
              )}
            </View>
          </View>

          {/* Date Range Filters */}
          <View style={styles.filterSection}>
            <Text style={[styles.filterSectionTitle, { color: colors.text }]}>Created Date</Text>
            <View style={styles.chipContainer}>
              {Object.entries(dateRangePresets).map(([key, range]) => (
                <Chip
                  key={key}
                  mode={selectedDateRange === key ? 'flat' : 'outlined'}
                  selected={selectedDateRange === key}
                  onPress={() => setSelectedDateRange(selectedDateRange === key ? undefined : key)}
                  style={[
                    styles.filterChip,
                    selectedDateRange === key && { backgroundColor: colors.primary + '20' },
                  ]}
                  textStyle={[
                    styles.filterChipText,
                    { color: selectedDateRange === key ? colors.primary : colors.textSecondary },
                  ]}
                >
                  {range.label}
                </Chip>
              ))}
            </View>
          </View>

          <Button
            mode="contained"
            onPress={() => {
              setIsFilterModalVisible(false);
              loadCampaigns();
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
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 12,
    paddingBottom: 8,
    gap: 8,
  },
  activeFilterChip: {
    marginRight: 8,
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
  campaignCard: {
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
  campaignName: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
  },
  statusChip: {
    alignSelf: 'flex-start',
  },
  statusChipText: {
    fontSize: 11,
    fontWeight: '600',
  },
  actionMenu: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  actionButton: {
    margin: -4,
  },
  subject: {
    fontSize: 13,
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
    marginLeft: 4,
  },
  createdAt: {
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
  footerLoader: {
    paddingVertical: 16,
    alignItems: 'center',
  },
  modalContent: {
    margin: 20,
    borderRadius: 16,
    paddingBottom: 20,
    maxHeight: '80%',
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
  filterSection: {
    padding: 16,
    paddingBottom: 0,
  },
  filterSectionTitle: {
    fontSize: 12,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 12,
  },
  chipContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  filterChip: {
    marginBottom: 4,
  },
  filterChipText: {
    fontSize: 13,
  },
  applyFilterButton: {
    marginHorizontal: 16,
    marginTop: 16,
    borderRadius: 8,
  },
});
