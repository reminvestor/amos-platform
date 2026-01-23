import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/providers/contacts_provider.dart';

void main() {
  // Test contact helper
  Contact createTestContact({
    String id = '1',
    String email = 'test@example.com',
    ContactStatus status = ContactStatus.active,
    String? name,
    String? firstName,
    String? lastName,
    String? phone,
    String? company,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Contact(
      id: id,
      email: email,
      status: status,
      name: name,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      company: company,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  group('ContactsState', () {
    test('default state has correct initial values', () {
      const state = ContactsState();

      expect(state.contacts, isEmpty);
      expect(state.selectedContact, isNull);
      expect(state.isLoading, isFalse);
      expect(state.isLoadingMore, isFalse);
      expect(state.error, isNull);
      expect(state.currentPage, equals(1));
      expect(state.hasMore, isTrue);
      expect(state.searchQuery, isNull);
      expect(state.filterGroupId, isNull);
      expect(state.filterStatus, isNull);
    });

    test('isEmpty returns true when contacts list is empty', () {
      const state = ContactsState();

      expect(state.isEmpty, isTrue);
    });

    test('isEmpty returns false when contacts exist', () {
      final contact = createTestContact();
      final state = ContactsState(contacts: [contact]);

      expect(state.isEmpty, isFalse);
    });

    test('totalCount returns correct count', () {
      final contacts = [
        createTestContact(id: '1'),
        createTestContact(id: '2'),
        createTestContact(id: '3'),
      ];
      final state = ContactsState(contacts: contacts);

      expect(state.totalCount, equals(3));
    });

    test('activeCount returns count of active contacts', () {
      final contacts = [
        createTestContact(id: '1', status: ContactStatus.active),
        createTestContact(id: '2', status: ContactStatus.inactive),
        createTestContact(id: '3', status: ContactStatus.active),
      ];
      final state = ContactsState(contacts: contacts);

      expect(state.activeCount, equals(2));
    });

    group('copyWith', () {
      test('updates contacts', () {
        const initial = ContactsState();
        final contacts = [createTestContact()];

        final modified = initial.copyWith(contacts: contacts);

        expect(modified.contacts.length, equals(1));
        expect(initial.contacts, isEmpty);
      });

      test('updates selectedContact', () {
        const initial = ContactsState();
        final contact = createTestContact();

        final modified = initial.copyWith(selectedContact: contact);

        expect(modified.selectedContact, equals(contact));
        expect(initial.selectedContact, isNull);
      });

      test('clears selectedContact when clearSelectedContact is true', () {
        final contact = createTestContact();
        final initial = ContactsState(selectedContact: contact);

        final modified = initial.copyWith(clearSelectedContact: true);

        expect(modified.selectedContact, isNull);
      });

      test('updates isLoading', () {
        const initial = ContactsState();

        final modified = initial.copyWith(isLoading: true);

        expect(modified.isLoading, isTrue);
        expect(initial.isLoading, isFalse);
      });

      test('updates isLoadingMore', () {
        const initial = ContactsState();

        final modified = initial.copyWith(isLoadingMore: true);

        expect(modified.isLoadingMore, isTrue);
        expect(initial.isLoadingMore, isFalse);
      });

      test('updates error', () {
        const initial = ContactsState();

        final modified = initial.copyWith(error: 'Test error');

        expect(modified.error, equals('Test error'));
        expect(initial.error, isNull);
      });

      test('clears error when clearError is true', () {
        const initial = ContactsState(error: 'Previous error');

        final modified = initial.copyWith(clearError: true);

        expect(modified.error, isNull);
      });

      test('updates currentPage', () {
        const initial = ContactsState();

        final modified = initial.copyWith(currentPage: 5);

        expect(modified.currentPage, equals(5));
        expect(initial.currentPage, equals(1));
      });

      test('updates hasMore', () {
        const initial = ContactsState();

        final modified = initial.copyWith(hasMore: false);

        expect(modified.hasMore, isFalse);
        expect(initial.hasMore, isTrue);
      });

      test('updates searchQuery', () {
        const initial = ContactsState();

        final modified = initial.copyWith(searchQuery: 'test');

        expect(modified.searchQuery, equals('test'));
        expect(initial.searchQuery, isNull);
      });

      test('clears searchQuery when clearSearchQuery is true', () {
        const initial = ContactsState(searchQuery: 'previous');

        final modified = initial.copyWith(clearSearchQuery: true);

        expect(modified.searchQuery, isNull);
      });

      test('updates filterGroupId', () {
        const initial = ContactsState();

        final modified = initial.copyWith(filterGroupId: 'group-1');

        expect(modified.filterGroupId, equals('group-1'));
        expect(initial.filterGroupId, isNull);
      });

      test('clears filterGroupId when clearFilterGroupId is true', () {
        const initial = ContactsState(filterGroupId: 'group-1');

        final modified = initial.copyWith(clearFilterGroupId: true);

        expect(modified.filterGroupId, isNull);
      });

      test('updates filterStatus', () {
        const initial = ContactsState();

        final modified = initial.copyWith(filterStatus: ContactStatus.active);

        expect(modified.filterStatus, equals(ContactStatus.active));
        expect(initial.filterStatus, isNull);
      });

      test('clears filterStatus when clearFilterStatus is true', () {
        const initial = ContactsState(filterStatus: ContactStatus.active);

        final modified = initial.copyWith(clearFilterStatus: true);

        expect(modified.filterStatus, isNull);
      });

      test('preserves unmodified values', () {
        final contact = createTestContact();
        final initial = ContactsState(
          contacts: [contact],
          selectedContact: contact,
          isLoading: true,
          currentPage: 3,
          hasMore: false,
          searchQuery: 'test',
          filterGroupId: 'group-1',
          filterStatus: ContactStatus.inactive,
        );

        final modified = initial.copyWith(isLoadingMore: true);

        expect(modified.contacts.length, equals(1));
        expect(modified.selectedContact, equals(contact));
        expect(modified.isLoading, isTrue);
        expect(modified.isLoadingMore, isTrue);
        expect(modified.currentPage, equals(3));
        expect(modified.hasMore, isFalse);
        expect(modified.searchQuery, equals('test'));
        expect(modified.filterGroupId, equals('group-1'));
        expect(modified.filterStatus, equals(ContactStatus.inactive));
      });
    });

    group('filtered contacts', () {
      test('activeContacts returns only active contacts', () {
        final contacts = [
          createTestContact(id: '1', status: ContactStatus.active),
          createTestContact(id: '2', status: ContactStatus.inactive),
          createTestContact(id: '3', status: ContactStatus.active),
        ];
        final state = ContactsState(contacts: contacts);

        expect(state.activeContacts.length, equals(2));
        expect(state.activeContacts.every((c) => c.status == ContactStatus.active), isTrue);
      });

      test('inactiveContacts returns only inactive contacts', () {
        final contacts = [
          createTestContact(id: '1', status: ContactStatus.active),
          createTestContact(id: '2', status: ContactStatus.inactive),
          createTestContact(id: '3', status: ContactStatus.inactive),
        ];
        final state = ContactsState(contacts: contacts);

        expect(state.inactiveContacts.length, equals(2));
        expect(state.inactiveContacts.every((c) => c.status == ContactStatus.inactive), isTrue);
      });

      test('unsubscribedContacts returns only unsubscribed contacts', () {
        final contacts = [
          createTestContact(id: '1', status: ContactStatus.unsubscribed),
          createTestContact(id: '2', status: ContactStatus.active),
          createTestContact(id: '3', status: ContactStatus.unsubscribed),
        ];
        final state = ContactsState(contacts: contacts);

        expect(state.unsubscribedContacts.length, equals(2));
        expect(state.unsubscribedContacts.every((c) => c.status == ContactStatus.unsubscribed), isTrue);
      });

      test('filtered lists return empty when no matching contacts', () {
        final contacts = [
          createTestContact(id: '1', status: ContactStatus.active),
        ];
        final state = ContactsState(contacts: contacts);

        expect(state.inactiveContacts, isEmpty);
        expect(state.unsubscribedContacts, isEmpty);
      });
    });

    group('searchLocally', () {
      test('returns all contacts when query is empty', () {
        final contacts = [
          createTestContact(id: '1', name: 'Alice', email: 'alice@test.com'),
          createTestContact(id: '2', name: 'Bob', email: 'bob@test.com'),
        ];
        final state = ContactsState(contacts: contacts);

        final results = state.searchLocally('');

        expect(results.length, equals(2));
      });

      test('filters contacts by name match', () {
        final contacts = [
          createTestContact(id: '1', name: 'Alice Smith', email: 'alice@test.com'),
          createTestContact(id: '2', name: 'Bob Jones', email: 'bob@test.com'),
          createTestContact(id: '3', name: 'Charlie Smith', email: 'charlie@test.com'),
        ];
        final state = ContactsState(contacts: contacts);

        final results = state.searchLocally('Smith');

        expect(results.length, equals(2));
        expect(results.any((c) => c.name == 'Alice Smith'), isTrue);
        expect(results.any((c) => c.name == 'Charlie Smith'), isTrue);
      });

      test('filters contacts by email match', () {
        final contacts = [
          createTestContact(id: '1', name: 'Alice', email: 'alice@company.com'),
          createTestContact(id: '2', name: 'Bob', email: 'bob@test.com'),
          createTestContact(id: '3', name: 'Charlie', email: 'charlie@company.com'),
        ];
        final state = ContactsState(contacts: contacts);

        final results = state.searchLocally('company');

        expect(results.length, equals(2));
        expect(results.any((c) => c.email == 'alice@company.com'), isTrue);
        expect(results.any((c) => c.email == 'charlie@company.com'), isTrue);
      });

      test('search is case insensitive', () {
        final contacts = [
          createTestContact(id: '1', name: 'Alice', email: 'alice@test.com'),
          createTestContact(id: '2', name: 'ALICE', email: 'ALICE@test.com'),
        ];
        final state = ContactsState(contacts: contacts);

        final results = state.searchLocally('alice');

        expect(results.length, equals(2));
      });

      test('returns empty list when no matches', () {
        final contacts = [
          createTestContact(id: '1', name: 'Alice', email: 'alice@test.com'),
          createTestContact(id: '2', name: 'Bob', email: 'bob@test.com'),
        ];
        final state = ContactsState(contacts: contacts);

        final results = state.searchLocally('Charlie');

        expect(results, isEmpty);
      });
    });
  });

  group('ContactsNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is empty ContactsState', () {
      final state = container.read(contactsStateProvider);

      expect(state.contacts, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('setContacts updates contacts list', () {
      final contacts = [
        createTestContact(id: '1'),
        createTestContact(id: '2'),
      ];

      container.read(contactsStateProvider.notifier).setContacts(contacts);

      final state = container.read(contactsStateProvider);
      expect(state.contacts.length, equals(2));
    });

    test('addContact prepends contact to list', () {
      final contact1 = createTestContact(id: '1', name: 'First');
      final contact2 = createTestContact(id: '2', name: 'Second');

      final notifier = container.read(contactsStateProvider.notifier);
      notifier.setContacts([contact1]);
      notifier.addContact(contact2);

      final state = container.read(contactsStateProvider);
      expect(state.contacts.length, equals(2));
      expect(state.contacts.first.id, equals('2'));
    });

    test('updateContact updates existing contact by id', () {
      final contact = createTestContact(id: '1', name: 'Original');
      final updated = createTestContact(id: '1', name: 'Updated');

      final notifier = container.read(contactsStateProvider.notifier);
      notifier.setContacts([contact]);
      notifier.updateContact(updated);

      final state = container.read(contactsStateProvider);
      expect(state.contacts.first.name, equals('Updated'));
    });

    test('updateContact does nothing when id not found', () {
      final contact = createTestContact(id: '1', name: 'Original');
      final nonExistent = createTestContact(id: '999', name: 'Nonexistent');

      final notifier = container.read(contactsStateProvider.notifier);
      notifier.setContacts([contact]);
      notifier.updateContact(nonExistent);

      final state = container.read(contactsStateProvider);
      expect(state.contacts.length, equals(1));
      expect(state.contacts.first.name, equals('Original'));
    });

    test('removeContact removes contact by id', () {
      final contacts = [
        createTestContact(id: '1'),
        createTestContact(id: '2'),
      ];

      final notifier = container.read(contactsStateProvider.notifier);
      notifier.setContacts(contacts);
      notifier.removeContact('1');

      final state = container.read(contactsStateProvider);
      expect(state.contacts.length, equals(1));
      expect(state.contacts.first.id, equals('2'));
    });

    test('removeContact does nothing when id not found', () {
      final contact = createTestContact(id: '1');

      final notifier = container.read(contactsStateProvider.notifier);
      notifier.setContacts([contact]);
      notifier.removeContact('999');

      final state = container.read(contactsStateProvider);
      expect(state.contacts.length, equals(1));
    });

    test('clearSelectedContact clears the selected contact', () {
      container.read(contactsStateProvider.notifier).clearSelectedContact();

      final state = container.read(contactsStateProvider);
      expect(state.selectedContact, isNull);
    });

    test('filterByStatus sets the filter status', () {
      container.read(contactsStateProvider.notifier).filterByStatus(ContactStatus.active);

      final state = container.read(contactsStateProvider);
      expect(state.filterStatus, equals(ContactStatus.active));
    });

    test('clearFilters clears all filter parameters', () {
      final notifier = container.read(contactsStateProvider.notifier);

      // Set some filters first
      final initialState = container.read(contactsStateProvider);
      final stateWithFilters = initialState.copyWith(
        searchQuery: 'test',
        filterGroupId: 'group-1',
        filterStatus: ContactStatus.active,
      );

      // Clear filters
      notifier.clearFilters();

      final state = container.read(contactsStateProvider);
      expect(state.searchQuery, isNull);
      expect(state.filterGroupId, isNull);
      expect(state.filterStatus, isNull);
    });

    test('clear resets state to initial values', () {
      final contact = createTestContact();

      final notifier = container.read(contactsStateProvider.notifier);
      notifier.setContacts([contact]);
      notifier.clear();

      final state = container.read(contactsStateProvider);
      expect(state.contacts, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.currentPage, equals(1));
    });

    test('clearError clears the error state', () {
      final notifier = container.read(contactsStateProvider.notifier);
      notifier.setError('Test error');
      notifier.clearError();

      final state = container.read(contactsStateProvider);
      expect(state.error, isNull);
    });

    test('setLoading updates loading state', () {
      container.read(contactsStateProvider.notifier).setLoading(true);

      final state = container.read(contactsStateProvider);
      expect(state.isLoading, isTrue);
    });

    test('setError updates error state', () {
      container.read(contactsStateProvider.notifier).setError('Test error');

      final state = container.read(contactsStateProvider);
      expect(state.error, equals('Test error'));
    });
  });

  group('Convenience Providers', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('contactsLoadingProvider reflects loading state', () {
      expect(container.read(contactsLoadingProvider), isFalse);

      container.read(contactsStateProvider.notifier).setLoading(true);

      expect(container.read(contactsLoadingProvider), isTrue);
    });

    test('contactsErrorProvider reflects error state', () {
      expect(container.read(contactsErrorProvider), isNull);

      container.read(contactsStateProvider.notifier).setError('Error');

      expect(container.read(contactsErrorProvider), equals('Error'));
    });

    test('selectedContactProvider reflects selected contact', () {
      expect(container.read(selectedContactProvider), isNull);
    });

    test('activeContactsProvider returns only active contacts', () {
      final contacts = [
        createTestContact(id: '1', status: ContactStatus.active),
        createTestContact(id: '2', status: ContactStatus.inactive),
      ];

      container.read(contactsStateProvider.notifier).setContacts(contacts);

      expect(container.read(activeContactsProvider).length, equals(1));
      expect(container.read(activeContactsProvider).first.id, equals('1'));
    });

    test('inactiveContactsProvider returns only inactive contacts', () {
      final contacts = [
        createTestContact(id: '1', status: ContactStatus.active),
        createTestContact(id: '2', status: ContactStatus.inactive),
      ];

      container.read(contactsStateProvider.notifier).setContacts(contacts);

      expect(container.read(inactiveContactsProvider).length, equals(1));
      expect(container.read(inactiveContactsProvider).first.id, equals('2'));
    });

    test('unsubscribedContactsProvider returns only unsubscribed contacts', () {
      final contacts = [
        createTestContact(id: '1', status: ContactStatus.unsubscribed),
        createTestContact(id: '2', status: ContactStatus.active),
      ];

      container.read(contactsStateProvider.notifier).setContacts(contacts);

      expect(container.read(unsubscribedContactsProvider).length, equals(1));
      expect(container.read(unsubscribedContactsProvider).first.id, equals('1'));
    });

    test('contactsCountProvider returns total count', () {
      final contacts = [
        createTestContact(id: '1'),
        createTestContact(id: '2'),
        createTestContact(id: '3'),
      ];

      container.read(contactsStateProvider.notifier).setContacts(contacts);

      expect(container.read(contactsCountProvider), equals(3));
    });

    test('activeContactsCountProvider returns active count', () {
      final contacts = [
        createTestContact(id: '1', status: ContactStatus.active),
        createTestContact(id: '2', status: ContactStatus.inactive),
        createTestContact(id: '3', status: ContactStatus.active),
      ];

      container.read(contactsStateProvider.notifier).setContacts(contacts);

      expect(container.read(activeContactsCountProvider), equals(2));
    });
  });
}
