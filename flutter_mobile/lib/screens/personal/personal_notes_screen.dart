import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/services/storage_service.dart';
import 'package:amos_mobile/services/dictation_service.dart';

/// Note model
class Note {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? color;
  final bool isPinned;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.color,
    this.isPinned = false,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      color: json['color'],
      isPinned: json['is_pinned'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'color': color,
      'is_pinned': isPinned,
    };
  }

  Note copyWith({
    String? title,
    String? content,
    DateTime? updatedAt,
    String? color,
    bool? isPinned,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      color: color ?? this.color,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}

/// Notes state notifier using Notifier pattern
class NotesNotifier extends Notifier<List<Note>> {
  static const String _storageKey = 'personal_notes';

  @override
  List<Note> build() {
    _loadNotes();
    return [];
  }

  Future<void> _loadNotes() async {
    try {
      final storage = StorageService.instance;
      final data = await storage.read(_storageKey);
      if (data != null) {
        final List<dynamic> decoded = jsonDecode(data);
        state = decoded.map((e) => Note.fromJson(e)).toList();
      }
    } catch (e) {
      // Ignore load errors
    }
  }

  Future<void> _saveNotes() async {
    try {
      final storage = StorageService.instance;
      final data = jsonEncode(state.map((e) => e.toJson()).toList());
      await storage.write(_storageKey, data);
    } catch (e) {
      // Ignore save errors
    }
  }

  void addNote(Note note) {
    state = [note, ...state];
    _saveNotes();
  }

  void updateNote(Note note) {
    state = state.map((n) => n.id == note.id ? note : n).toList();
    _saveNotes();
  }

  void deleteNote(String id) {
    state = state.where((n) => n.id != id).toList();
    _saveNotes();
  }

  void togglePin(String id) {
    final updatedState = state.map((n) {
      if (n.id == id) {
        return n.copyWith(isPinned: !n.isPinned);
      }
      return n;
    }).toList();
    // Sort: pinned first, then by updated date
    updatedState.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    state = updatedState;
    _saveNotes();
  }
}

final notesProvider = NotifierProvider<NotesNotifier, List<Note>>(() {
  return NotesNotifier();
});

class PersonalNotesScreen extends ConsumerWidget {
  const PersonalNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    final pinnedNotes = notes.where((n) => n.isPinned).toList();
    final otherNotes = notes.where((n) => !n.isPinned).toList();

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/logo-header.png',
          height: 26,
          color: Theme.of(context).brightness == Brightness.light
              ? const Color(0xFF1a1a2e)
              : null,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.bell),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: notes.isEmpty
          ? _buildEmptyState(context, ref)
          : RefreshIndicator(
              onRefresh: () async {},
              child: CustomScrollView(
                slivers: [
                  if (pinnedNotes.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.pin,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Pinned',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.2,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _NoteCard(
                            note: pinnedNotes[index],
                            onTap: () => _openNoteEditor(
                                context, ref, pinnedNotes[index]),
                            onTogglePin: () => ref
                                .read(notesProvider.notifier)
                                .togglePin(pinnedNotes[index].id),
                            onDelete: () => ref
                                .read(notesProvider.notifier)
                                .deleteNote(pinnedNotes[index].id),
                          ),
                          childCount: pinnedNotes.length,
                        ),
                      ),
                    ),
                  ],
                  if (otherNotes.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Notes',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.2,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _NoteCard(
                            note: otherNotes[index],
                            onTap: () =>
                                _openNoteEditor(context, ref, otherNotes[index]),
                            onTogglePin: () => ref
                                .read(notesProvider.notifier)
                                .togglePin(otherNotes[index].id),
                            onDelete: () => ref
                                .read(notesProvider.notifier)
                                .deleteNote(otherNotes[index].id),
                          ),
                          childCount: otherNotes.length,
                        ),
                      ),
                    ),
                  ],
                  const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNoteEditor(context, ref, null),
        child: const Icon(LucideIcons.plus),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.stickyNote,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No notes yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first note',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _openNoteEditor(context, ref, null),
            icon: const Icon(LucideIcons.plus),
            label: const Text('Create Note'),
          ),
        ],
      ),
    );
  }

  void _openNoteEditor(BuildContext context, WidgetRef ref, Note? note) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _NoteEditorScreen(
          note: note,
          onSave: (savedNote) {
            if (note == null) {
              ref.read(notesProvider.notifier).addNote(savedNote);
            } else {
              ref.read(notesProvider.notifier).updateNote(savedNote);
            }
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onTogglePin,
    required this.onDelete,
  });

  Color? _getCardColor(BuildContext context) {
    if (note.color == null) return null;
    switch (note.color) {
      case 'red':
        return Colors.red.withOpacity(0.1);
      case 'orange':
        return Colors.orange.withOpacity(0.1);
      case 'yellow':
        return Colors.yellow.withOpacity(0.1);
      case 'green':
        return Colors.green.withOpacity(0.1);
      case 'blue':
        return Colors.blue.withOpacity(0.1);
      case 'purple':
        return Colors.purple.withOpacity(0.1);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: _getCardColor(context) ?? theme.colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showOptions(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Untitled' : note.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (note.isPinned)
                    Icon(
                      LucideIcons.pin,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  note.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatDate(note.updatedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(note.isPinned ? LucideIcons.pinOff : LucideIcons.pin),
              title: Text(note.isPinned ? 'Unpin' : 'Pin to top'),
              onTap: () {
                Navigator.pop(context);
                onTogglePin();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Are you sure you want to delete this note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final Function(Note) onSave;

  const _NoteEditorScreen({
    this.note,
    required this.onSave,
  });

  @override
  State<_NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<_NoteEditorScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  String? _selectedColor;
  bool _hasChanges = false;

  // Dictation support
  DictationService? _dictationService;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<DictationState>? _dictationStateSubscription;
  StreamSubscription<String>? _interimSubscription;
  DictationState _dictationState = DictationState.idle;
  String _interimText = '';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController =
        TextEditingController(text: widget.note?.content ?? '');
    _selectedColor = widget.note?.color;

    _titleController.addListener(() => setState(() => _hasChanges = true));
    _contentController.addListener(() => setState(() => _hasChanges = true));

    _initDictation();
  }

  void _initDictation() {
    _dictationService = DictationService(textController: _contentController);

    // Setup pulse animation for listening state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to dictation state changes
    _dictationStateSubscription =
        _dictationService!.stateStream.listen((state) {
      if (mounted) {
        setState(() => _dictationState = state);
        if (state == DictationState.listening) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });

    // Listen to interim text changes
    _interimSubscription = _dictationService!.interimTextStream.listen((text) {
      if (mounted) {
        setState(() => _interimText = text);
      }
    });
  }

  Future<void> _toggleDictation() async {
    try {
      await _dictationService?.toggle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dictation error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    // Clean up dictation
    _pulseController.dispose();
    _dictationStateSubscription?.cancel();
    _interimSubscription?.cancel();
    _dictationService?.dispose();
    super.dispose();
  }

  void _save() {
    final now = DateTime.now();
    final note = Note(
      id: widget.note?.id ?? now.millisecondsSinceEpoch.toString(),
      title: _titleController.text,
      content: _contentController.text,
      createdAt: widget.note?.createdAt ?? now,
      updatedAt: now,
      color: _selectedColor,
      isPinned: widget.note?.isPinned ?? false,
    );

    widget.onSave(note);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isListening = _dictationState == DictationState.listening;
    final isInitializing = _dictationState == DictationState.initializing;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () {
            if (_hasChanges) {
              _showDiscardDialog();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
        actions: [
          // Dictation button in app bar
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: isListening ? _pulseAnimation.value : 1.0,
                child: IconButton(
                  icon: isInitializing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          isListening ? LucideIcons.micOff : LucideIcons.mic,
                          color: isListening
                              ? Colors.red
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                  onPressed: isInitializing ? null : _toggleDictation,
                  tooltip: isListening ? 'Stop dictation' : 'Start dictation',
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.palette),
            onPressed: _showColorPicker,
            tooltip: 'Color',
          ),
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
              style: Theme.of(context).textTheme.titleLarge,
              textCapitalization: TextCapitalization.sentences,
            ),
            const Divider(),
            // Show interim text indicator when listening
            if (isListening && _interimText.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.mic,
                      size: 14,
                      color: Colors.red.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _interimText,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Container(
                decoration: isListening
                    ? BoxDecoration(
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: TextField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    hintText: isListening
                        ? 'Listening... speak now'
                        : 'Start typing or tap mic to dictate...',
                    border: InputBorder.none,
                    contentPadding:
                        isListening ? const EdgeInsets.all(8) : null,
                  ),
                  maxLines: null,
                  expands: true,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDiscardDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Note color',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  _ColorOption(
                    color: null,
                    label: 'Default',
                    isSelected: _selectedColor == null,
                    onTap: () {
                      setState(() => _selectedColor = null);
                      Navigator.pop(context);
                    },
                  ),
                  _ColorOption(
                    color: Colors.red,
                    label: 'Red',
                    isSelected: _selectedColor == 'red',
                    onTap: () {
                      setState(() => _selectedColor = 'red');
                      Navigator.pop(context);
                    },
                  ),
                  _ColorOption(
                    color: Colors.orange,
                    label: 'Orange',
                    isSelected: _selectedColor == 'orange',
                    onTap: () {
                      setState(() => _selectedColor = 'orange');
                      Navigator.pop(context);
                    },
                  ),
                  _ColorOption(
                    color: Colors.yellow,
                    label: 'Yellow',
                    isSelected: _selectedColor == 'yellow',
                    onTap: () {
                      setState(() => _selectedColor = 'yellow');
                      Navigator.pop(context);
                    },
                  ),
                  _ColorOption(
                    color: Colors.green,
                    label: 'Green',
                    isSelected: _selectedColor == 'green',
                    onTap: () {
                      setState(() => _selectedColor = 'green');
                      Navigator.pop(context);
                    },
                  ),
                  _ColorOption(
                    color: Colors.blue,
                    label: 'Blue',
                    isSelected: _selectedColor == 'blue',
                    onTap: () {
                      setState(() => _selectedColor = 'blue');
                      Navigator.pop(context);
                    },
                  ),
                  _ColorOption(
                    color: Colors.purple,
                    label: 'Purple',
                    isSelected: _selectedColor == 'purple',
                    onTap: () {
                      setState(() => _selectedColor = 'purple');
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorOption extends StatelessWidget {
  final Color? color;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorOption({
    required this.color,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color?.withOpacity(0.3) ??
              Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: isSelected
            ? Icon(
                LucideIcons.check,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
      ),
    );
  }
}
