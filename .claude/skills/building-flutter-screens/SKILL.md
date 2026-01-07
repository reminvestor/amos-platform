# Building Flutter Screens

Create new screens following AMOS Flutter patterns with Riverpod state management.

## Description

This skill provides patterns and templates for adding new screens to the AMOS Flutter mobile app. It covers file organization, Riverpod state management, API service integration, navigation with go_router, and consistent styling.

**Use this skill when:**
- Adding new feature screens
- Creating list/detail view patterns
- Building forms with validation
- Integrating with API services
- Setting up navigation routes

## Instructions

### Screen File Structure

New screens go in `lib/screens/{feature}/`:

```
lib/screens/
├── agents/
│   ├── agent_list_screen.dart
│   └── agent_detail_screen.dart
├── campaigns/
│   ├── campaign_list_screen.dart
│   └── campaign_form_screen.dart
└── {new_feature}/
    ├── {feature}_list_screen.dart
    ├── {feature}_detail_screen.dart
    └── {feature}_form_screen.dart
```

### Basic Screen Template

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';

class FeatureListScreen extends ConsumerStatefulWidget {
  const FeatureListScreen({super.key});

  @override
  ConsumerState<FeatureListScreen> createState() => _FeatureListScreenState();
}

class _FeatureListScreenState extends ConsumerState<FeatureListScreen> {
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load data via provider
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Features'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => _navigateToCreate(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Build list or loading state
    return const Center(child: CircularProgressIndicator());
  }

  void _navigateToCreate() {
    // Navigate to create form
  }
}
```

### Adding Navigation Route

Edit `lib/config/router.dart`:

```dart
// Add import
import 'package:amos_mobile/screens/features/feature_list_screen.dart';

// Add route in ShellRoute children
GoRoute(
  path: '/features',
  name: 'features',
  builder: (context, state) => const FeatureListScreen(),
),

// For detail routes with parameters
GoRoute(
  path: '/features/:id',
  name: 'feature-detail',
  builder: (context, state) {
    final id = int.parse(state.pathParameters['id']!);
    return FeatureDetailScreen(featureId: id);
  },
),
```

### API Service Pattern

Create `lib/services/features_service.dart`:

```dart
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/models/feature.dart';

class FeaturesService {
  final ApiClient _apiClient;

  FeaturesService(this._apiClient);

  Future<List<Feature>> getAll() async {
    final response = await _apiClient.get('/api/v1/features');
    return (response['features'] as List)
        .map((json) => Feature.fromJson(json))
        .toList();
  }

  Future<Feature> getById(int id) async {
    final response = await _apiClient.get('/api/v1/features/$id');
    return Feature.fromJson(response['feature']);
  }

  Future<Feature> create(Map<String, dynamic> data) async {
    final response = await _apiClient.post('/api/v1/features', data);
    return Feature.fromJson(response['feature']);
  }

  Future<Feature> update(int id, Map<String, dynamic> data) async {
    final response = await _apiClient.put('/api/v1/features/$id', data);
    return Feature.fromJson(response['feature']);
  }

  Future<void> delete(int id) async {
    await _apiClient.delete('/api/v1/features/$id');
  }
}
```

### Riverpod Provider Pattern

Add to `lib/providers/app_providers.dart`:

```dart
// Service provider
final featuresServiceProvider = Provider<FeaturesService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return FeaturesService(apiClient);
});

// State notifier for list
final featuresProvider = StateNotifierProvider<FeaturesNotifier, AsyncValue<List<Feature>>>((ref) {
  return FeaturesNotifier(ref.watch(featuresServiceProvider));
});

class FeaturesNotifier extends StateNotifier<AsyncValue<List<Feature>>> {
  final FeaturesService _service;

  FeaturesNotifier(this._service) : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final features = await _service.getAll();
      state = AsyncValue.data(features);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
```

### Model Pattern

Create `lib/models/feature.dart`:

```dart
class Feature {
  final int id;
  final String name;
  final String? description;
  final DateTime createdAt;

  Feature({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
  });

  factory Feature.fromJson(Map<String, dynamic> json) {
    return Feature(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
```

### List Screen with Pull-to-Refresh

```dart
Widget _buildBody() {
  final featuresAsync = ref.watch(featuresProvider);

  return featuresAsync.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Error: $error'),
          ElevatedButton(
            onPressed: () => ref.read(featuresProvider.notifier).load(),
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
    data: (features) => RefreshIndicator(
      onRefresh: () => ref.read(featuresProvider.notifier).load(),
      child: ListView.builder(
        itemCount: features.length,
        itemBuilder: (context, index) => _buildFeatureCard(features[index]),
      ),
    ),
  );
}
```

### Form Screen Pattern

```dart
class FeatureFormScreen extends ConsumerStatefulWidget {
  final int? featureId; // null for create, id for edit

  const FeatureFormScreen({super.key, this.featureId});

  @override
  ConsumerState<FeatureFormScreen> createState() => _FeatureFormScreenState();
}

class _FeatureFormScreenState extends ConsumerState<FeatureFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.featureId == null ? 'Create Feature' : 'Edit Feature'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'Name is required' : null,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      // Save via service
      context.pop(); // Return to list
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
```

## Examples

**Create a new feature screen:**
```
Use building-flutter-screens to create a tasks list and detail screen
```

**Add form with validation:**
```
Use building-flutter-screens to add a create/edit form for campaigns
```

## Resources

- [Flutter Screen Patterns](resources/screen-patterns.md) - Common UI patterns
- [Riverpod Best Practices](https://riverpod.dev/docs/concepts/best_practices)

## Related Skills

- [Running Flutter App](../running-flutter-app/SKILL.md) - Test new screens
- [Debugging Mobile API](../debugging-mobile-api/SKILL.md) - API integration issues
