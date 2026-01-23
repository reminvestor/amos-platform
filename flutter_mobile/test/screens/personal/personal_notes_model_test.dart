import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/screens/personal/personal_notes_screen.dart';

void main() {
  group('Note', () {
    final createdAt = DateTime(2025, 1, 15, 10, 0);
    final updatedAt = DateTime(2025, 1, 15, 12, 0);

    test('creates with required values', () {
      final note = Note(
        id: '1',
        title: 'Shopping List',
        content: 'Milk, eggs, bread',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(note.id, '1');
      expect(note.title, 'Shopping List');
      expect(note.content, 'Milk, eggs, bread');
      expect(note.createdAt, createdAt);
      expect(note.updatedAt, updatedAt);
      expect(note.color, isNull);
      expect(note.isPinned, false);
    });

    test('creates with all optional values', () {
      final note = Note(
        id: '2',
        title: 'Important Note',
        content: 'Very important content',
        createdAt: createdAt,
        updatedAt: updatedAt,
        color: 'red',
        isPinned: true,
      );

      expect(note.color, 'red');
      expect(note.isPinned, true);
    });

    test('creates with different colors', () {
      final colors = ['red', 'orange', 'yellow', 'green', 'blue', 'purple'];

      for (final color in colors) {
        final note = Note(
          id: color,
          title: 'Note with $color',
          content: 'Content',
          createdAt: createdAt,
          updatedAt: updatedAt,
          color: color,
        );

        expect(note.color, color);
      }
    });

    group('fromJson', () {
      test('parses complete data', () {
        final json = {
          'id': 'note-123',
          'title': 'Meeting Notes',
          'content': 'Discussed quarterly goals',
          'created_at': '2025-01-15T10:00:00Z',
          'updated_at': '2025-01-15T12:00:00Z',
          'color': 'blue',
          'is_pinned': true,
        };

        final note = Note.fromJson(json);

        expect(note.id, 'note-123');
        expect(note.title, 'Meeting Notes');
        expect(note.content, 'Discussed quarterly goals');
        expect(note.color, 'blue');
        expect(note.isPinned, true);
        expect(note.createdAt.year, 2025);
        expect(note.updatedAt.year, 2025);
      });

      test('handles missing optional fields', () {
        final json = {
          'id': '1',
          'created_at': '2025-01-15T10:00:00Z',
          'updated_at': '2025-01-15T10:00:00Z',
        };

        final note = Note.fromJson(json);

        expect(note.title, '');
        expect(note.content, '');
        expect(note.color, isNull);
        expect(note.isPinned, false);
      });

      test('handles null values', () {
        final json = {
          'id': '1',
          'title': null,
          'content': null,
          'color': null,
          'is_pinned': null,
          'created_at': '2025-01-15T10:00:00Z',
          'updated_at': '2025-01-15T10:00:00Z',
        };

        final note = Note.fromJson(json);

        expect(note.title, '');
        expect(note.content, '');
        expect(note.color, isNull);
        expect(note.isPinned, false);
      });
    });

    group('toJson', () {
      test('serializes all fields', () {
        final note = Note(
          id: '1',
          title: 'Test Note',
          content: 'Test content',
          createdAt: DateTime.parse('2025-01-15T10:00:00Z'),
          updatedAt: DateTime.parse('2025-01-15T12:00:00Z'),
          color: 'green',
          isPinned: true,
        );

        final json = note.toJson();

        expect(json['id'], '1');
        expect(json['title'], 'Test Note');
        expect(json['content'], 'Test content');
        expect(json['color'], 'green');
        expect(json['is_pinned'], true);
        expect(json['created_at'], isA<String>());
        expect(json['updated_at'], isA<String>());
      });

      test('includes null color', () {
        final note = Note(
          id: '1',
          title: 'Test',
          content: 'Content',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final json = note.toJson();

        expect(json['color'], isNull);
      });
    });

    group('copyWith', () {
      test('copies with no changes', () {
        final original = Note(
          id: '1',
          title: 'Original',
          content: 'Original content',
          createdAt: createdAt,
          updatedAt: updatedAt,
          color: 'blue',
          isPinned: true,
        );

        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.title, original.title);
        expect(copy.content, original.content);
        expect(copy.createdAt, original.createdAt);
        expect(copy.updatedAt, original.updatedAt);
        expect(copy.color, original.color);
        expect(copy.isPinned, original.isPinned);
      });

      test('copies with title changed', () {
        final original = Note(
          id: '1',
          title: 'Original Title',
          content: 'Content',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final modified = original.copyWith(title: 'New Title');

        expect(modified.title, 'New Title');
        expect(modified.content, original.content);
        expect(modified.id, original.id);
      });

      test('copies with content changed', () {
        final original = Note(
          id: '1',
          title: 'Title',
          content: 'Original content',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final modified = original.copyWith(content: 'New content');

        expect(modified.content, 'New content');
        expect(modified.title, original.title);
      });

      test('copies with color changed', () {
        final original = Note(
          id: '1',
          title: 'Title',
          content: 'Content',
          createdAt: createdAt,
          updatedAt: updatedAt,
          color: 'blue',
        );

        final modified = original.copyWith(color: 'red');

        expect(modified.color, 'red');
      });

      test('copies with isPinned changed', () {
        final original = Note(
          id: '1',
          title: 'Title',
          content: 'Content',
          createdAt: createdAt,
          updatedAt: updatedAt,
          isPinned: false,
        );

        final modified = original.copyWith(isPinned: true);

        expect(modified.isPinned, true);
        expect(original.isPinned, false);
      });

      test('copies with updatedAt changed', () {
        final original = Note(
          id: '1',
          title: 'Title',
          content: 'Content',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final newUpdatedAt = DateTime(2025, 1, 16, 10, 0);
        final modified = original.copyWith(updatedAt: newUpdatedAt);

        expect(modified.updatedAt, newUpdatedAt);
        expect(modified.createdAt, createdAt);
      });

      test('copies with multiple fields changed', () {
        final original = Note(
          id: '1',
          title: 'Original',
          content: 'Original content',
          createdAt: createdAt,
          updatedAt: updatedAt,
          color: 'blue',
          isPinned: false,
        );

        final newUpdatedAt = DateTime.now();
        final modified = original.copyWith(
          title: 'Modified',
          content: 'Modified content',
          color: 'red',
          isPinned: true,
          updatedAt: newUpdatedAt,
        );

        expect(modified.title, 'Modified');
        expect(modified.content, 'Modified content');
        expect(modified.color, 'red');
        expect(modified.isPinned, true);
        expect(modified.updatedAt, newUpdatedAt);
        expect(modified.id, original.id);
        expect(modified.createdAt, original.createdAt);
      });

      test('preserves id and createdAt', () {
        final original = Note(
          id: 'unique-id',
          title: 'Title',
          content: 'Content',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final modified = original.copyWith(
          title: 'New Title',
          content: 'New Content',
        );

        expect(modified.id, 'unique-id');
        expect(modified.createdAt, createdAt);
      });
    });

    test('round trips through JSON', () {
      final original = Note(
        id: 'round-trip-id',
        title: 'Round Trip Test',
        content: 'This is a test note for round trip serialization',
        createdAt: DateTime.parse('2025-01-15T10:00:00.000Z'),
        updatedAt: DateTime.parse('2025-01-15T12:00:00.000Z'),
        color: 'purple',
        isPinned: true,
      );

      final json = original.toJson();
      final restored = Note.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.content, original.content);
      expect(restored.color, original.color);
      expect(restored.isPinned, original.isPinned);
    });

    test('creates notes for different use cases', () {
      // Quick note
      final quickNote = Note(
        id: '1',
        title: '',
        content: 'Remember to call mom',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      // Meeting notes
      final meetingNote = Note(
        id: '2',
        title: 'Q1 Planning Meeting',
        content: '- Goal 1: Increase revenue by 20%\n- Goal 2: Launch new product',
        createdAt: createdAt,
        updatedAt: updatedAt,
        color: 'blue',
        isPinned: true,
      );

      // Idea note
      final ideaNote = Note(
        id: '3',
        title: 'App Ideas',
        content: 'New feature: dark mode, offline support',
        createdAt: createdAt,
        updatedAt: updatedAt,
        color: 'yellow',
      );

      // Urgent reminder
      final urgentNote = Note(
        id: '4',
        title: 'URGENT',
        content: 'Submit report by 5pm!',
        createdAt: createdAt,
        updatedAt: updatedAt,
        color: 'red',
        isPinned: true,
      );

      expect(quickNote.title, '');
      expect(meetingNote.isPinned, true);
      expect(ideaNote.color, 'yellow');
      expect(urgentNote.color, 'red');
    });

    test('handles empty title and content', () {
      final emptyNote = Note(
        id: '1',
        title: '',
        content: '',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(emptyNote.title, '');
      expect(emptyNote.content, '');
    });

    test('handles long content', () {
      final longContent = 'A' * 10000;
      final note = Note(
        id: '1',
        title: 'Long Note',
        content: longContent,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(note.content.length, 10000);
    });

    test('handles special characters in content', () {
      final note = Note(
        id: '1',
        title: 'Special Chars',
        content: 'Unicode: 你好 🎉 € £ ¥',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(note.content, 'Unicode: 你好 🎉 € £ ¥');
    });

    test('handles newlines in content', () {
      final note = Note(
        id: '1',
        title: 'Multi-line',
        content: 'Line 1\nLine 2\nLine 3',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(note.content.contains('\n'), true);
    });
  });
}
