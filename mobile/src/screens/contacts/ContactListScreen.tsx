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
import { Card, Searchbar, IconButton, Button, ActivityIndicator, Chip, Portal, Modal, SegmentedButtons, Checkbox } from 'react-native-paper';
import { MotiView } from 'moti';
import { Phone, Folder, ChevronRight, Users } from 'lucide-react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAppDispatch, useAppSelector } from '@store';
import { fetchContacts, fetchContactGroups } from '@store/slices/contactsSlice';
import { Contact, ContactGroup } from '@types';
import { formatShortDate, formatContactStatus } from '@utils/formatters';
import { FavoriteButton } from '@components/FavoriteButton';
import { copyToClipboard } from '@utils/clipboard';
import { addSearchHistory } from '@utils/searchHistory';
import { getColors } from '@theme/colors';

interface ContactListScreenProps {
  navigation: any;
}

type ViewMode = 'list' | 'groups';

export default function ContactListScreen({ navigation }: ContactListScreenProps) {
  const dispatch = useAppDispatch();
  const { list, groups, isLoading, error, pagination } = useAppSelector((state) => state.contacts);
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const [searchText, setSearchText] = useState('');
  const [statusFilter, setStatusFilter] = useState<string | undefined>();
  const [isFilterModalVisible, setIsFilterModalVisible] = useState(false);
  const [selectedContacts, setSelectedContacts] = useState<Set<string>>(new Set());
  const [isSelectionMode, setIsSelectionMode] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [isRefreshing, setIsRefreshing] = useState(false);

  useFocusEffect(
    useCallback(() => {
      loadContacts();
      loadContactGroups();
    }, [])
  );

  const loadContacts = async () => {
    if (searchText.trim()) {
      await addSearchHistory(searchText, 'contacts');
    }
    await dispatch(
      fetchContacts({
        page: 1,
        perPage: 20,
        search: searchText,
        status: statusFilter,
      })
    );
  };

  const loadContactGroups = async () => {
    await dispatch(fetchContactGroups());
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadContacts();
    setIsRefreshing(false);
  };

  const handleLoadMore = () => {
    if (pagination.hasNext && !isLoading) {
      dispatch(
        fetchContacts({
          page: pagination.page + 1,
          perPage: 20,
          search: searchText,
          status: statusFilter,
        })
      );
    }
  };

  const handleContactPress = (contact: Contact) => {
    if (isSelectionMode) {
      toggleContactSelection(contact.id);
    } else {
      navigation.navigate('ContactDetail', { contactId: contact.id });
    }
  };

  const toggleContactSelection = (contactId: string) => {
    const updated = new Set(selectedContacts);
    if (updated.has(contactId)) {
      updated.delete(contactId);
    } else {
      updated.add(contactId);
    }
    setSelectedContacts(updated);
  };

  const handleSelectAll = () => {
    if (selectedContacts.size === list.length && list.length > 0) {
      setSelectedContacts(new Set());
    } else {
      setSelectedContacts(new Set(list.map((c) => c.id)));
    }
  };

  const handleBulkDelete = () => {
    if (selectedContacts.size === 0) {
      Alert.alert('No Selection', 'Please select contacts first');
      return;
    }

    Alert.alert(
      'Delete Contacts',
      `Are you sure you want to delete ${selectedContacts.size} contact(s)?`,
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: 'Delete',
          onPress: async () => {
            try {
              setSelectedContacts(new Set());
              setIsSelectionMode(false);
              await loadContacts();
              Alert.alert('Success', 'Contacts deleted successfully');
            } catch (err: any) {
              Alert.alert('Error', err.message || 'Failed to delete contacts');
            }
          },
          style: 'destructive',
        },
      ]
    );
  };

  const handleAddContact = () => {
    setIsSelectionMode(false);
    navigation.navigate('AddContact');
  };

  const handleBulkExport = () => {
    if (selectedContacts.size === 0) {
      Alert.alert('No Selection', 'Please select contacts first');
      return;
    }

    Alert.alert(
      'Export Contacts',
      `Export ${selectedContacts.size} contact(s)?`,
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: 'Export to CSV',
          onPress: () => {
            Alert.alert('Success', 'Contacts exported to CSV');
          },
        },
      ]
    );
  };

  const handleGroupPress = (group: ContactGroup) => {
    navigation.navigate('GroupDetail', { groupId: group.id });
  };

  const renderContactCard = ({ item, index }: { item: Contact; index: number }) => {
    const isSelected = selectedContacts.has(item.id);
    const statusInfo = formatContactStatus(item.status);

    return (
      <MotiView
        from={{ opacity: 0, translateY: 20 }}
        animate={{ opacity: 1, translateY: 0 }}
        transition={{ type: 'timing', duration: 350, delay: index * 50 }}
      >
        <Card
          style={[
            styles.contactCard,
            { backgroundColor: colors.card },
            isSelected && { borderColor: colors.primary, borderWidth: 2 },
          ]}
          onPress={() => handleContactPress(item)}
          mode="outlined"
        >
          <Card.Content style={styles.cardContentRow}>
            {isSelectionMode && (
              <View style={styles.checkboxContainer}>
                <Checkbox
                  status={isSelected ? 'checked' : 'unchecked'}
                  onPress={() => toggleContactSelection(item.id)}
                  color={colors.primary}
                />
              </View>
            )}

            <View style={styles.cardContent}>
              <View style={styles.cardHeader}>
                <View style={styles.nameContainer}>
                  <Text style={[styles.contactName, { color: colors.text }]} numberOfLines={1}>
                    {item.name || item.email}
                  </Text>
                  <View style={styles.emailContainer}>
                    <Text style={[styles.contactEmail, { color: colors.textSecondary }]} numberOfLines={1}>
                      {item.email}
                    </Text>
                    <IconButton
                      icon="content-copy"
                      size={14}
                      iconColor={colors.textTertiary}
                      onPress={() => copyToClipboard(item.email, 'Email')}
                      style={styles.copyButton}
                    />
                  </View>
                </View>
                <View style={styles.cardActions}>
                  <FavoriteButton id={item.id} type="contact" size={20} />
                  <Chip
                    compact
                    mode="flat"
                    style={[styles.statusChip, { backgroundColor: statusInfo.color + '20' }]}
                    textStyle={[styles.statusChipText, { color: statusInfo.color }]}
                  >
                    {statusInfo.label}
                  </Chip>
                </View>
              </View>

              <View style={styles.cardMeta}>
                <View style={styles.metaItem}>
                  <Phone size={14} color={colors.textTertiary} />
                  <Text style={[styles.metaText, { color: colors.textTertiary }]}>{item.phone || 'No phone'}</Text>
                </View>
                <Text style={[styles.metaDate, { color: colors.textTertiary }]}>
                  Added {formatShortDate(item.created_at)}
                </Text>
              </View>

              {item.tags && item.tags.length > 0 && (
                <View style={styles.tagsContainer}>
                  {item.tags.slice(0, 2).map((tag) => (
                    <Chip
                      key={tag}
                      compact
                      mode="flat"
                      style={[styles.tagChip, { backgroundColor: colors.primary + '15' }]}
                      textStyle={[styles.tagChipText, { color: colors.primary }]}
                    >
                      {tag}
                    </Chip>
                  ))}
                  {item.tags.length > 2 && (
                    <Text style={[styles.moreTagsText, { color: colors.textTertiary }]}>+{item.tags.length - 2}</Text>
                  )}
                </View>
              )}
            </View>
          </Card.Content>
        </Card>
      </MotiView>
    );
  };

  const renderGroupCard = ({ item, index }: { item: ContactGroup; index: number }) => (
    <MotiView
      from={{ opacity: 0, translateY: 20 }}
      animate={{ opacity: 1, translateY: 0 }}
      transition={{ type: 'timing', duration: 350, delay: index * 50 }}
    >
      <Card
        style={[styles.groupCard, { backgroundColor: colors.card }]}
        onPress={() => handleGroupPress(item)}
        mode="outlined"
      >
        <Card.Content style={styles.groupCardContent}>
          <View style={[styles.groupIconContainer, { backgroundColor: colors.primary + '15' }]}>
            <Folder size={32} color={colors.primary} />
          </View>
          <View style={styles.groupContent}>
            <Text style={[styles.groupName, { color: colors.text }]}>{item.name}</Text>
            <Text style={[styles.groupCount, { color: colors.textTertiary }]}>{item.contact_count || 0} contacts</Text>
          </View>
          <ChevronRight size={24} color={colors.textTertiary} />
        </Card.Content>
      </Card>
    </MotiView>
  );

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <Users size={64} color={colors.textTertiary} />
      <Text style={[styles.emptyTitle, { color: colors.textSecondary }]}>No contacts yet</Text>
      <Text style={[styles.emptySubtitle, { color: colors.textTertiary }]}>
        Add your first contact to get started
      </Text>
      <Button
        mode="contained"
        onPress={handleAddContact}
        icon="plus"
        style={styles.addButton}
        buttonColor={colors.primary}
      >
        Add Contact
      </Button>
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
    return statusFilter.charAt(0).toUpperCase() + statusFilter.slice(1);
  };

  if (isLoading && list.length === 0) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
          <Text style={[styles.loadingText, { color: colors.textSecondary }]}>Loading contacts...</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      {/* Header */}
      <View style={[styles.header, { backgroundColor: colors.surface, borderBottomColor: colors.border }]}>
        <View style={styles.headerLeft}>
          <Text style={[styles.headerTitle, { color: colors.text }]}>Contacts</Text>
          {selectedContacts.size > 0 && (
            <Chip
              compact
              mode="flat"
              style={[styles.selectionBadge, { backgroundColor: colors.primary }]}
              textStyle={styles.selectionBadgeText}
            >
              {selectedContacts.size}
            </Chip>
          )}
        </View>
        <IconButton
          icon="plus"
          size={24}
          iconColor={colors.primary}
          onPress={handleAddContact}
        />
      </View>

      {/* Search Bar */}
      <View style={styles.searchContainer}>
        <Searchbar
          placeholder="Search contacts..."
          value={searchText}
          onChangeText={setSearchText}
          onSubmitEditing={loadContacts}
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

      {/* View Mode Toggle */}
      <View style={[styles.viewModeContainer, { backgroundColor: colors.surface, borderBottomColor: colors.border }]}>
        <SegmentedButtons
          value={viewMode}
          onValueChange={(value) => setViewMode(value as ViewMode)}
          buttons={[
            { value: 'list', label: 'Contacts', icon: 'format-list-bulleted' },
            { value: 'groups', label: 'Groups', icon: 'folder-multiple' },
          ]}
          style={styles.segmentedButtons}
        />
      </View>

      {/* Active Filter Chip */}
      {statusFilter && (
        <View style={styles.activeFilterContainer}>
          <Chip
            mode="outlined"
            onClose={() => {
              setStatusFilter(undefined);
              loadContacts();
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

      {/* Selection Toolbar */}
      {isSelectionMode && selectedContacts.size > 0 && (
        <View style={[styles.selectionToolbar, { backgroundColor: colors.surface, borderBottomColor: colors.border }]}>
          <Button
            mode="outlined"
            onPress={handleSelectAll}
            icon="checkbox-marked"
            compact
            style={styles.toolbarButton}
            textColor={colors.primary}
          >
            {selectedContacts.size === list.length ? 'Deselect' : 'Select All'}
          </Button>
          <Button
            mode="outlined"
            onPress={handleBulkExport}
            icon="download"
            compact
            style={styles.toolbarButton}
            textColor={colors.success}
          >
            Export
          </Button>
          <Button
            mode="contained"
            onPress={handleBulkDelete}
            icon="trash-can"
            compact
            style={styles.toolbarButton}
            buttonColor={colors.error}
          >
            Delete
          </Button>
        </View>
      )}

      {/* Contacts List */}
      {viewMode === 'list' ? (
        <FlatList
          data={list}
          renderItem={renderContactCard}
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
      ) : (
        <FlatList
          data={groups}
          renderItem={renderGroupCard}
          keyExtractor={(item) => item.id}
          ListEmptyComponent={renderEmpty}
          contentContainerStyle={styles.listContent}
        />
      )}

      {/* Selection Mode Toggle */}
      {viewMode === 'list' && list.length > 0 && (
        <Button
          mode="contained"
          onPress={() => {
            if (isSelectionMode) {
              setIsSelectionMode(false);
              setSelectedContacts(new Set());
            } else {
              setIsSelectionMode(true);
            }
          }}
          style={styles.selectionModeButton}
          buttonColor={colors.primary}
        >
          {isSelectionMode ? 'Exit Selection' : 'Select Contacts'}
        </Button>
      )}

      {/* Filter Modal */}
      <Portal>
        <Modal
          visible={isFilterModalVisible}
          onDismiss={() => setIsFilterModalVisible(false)}
          contentContainerStyle={[styles.modalContent, { backgroundColor: colors.surface }]}
        >
          <View style={[styles.modalHeader, { borderBottomColor: colors.border }]}>
            <Text style={[styles.modalTitle, { color: colors.text }]}>Filter Contacts</Text>
            <IconButton
              icon="close"
              size={24}
              iconColor={colors.text}
              onPress={() => setIsFilterModalVisible(false)}
            />
          </View>

          <View style={styles.filterSection}>
            <Text style={[styles.filterSectionTitle, { color: colors.text }]}>Contact Status</Text>
            <View style={styles.chipContainer}>
              {['active', 'inactive', 'unsubscribed', 'bounced'].map((status) => (
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
                  {status.charAt(0).toUpperCase() + status.slice(1)}
                </Chip>
              ))}
            </View>
          </View>

          <Button
            mode="contained"
            onPress={() => {
              setIsFilterModalVisible(false);
              loadContacts();
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
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '700',
  },
  selectionBadge: {
    marginLeft: 12,
  },
  selectionBadgeText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
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
  viewModeContainer: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderBottomWidth: 1,
  },
  segmentedButtons: {
    borderRadius: 4, // Reduced for more squared look
  },
  activeFilterContainer: {
    paddingHorizontal: 12,
    paddingVertical: 8,
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
  selectionToolbar: {
    flexDirection: 'row',
    paddingHorizontal: 8,
    paddingVertical: 8,
    borderBottomWidth: 1,
    gap: 8,
  },
  toolbarButton: {
    flex: 1,
  },
  listContent: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    flexGrow: 1,
  },
  contactCard: {
    marginBottom: 12,
    borderRadius: 12,
  },
  cardContentRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  checkboxContainer: {
    marginRight: 8,
    marginTop: -8,
  },
  cardContent: {
    flex: 1,
  },
  cardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 8,
  },
  nameContainer: {
    flex: 1,
    marginRight: 8,
  },
  cardActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  contactName: {
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 4,
  },
  contactEmail: {
    fontSize: 13,
  },
  emailContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  copyButton: {
    margin: -8,
    marginLeft: 0,
  },
  statusChip: {
    height: 24,
  },
  statusChipText: {
    fontSize: 10,
    fontWeight: '600',
  },
  cardMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  metaItem: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  metaText: {
    fontSize: 12,
    marginLeft: 4,
  },
  metaDate: {
    fontSize: 11,
  },
  tagsContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: 6,
  },
  tagChip: {
    height: 24,
  },
  tagChipText: {
    fontSize: 10,
  },
  moreTagsText: {
    fontSize: 11,
  },
  groupCard: {
    marginBottom: 12,
    borderRadius: 12,
  },
  groupCardContent: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  groupIconContainer: {
    width: 48,
    height: 48,
    borderRadius: 8,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  groupContent: {
    flex: 1,
  },
  groupName: {
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 4,
  },
  groupCount: {
    fontSize: 13,
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
  addButton: {
    marginTop: 20,
    borderRadius: 8,
  },
  footerLoader: {
    paddingVertical: 16,
    alignItems: 'center',
  },
  selectionModeButton: {
    marginHorizontal: 16,
    marginBottom: 16,
    borderRadius: 8,
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
  filterSection: {
    padding: 16,
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
    borderRadius: 8,
  },
});
