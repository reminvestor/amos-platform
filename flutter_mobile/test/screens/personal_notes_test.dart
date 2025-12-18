import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/screens/personal/personal_notes_screen.dart';

void main() {
  group('Note', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 'note-123',
        'title': 'Test Note',
        'content': 'This is the content',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
        'color': 'blue',
        'is_pinned': true,
      };

      final note = Note.fromJson(json);

      expect(note.id, equals('note-123'));
      expect(note.title, equals('Test Note'));
      expect(note.content, equals('This is the content'));
      expect(note.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(note.updatedAt, equals(DateTime.parse('2024-01-16T11:00:00.000Z')));
      expect(note.color, equals('blue'));
      expect(note.isPinned, isTrue);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'note-456',
        'title': '',
        'content': '',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-15T10:30:00.000Z',
      };

      final note = Note.fromJson(json);

      expect(note.id, equals('note-456'));
      expect(note.title, isEmpty);
      expect(note.content, isEmpty);
      expect(note.color, isNull);
      expect(note.isPinned, isFalse);
    });

    test('toJson serializes correctly', () {
      final note = Note(
        id: 'note-789',
        title: 'My Note',
        content: 'Note content here',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
        color: 'green',
        isPinned: false,
      );

      final json = note.toJson();

      expect(json['id'], equals('note-789'));
      expect(json['title'], equals('My Note'));
      expect(json['content'], equals('Note content here'));
      expect(json['color'], equals('green'));
      expect(json['is_pinned'], isFalse);
    });

    test('copyWith creates new note with updated values', () {
      final original = Note(
        id: 'note-1',
        title: 'Original Title',
        content: 'Original Content',
        createdAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
        updatedAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
        color: 'red',
        isPinned: false,
      );

      final updated = original.copyWith(
        title: 'Updated Title',
        isPinned: true,
        updatedAt: DateTime.parse('2024-01-16T12:00:00.000Z'),
      );

      // Updated fields
      expect(updated.title, equals('Updated Title'));
      expect(updated.isPinned, isTrue);
      expect(updated.updatedAt, equals(DateTime.parse('2024-01-16T12:00:00.000Z')));

      // Unchanged fields
      expect(updated.id, equals(original.id));
      expect(updated.content, equals(original.content));
      expect(updated.createdAt, equals(original.createdAt));
      expect(updated.color, equals(original.color));
    });

    test('copyWith with new color', () {
      final original = Note(
        id: 'note-2',
        title: 'Title',
        content: 'Content',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        color: 'blue',
      );

      final updated = original.copyWith(color: 'yellow');

      expect(updated.color, equals('yellow'));
      expect(updated.title, equals(original.title));
    });

    test('roundtrip serialization works', () {
      final original = Note(
        id: 'note-roundtrip',
        title: 'Roundtrip Test',
        content: 'Testing serialization',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
        color: 'purple',
        isPinned: true,
      );

      final json = original.toJson();
      final parsed = Note.fromJson(json);

      expect(parsed.id, equals(original.id));
      expect(parsed.title, equals(original.title));
      expect(parsed.content, equals(original.content));
      expect(parsed.color, equals(original.color));
      expect(parsed.isPinned, equals(original.isPinned));
    });
  });
}
