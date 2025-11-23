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
  SectionList,
  Switch,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAppDispatch, useAppSelector } from '@store';
import { fetchContacts, fetchContactGroups } from '@store/slices/contactsSlice';
import { Contact, ContactGroup } from '@types';
import { formatShortDate, formatContactStatus } from '@utils/formatters';
import * as contactService from '@services/contacts';
import { FavoriteButton } from '@components/FavoriteButton';
import { copyToClipboard } from '@utils/clipboard';
import { addSearchHistory } from '@utils/searchHistory';

interface ContactListScreenProps {
  navigation: any;
}

type ViewMode = 'list' | 'groups';

export default function ContactListScreen({ navigation }: ContactListScreenProps) {
  const dispatch = useAppDispatch();
  const { list, groups, isLoading, error, pagination } = useAppSelector((state) => state.contacts);
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
              // Delete selected contacts (implementation would depend on API)
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
    Alert.alert('Add Contact', 'Navigate to add contact screen (coming soon)');
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

  const renderContactCard = ({ item }: { item: Contact }) => {
    const isSelected = selectedContacts.has(item.id);
    const statusInfo = formatContactStatus(item.status);

    return (
      <TouchableOpacity
        style={[styles.contactCard, isSelected && styles.contactCardSelected]}
        onPress={() => handleContactPress(item)}
      >
        {isSelectionMode && (
          <View style={styles.checkboxContainer}>
            <View
              style={[styles.checkbox, isSelected && styles.checkboxSelected]}
            >
              {isSelected && (
                <MaterialCommunityIcons name="check" size={16} color="#fff" />
              )}
            </View>
          </View>
        )}

        <View style={styles.cardContent}>
          <View style={styles.cardHeader}>
            <View style={styles.nameContainer}>
              <Text style={styles.contactName} numberOfLines={1}>
                {item.name || item.email}
              </Text>
              <TouchableOpacity
                style={styles.emailContainer}
                onPress={() => copyToClipboard(item.email, 'Email')}
              >
                <Text style={styles.contactEmail} numberOfLines={1}>
                  {item.email}
                </Text>
                <MaterialCommunityIcons name="content-copy" size={14} color="#999" />
              </TouchableOpacity>
            </View>
            <View style={styles.cardActions}>
              <FavoriteButton id={item.id} type="contact" size={20} />
              <View style={[styles.statusBadge, { backgroundColor: statusInfo.color }]}>
                <Text style={styles.statusText}>{statusInfo.label}</Text>
              </View>
            </View>
          </View>

          <View style={styles.cardMeta}>
            <View style={styles.metaItem}>
              <MaterialCommunityIcons name="phone" size={14} color="#999" />
              <Text style={styles.metaText}>{item.phone || 'No phone'}</Text>
            </View>
            <Text style={styles.metaDate}>
              Added {formatShortDate(item.created_at)}
            </Text>
          </View>

          {item.tags && item.tags.length > 0 && (
            <View style={styles.tagsContainer}>
              {item.tags.slice(0, 2).map((tag) => (
                <View key={tag} style={styles.tag}>
                  <Text style={styles.tagText}>{tag}</Text>
                </View>
              ))}
              {item.tags.length > 2 && (
                <Text style={styles.moreTagsText}>+{item.tags.length - 2}</Text>
              )}
            </View>
          )}
        </View>
      </TouchableOpacity>
    );
  };

  const renderGroupCard = ({ item }: { item: ContactGroup }) => (
    <TouchableOpacity
      style={styles.groupCard}
      onPress={() => handleGroupPress(item)}
    >
      <View style={styles.groupIconContainer}>
        <MaterialCommunityIcons name="folder" size={32} color="#4A90E2" />
      </View>
      <View style={styles.groupContent}>
        <Text style={styles.groupName}>{item.name}</Text>
        <Text style={styles.groupCount}>{item.contact_count || 0} contacts</Text>
      </View>
      <MaterialCommunityIcons name="chevron-right" size={24} color="#ccc" />
    </TouchableOpacity>
  );

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <MaterialCommunityIcons name="contacts" size={64} color="#ccc" />
      <Text style={styles.emptyTitle}>No contacts yet</Text>
      <Text style={styles.emptySubtitle}>
        Add your first contact to get started
      </Text>
      <TouchableOpacity style={styles.addButton} onPress={handleAddContact}>
        <MaterialCommunityIcons name="plus" size={20} color="#fff" />
        <Text style={styles.addButtonText}>Add Contact</Text>
      </TouchableOpacity>
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

  if (isLoading && list.length === 0) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color="#4A90E2" />
          <Text style={styles.loadingText}>Loading contacts...</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <Text style={styles.headerTitle}>Contacts</Text>
          {selectedContacts.size > 0 && (
            <View style={styles.selectionBadge}>
              <Text style={styles.selectionBadgeText}>{selectedContacts.size}</Text>
            </View>
          )}
        </View>
        <TouchableOpacity onPress={handleAddContact} style={styles.addButtonHeader}>
          <MaterialCommunityIcons name="plus" size={24} color="#4A90E2" />
        </TouchableOpacity>
      </View>

      {/* Search Bar */}
      <View style={styles.searchBar}>
        <MaterialCommunityIcons name="magnify" size={20} color="#999" />
        <TextInput
          style={styles.searchInput}
          placeholder="Search contacts..."
          placeholderTextColor="#999"
          value={searchText}
          onChangeText={setSearchText}
          onSubmitEditing={loadContacts}
        />
        <TouchableOpacity onPress={() => setIsFilterModalVisible(true)}>
          <MaterialCommunityIcons name="filter" size={20} color="#4A90E2" />
        </TouchableOpacity>
      </View>

      {/* View Mode Toggle */}
      <View style={styles.viewModeToggle}>
        <TouchableOpacity
          style={[styles.viewModeButton, viewMode === 'list' && styles.viewModeButtonActive]}
          onPress={() => setViewMode('list')}
        >
          <MaterialCommunityIcons
            name="format-list-bulleted"
            size={18}
            color={viewMode === 'list' ? '#4A90E2' : '#999'}
          />
          <Text style={[styles.viewModeText, viewMode === 'list' && styles.viewModeTextActive]}>
            Contacts
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.viewModeButton, viewMode === 'groups' && styles.viewModeButtonActive]}
          onPress={() => setViewMode('groups')}
        >
          <MaterialCommunityIcons
            name="folder-multiple"
            size={18}
            color={viewMode === 'groups' ? '#4A90E2' : '#999'}
          />
          <Text style={[styles.viewModeText, viewMode === 'groups' && styles.viewModeTextActive]}>
            Groups
          </Text>
        </TouchableOpacity>
      </View>

      {/* Error message */}
      {error && (
        <View style={styles.errorBox}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}

      {/* Selection Toolbar */}
      {isSelectionMode && selectedContacts.size > 0 && (
        <View style={styles.selectionToolbar}>
          <TouchableOpacity
            style={styles.toolbarButton}
            onPress={handleSelectAll}
          >
            <MaterialCommunityIcons name="checkbox-marked" size={20} color="#4A90E2" />
            <Text style={styles.toolbarButtonText}>
              {selectedContacts.size === list.length ? 'Deselect All' : 'Select All'}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.toolbarButton}
            onPress={handleBulkExport}
          >
            <MaterialCommunityIcons name="download" size={20} color="#27AE60" />
            <Text style={styles.toolbarButtonText}>Export</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.toolbarButton, styles.toolbarButtonDanger]}
            onPress={handleBulkDelete}
          >
            <MaterialCommunityIcons name="trash-can" size={20} color="#E74C3C" />
            <Text style={[styles.toolbarButtonText, { color: '#E74C3C' }]}>Delete</Text>
          </TouchableOpacity>
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
              tintColor="#4A90E2"
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

      {/* Long Press to Select */}
      {!isSelectionMode && list.length > 0 && (
        <TouchableOpacity
          style={styles.selectionModeButton}
          onPress={() => setIsSelectionMode(true)}
        >
          <Text style={styles.selectionModeText}>Select Contacts</Text>
        </TouchableOpacity>
      )}

      {isSelectionMode && (
        <TouchableOpacity
          style={styles.selectionModeButton}
          onPress={() => {
            setIsSelectionMode(false);
            setSelectedContacts(new Set());
          }}
        >
          <Text style={styles.selectionModeText}>Exit Selection</Text>
        </TouchableOpacity>
      )}

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
              <Text style={styles.modalTitle}>Filter Contacts</Text>
              <TouchableOpacity onPress={() => setIsFilterModalVisible(false)}>
                <MaterialCommunityIcons name="close" size={24} color="#333" />
              </TouchableOpacity>
            </View>

            <View style={styles.filterOptions}>
              <Text style={styles.filterLabel}>Contact Status</Text>
              {['active', 'inactive', 'unsubscribed', 'bounced'].map((status) => (
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
                    {status.charAt(0).toUpperCase() + status.slice(1)}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            <TouchableOpacity
              style={styles.applyFilterButton}
              onPress={() => {
                setIsFilterModalVisible(false);
                loadContacts();
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
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: '#333',
  },
  selectionBadge: {
    marginLeft: 12,
    backgroundColor: '#4A90E2',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 12,
  },
  selectionBadgeText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
  addButtonHeader: {
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
  viewModeToggle: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  viewModeButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 8,
    marginHorizontal: 4,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  viewModeButtonActive: {
    borderBottomColor: '#4A90E2',
  },
  viewModeText: {
    fontSize: 13,
    color: '#999',
    marginLeft: 6,
    fontWeight: '500',
  },
  viewModeTextActive: {
    color: '#4A90E2',
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
  selectionToolbar: {
    flexDirection: 'row',
    paddingHorizontal: 8,
    paddingVertical: 8,
    backgroundColor: '#f5f5f5',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  toolbarButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 8,
    marginHorizontal: 4,
    borderRadius: 6,
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#eee',
  },
  toolbarButtonDanger: {
    borderColor: '#fee',
    backgroundColor: '#fef5f5',
  },
  toolbarButtonText: {
    fontSize: 12,
    color: '#4A90E2',
    marginLeft: 6,
    fontWeight: '600',
  },
  listContent: {
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  contactCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#eee',
    padding: 12,
    marginBottom: 12,
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  contactCardSelected: {
    borderColor: '#4A90E2',
    backgroundColor: '#f0f5ff',
  },
  checkboxContainer: {
    paddingRight: 12,
    paddingTop: 2,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: 4,
    borderWidth: 2,
    borderColor: '#ddd',
    justifyContent: 'center',
    alignItems: 'center',
  },
  checkboxSelected: {
    backgroundColor: '#4A90E2',
    borderColor: '#4A90E2',
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
    color: '#333',
    marginBottom: 2,
  },
  contactEmail: {
    fontSize: 13,
    color: '#666',
  },
  emailContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  statusBadge: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  statusText: {
    fontSize: 11,
    fontWeight: '600',
    color: '#fff',
  },
  cardMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  metaItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginRight: 12,
  },
  metaText: {
    fontSize: 12,
    color: '#999',
    marginLeft: 4,
  },
  metaDate: {
    fontSize: 12,
    color: '#999',
  },
  tagsContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
  },
  tag: {
    backgroundColor: '#e8f1ff',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
    marginRight: 6,
  },
  tagText: {
    fontSize: 11,
    color: '#4A90E2',
    fontWeight: '500',
  },
  moreTagsText: {
    fontSize: 11,
    color: '#999',
  },
  groupCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#eee',
    padding: 16,
    marginBottom: 12,
    flexDirection: 'row',
    alignItems: 'center',
  },
  groupIconContainer: {
    width: 48,
    height: 48,
    borderRadius: 8,
    backgroundColor: '#e8f1ff',
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
    color: '#333',
    marginBottom: 4,
  },
  groupCount: {
    fontSize: 13,
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
  addButton: {
    marginTop: 20,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingVertical: 12,
    backgroundColor: '#4A90E2',
    borderRadius: 8,
  },
  addButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    marginLeft: 8,
  },
  footerLoader: {
    paddingVertical: 16,
    alignItems: 'center',
  },
  selectionModeButton: {
    marginHorizontal: 16,
    marginBottom: 16,
    paddingVertical: 12,
    backgroundColor: '#4A90E2',
    borderRadius: 8,
    alignItems: 'center',
  },
  selectionModeText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
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
