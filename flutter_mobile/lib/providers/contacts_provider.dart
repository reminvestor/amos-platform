import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/services/contacts_service.dart';

/// State for contacts management
class ContactsState {
  final List<Contact> contacts;
  final Contact? selectedContact;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int currentPage;
  final bool hasMore;
  final String? searchQuery;
  final String? filterGroupId;
  final ContactStatus? filterStatus;

  const ContactsState({
    this.contacts = const [],
    this.selectedContact,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.currentPage = 1,
    this.hasMore = true,
    this.searchQuery,
    this.filterGroupId,
    this.filterStatus,
  });

  ContactsState copyWith({
    List<Contact>? contacts,
    Contact? selectedContact,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    int? currentPage,
    bool? hasMore,
    String? searchQuery,
    String? filterGroupId,
    ContactStatus? filterStatus,
    bool clearSelectedContact = false,
    bool clearError = false,
    bool clearSearchQuery = false,
    bool clearFilterGroupId = false,
    bool clearFilterStatus = false,
  }) {
    return ContactsState(
      contacts: contacts ?? this.contacts,
      selectedContact: clearSelectedContact ? null : (selectedContact ?? this.selectedContact),
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      filterGroupId: clearFilterGroupId ? null : (filterGroupId ?? this.filterGroupId),
      filterStatus: clearFilterStatus ? null : (filterStatus ?? this.filterStatus),
    );
  }

  /// Get contacts filtered by status
  List<Contact> get activeContacts =>
      contacts.where((c) => c.status == ContactStatus.active).toList();

  List<Contact> get inactiveContacts =>
      contacts.where((c) => c.status == ContactStatus.inactive).toList();

  List<Contact> get unsubscribedContacts =>
      contacts.where((c) => c.status == ContactStatus.unsubscribed).toList();

  /// Search contacts locally by name or email
  List<Contact> searchLocally(String query) {
    if (query.isEmpty) return contacts;
    final lowerQuery = query.toLowerCase();
    return contacts.where((c) {
      final name = c.displayName.toLowerCase();
      final email = c.email.toLowerCase();
      return name.contains(lowerQuery) || email.contains(lowerQuery);
    }).toList();
  }

  /// Check if there are any contacts
  bool get isEmpty => contacts.isEmpty;

  /// Get total count
  int get totalCount => contacts.length;

  /// Get active contact count
  int get activeCount => activeContacts.length;
}

/// Notifier for contacts state management
class ContactsNotifier extends Notifier<ContactsState> {
  late final ContactsService _contactsService;

  @override
  ContactsState build() {
    _contactsService = ref.read(contactsServiceProvider);
    return const ContactsState();
  }

  /// Load contacts from API
  Future<void> loadContacts({
    String? search,
    String? groupId,
    bool refresh = false,
  }) async {
    if (state.isLoading) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      searchQuery: search,
      filterGroupId: groupId,
      currentPage: refresh ? 1 : state.currentPage,
    );

    try {
      final contacts = await _contactsService.getContacts(
        search: search,
        groupId: groupId,
        page: refresh ? 1 : state.currentPage,
      );

      state = state.copyWith(
        contacts: refresh ? contacts : [...state.contacts, ...contacts],
        isLoading: false,
        hasMore: contacts.length >= 20,
        currentPage: refresh ? 1 : state.currentPage,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load more contacts (pagination)
  Future<void> loadMoreContacts() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final contacts = await _contactsService.getContacts(
        search: state.searchQuery,
        groupId: state.filterGroupId,
        page: state.currentPage + 1,
      );

      state = state.copyWith(
        contacts: [...state.contacts, ...contacts],
        isLoadingMore: false,
        hasMore: contacts.length >= 20,
        currentPage: state.currentPage + 1,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  /// Select a contact for detail view
  Future<void> selectContact(String id) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final contact = await _contactsService.getContact(id);
      state = state.copyWith(
        selectedContact: contact,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Clear selected contact
  void clearSelectedContact() {
    state = state.copyWith(clearSelectedContact: true);
  }

  /// Set contacts directly (for testing or external updates)
  void setContacts(List<Contact> contacts) {
    state = state.copyWith(contacts: contacts);
  }

  /// Add a contact to the list
  void addContact(Contact contact) {
    state = state.copyWith(contacts: [contact, ...state.contacts]);
  }

  /// Update a contact in the list
  void updateContact(Contact contact) {
    final index = state.contacts.indexWhere((c) => c.id == contact.id);
    if (index != -1) {
      final updatedList = [...state.contacts];
      updatedList[index] = contact;
      state = state.copyWith(
        contacts: updatedList,
        selectedContact: state.selectedContact?.id == contact.id
            ? contact
            : state.selectedContact,
      );
    }
  }

  /// Remove a contact from the list
  void removeContact(String id) {
    state = state.copyWith(
      contacts: state.contacts.where((c) => c.id != id).toList(),
      clearSelectedContact: state.selectedContact?.id == id,
    );
  }

  /// Filter contacts by status
  void filterByStatus(ContactStatus? status) {
    state = state.copyWith(filterStatus: status);
  }

  /// Clear all filters
  void clearFilters() {
    state = state.copyWith(
      clearSearchQuery: true,
      clearFilterGroupId: true,
      clearFilterStatus: true,
    );
  }

  /// Clear all contacts
  void clear() {
    state = const ContactsState();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Set loading state
  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  /// Set error state
  void setError(String error) {
    state = state.copyWith(error: error);
  }
}

// Service provider
final contactsServiceProvider = Provider<ContactsService>((ref) => ContactsService());

// State provider
final contactsStateProvider = NotifierProvider<ContactsNotifier, ContactsState>(
  ContactsNotifier.new,
);

// Convenience providers
final contactsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(contactsStateProvider).isLoading;
});

final contactsErrorProvider = Provider<String?>((ref) {
  return ref.watch(contactsStateProvider).error;
});

final selectedContactProvider = Provider<Contact?>((ref) {
  return ref.watch(contactsStateProvider).selectedContact;
});

final activeContactsProvider = Provider<List<Contact>>((ref) {
  return ref.watch(contactsStateProvider).activeContacts;
});

final inactiveContactsProvider = Provider<List<Contact>>((ref) {
  return ref.watch(contactsStateProvider).inactiveContacts;
});

final unsubscribedContactsProvider = Provider<List<Contact>>((ref) {
  return ref.watch(contactsStateProvider).unsubscribedContacts;
});

final contactsCountProvider = Provider<int>((ref) {
  return ref.watch(contactsStateProvider).totalCount;
});

final activeContactsCountProvider = Provider<int>((ref) {
  return ref.watch(contactsStateProvider).activeCount;
});
