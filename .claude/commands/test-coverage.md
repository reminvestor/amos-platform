---
name: test-coverage
description: Analyze test coverage gaps and generate unit/widget/integration tests for the Flutter mobile application. Activates when user mentions test coverage, generating tests, or testing gaps.
---

# Test Coverage Generator

Analyze test coverage gaps and generate unit/widget/integration tests for the Flutter mobile application.

## Usage

```bash
/test-coverage                      # Analyze coverage and suggest tests
/test-coverage --generate <file>    # Generate tests for specific file
/test-coverage --provider <name>    # Generate tests for a Riverpod provider
/test-coverage --widget <name>      # Generate widget tests
/test-coverage --feature <name>     # Generate tests for entire feature module
/test-coverage --report             # Generate detailed coverage report
/test-coverage --ralph              # Ralph loop: iterate until coverage target met
/test-coverage --ralph --target 80  # Ralph loop with 80% coverage target
```

## Workflow

### Step 1: Parse Arguments

Determine mode from arguments:
- No args: Analyze current coverage and suggest tests to add
- `--generate <file>`: Generate tests for specific source file
- `--provider <name>`: Generate tests for a Riverpod provider
- `--widget <name>`: Generate widget tests for a widget
- `--feature <name>`: Generate tests for entire feature (captain, angler, booking, etc.)
- `--report`: Generate detailed coverage report
- `--ralph` or `--loop`: Ralph Wiggum loop until coverage target met
- `--target N`: Coverage percentage target (default: 80%)

### Step 2: Coverage Analysis

1. **Run coverage analysis:**
   ```bash
   cd flutter_mobile && \
   flutter test --coverage 2>&1 | tee /tmp/flutter-coverage.txt && \
   genhtml coverage/lcov.info -o coverage/html 2>/dev/null || true
   ```

2. **Parse coverage output:**
   ```bash
   # Extract per-file coverage
   lcov --summary flutter_mobile/coverage/lcov.info 2>&1

   # List files with coverage data
   cat flutter_mobile/coverage/lcov.info | grep "^SF:" | sed 's/SF://' | head -50
   ```

3. **Display coverage summary:**
   ```
   ## Test Coverage Analysis

   Overall Coverage: {percentage}%

   ### Low Coverage Files (<70%):
   | File | Coverage | Missing Lines |
   |------|----------|---------------|
   | lib/features/booking/presentation/providers/booking_provider.dart | 45% | 23-45, 67-89 |
   | lib/services/stripe_service.dart | 52% | 100-150 |

   ### Medium Coverage Files (70-85%):
   | File | Coverage | Missing Lines |
   |------|----------|---------------|
   | lib/features/captain/fleet/presentation/providers/fleet_provider.dart | 78% | 200-210 |

   ### Well Covered Files (>85%):
   - lib/core/constants/cancellation_policy.dart (92%)
   - lib/core/utils/validators.dart (88%)
   ```

### Step 3: Generate Tests (if `--generate`, `--provider`, or `--widget`)

#### For Riverpod Providers

1. **Read the source file:**
   ```bash
   Read flutter_mobile/lib/features/{feature}/presentation/providers/{name}_provider.dart
   ```

2. **Identify untested methods:**
   - Parse class definitions
   - Find public methods
   - Cross-reference with existing tests
   - Note method signatures and return types

3. **Generate test file:**
   Create `flutter_mobile/test/features/{feature}/presentation/providers/{name}_provider_test.dart`:

   ```dart
   import 'package:flutter_test/flutter_test.dart';
   import 'package:mocktail/mocktail.dart';
   import 'package:amos_mobile/features/{feature}/presentation/providers/{name}_provider.dart';
   import 'package:amos_mobile/features/{feature}/data/repositories/{name}_repository.dart';

   import '../../../../../helpers/test_helpers.dart';

   // Mock classes
   class Mock{Repository} extends Mock implements {Repository} {}

   void main() {
     late Mock{Repository} mockRepository;

     setUp(() {
       mockRepository = Mock{Repository}();
     });

     group('{ProviderName}', () {
       // ===== Test build() method =====

       test('initializes with loading state', () async {
         // Arrange
         when(() => mockRepository.fetch{Data}())
             .thenAnswer((_) async => {mockData});

         final container = createProviderContainer(
           overrides: [
             {repository}Provider.overrideWithValue(mockRepository),
           ],
         );

         // Act
         final result = await container.read({provider}.future);

         // Assert
         expect(result, isNotNull);
         verify(() => mockRepository.fetch{Data}()).called(1);
       });

       test('handles error state', () async {
         // Arrange
         when(() => mockRepository.fetch{Data}())
             .thenThrow(Exception('Connection error'));

         final container = createProviderContainer(
           overrides: [
             {repository}Provider.overrideWithValue(mockRepository),
           ],
         );

         // Act & Assert
         expect(
           () => container.read({provider}.future),
           throwsException,
         );
       });

       // ===== Test {methodName} =====

       test('{methodName} success case', () async {
         // Arrange
         {arrange_code}

         final container = createProviderContainer(
           overrides: [
             {repository}Provider.overrideWithValue(mockRepository),
           ],
         );

         await container.read({provider}.future);

         // Act
         await container.read({provider}.notifier).{methodName}({params});

         // Assert
         {assertions}
       });

       test('{methodName} handles failure', () async {
         // Arrange
         {failure_arrange}

         final container = createProviderContainer(
           overrides: [
             {repository}Provider.overrideWithValue(mockRepository),
           ],
         );

         await container.read({provider}.future);

         // Act
         final result = await container.read({provider}.notifier).{methodName}({params});

         // Assert
         expect(result, {failure_expectation});
       });
     });
   }
   ```

#### For Widget Files

1. **Read the widget file:**
   ```bash
   Read flutter_mobile/lib/features/{feature}/presentation/widgets/{name}.dart
   # or
   Read flutter_mobile/lib/core/widgets/{name}.dart
   ```

2. **Identify test scenarios:**
   - Rendering states (loading, error, data)
   - User interactions (tap, scroll, input)
   - Conditional UI elements
   - Callbacks and navigation

3. **Generate widget test file:**
   Create `flutter_mobile/test/features/{feature}/presentation/widgets/{name}_test.dart`:

   ```dart
   import 'package:flutter/material.dart';
   import 'package:flutter_test/flutter_test.dart';
   import 'package:mocktail/mocktail.dart';
   import 'package:amos_mobile/features/{feature}/presentation/widgets/{name}.dart';

   import '../../../../../helpers/test_helpers.dart';

   void main() {
     group('{WidgetName}', () {
       // ===== Rendering Tests =====

       testWidgets('renders correctly with required props', (tester) async {
         // Arrange
         await tester.pumpWidget(
           createTestWidget(
             child: const {WidgetName}(
               {required_props}
             ),
           ),
         );

         // Assert
         expect(find.byType({WidgetName}), findsOneWidget);
         {rendering_assertions}
       });

       testWidgets('displays loading state', (tester) async {
         await tester.pumpWidget(
           createTestWidget(
             child: const {WidgetName}(
               isLoading: true,
             ),
           ),
         );

         expect(find.byType(CircularProgressIndicator), findsOneWidget);
       });

       testWidgets('displays error state', (tester) async {
         await tester.pumpWidget(
           createTestWidget(
             child: const {WidgetName}(
               error: 'Something went wrong',
             ),
           ),
         );

         expect(find.text('Something went wrong'), findsOneWidget);
       });

       // ===== Interaction Tests =====

       testWidgets('calls onTap when tapped', (tester) async {
         // Arrange
         var tapped = false;

         await tester.pumpWidget(
           createTestWidget(
             child: {WidgetName}(
               onTap: () => tapped = true,
             ),
           ),
         );

         // Act
         await tester.tap(find.byType({WidgetName}));
         await tester.pump();

         // Assert
         expect(tapped, isTrue);
       });

       testWidgets('handles user input', (tester) async {
         // Arrange
         String? inputValue;

         await tester.pumpWidget(
           createTestWidget(
             child: {WidgetName}(
               onChanged: (value) => inputValue = value,
             ),
           ),
         );

         // Act
         await tester.enterText(find.byType(TextField), 'test input');
         await tester.pump();

         // Assert
         expect(inputValue, 'test input');
       });
     });
   }
   ```

#### For Feature Modules

1. **Analyze feature structure:**
   ```bash
   find flutter_mobile/lib/features/{feature} -name "*.dart" -type f
   ```

2. **Generate comprehensive tests for:**
   - All providers in `presentation/providers/`
   - All screens in `presentation/screens/`
   - All widgets in `presentation/widgets/`
   - All entities in `domain/entities/`
   - All models in `data/models/`
   - All repositories in `data/repositories/`

### Step 4: Ralph Wiggum Loop Mode (if `--ralph`)

**Skip this section if NOT running in Ralph loop mode.**

If the user invoked `/test-coverage --ralph`:

#### Loop Initialization

1. **Initialize the Ralph loop:**
   ```bash
   # Parse target coverage (default 80%)
   TARGET_COVERAGE=${TARGET:-80}
   MAX_ITERATIONS=${MAX:-15}

   # Set completion promise
   COMPLETION_PROMISE="COVERAGE_TARGET_MET: Coverage is at or above ${TARGET_COVERAGE}%"
   ```

2. **Announce loop mode:**
   ```
   ## Ralph Wiggum Coverage Loop Activated

   Target Coverage: {target}%
   Max Iterations: {max_iterations}
   Completion Promise: COVERAGE_TARGET_MET

   Loop will continue until:
   - Coverage reaches {target}%
   - Max iterations reached ({max_iterations})
   - You run /cancel-ralph

   Starting iteration 1...
   ```

#### Each Loop Iteration

1. **Run coverage analysis:**
   ```bash
   cd flutter_mobile && flutter test --coverage
   ```

2. **Check if target met:**
   - Parse overall coverage percentage
   - If >= target: output completion promise and exit
   - If < target: continue to step 3

3. **Identify highest-impact gaps:**
   - Find files with lowest coverage
   - Prioritize by: file importance, lines uncovered, complexity
   - Select 1-3 files to improve this iteration

4. **Generate tests for gap:**
   - Read source file
   - Identify untested methods/branches
   - Generate appropriate tests
   - Write to test file

5. **Run new tests to verify:**
   ```bash
   cd flutter_mobile && flutter test test/features/{new_test_file}_test.dart -v
   ```

6. **Fix any test failures:**
   - If tests fail: analyze and fix
   - Re-run until passing

7. **Commit progress:**
   ```bash
   git add flutter_mobile/test/
   git commit -m "test: Add coverage for {module} - iteration {n}

   - Coverage: {old}% -> {new}%
   - Added tests for: {methods}

   Ralph Wiggum Coverage Loop - Iteration {n}"
   ```

8. **Report iteration progress:**
   ```
   ## Iteration {n}/{max}

   Coverage: {old}% -> {new}% (target: {target}%)
   Tests added: {count}
   Files improved:
   - {file1}: {old1}% -> {new1}%
   - {file2}: {old2}% -> {new2}%

   {Progress bar toward target}
   ```

9. **Continue to next iteration**

#### Loop Termination

Output the completion promise ONLY when:
- Overall coverage >= target percentage

```
COVERAGE_TARGET_MET: Coverage is at or above {target}%
```

## Test Patterns Reference

### Unit Test Pattern (Providers)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../../helpers/test_helpers.dart';

class MockRepository extends Mock implements Repository {}

void main() {
  late MockRepository mockRepository;

  setUp(() {
    mockRepository = MockRepository();
  });

  group('ProviderName', () {
    test('initializes correctly', () async {
      when(() => mockRepository.getData()).thenAnswer((_) async => mockData);

      final container = createProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(mockRepository)],
      );

      final result = await container.read(provider.future);
      expect(result, isNotNull);
    });

    test('handles error', () async {
      when(() => mockRepository.getData()).thenThrow(Exception('Error'));

      final container = createProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(mockRepository)],
      );

      expect(() => container.read(provider.future), throwsException);
    });
  });
}
```

### Widget Test Pattern

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/test_helpers.dart';

void main() {
  group('WidgetName', () {
    testWidgets('renders correctly', (tester) async {
      await tester.pumpWidget(
        createTestWidget(child: const WidgetName()),
      );

      expect(find.byType(WidgetName), findsOneWidget);
    });

    testWidgets('handles tap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        createTestWidget(
          child: WidgetName(onTap: () => tapped = true),
        ),
      );

      await tester.tap(find.byType(WidgetName));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });
}
```

### Entity/Model Test Pattern

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EntityName', () {
    test('creates with required fields', () {
      const entity = EntityName(
        id: 'test-1',
        name: 'Test',
      );

      expect(entity.id, 'test-1');
      expect(entity.name, 'Test');
    });

    test('copyWith creates modified copy', () {
      const original = EntityName(id: 'test-1', name: 'Original');
      final modified = original.copyWith(name: 'Modified');

      expect(modified.id, 'test-1');
      expect(modified.name, 'Modified');
      expect(original.name, 'Original'); // Original unchanged
    });

    test('toJson serializes correctly', () {
      const entity = EntityName(id: 'test-1', name: 'Test');
      final json = entity.toJson();

      expect(json['id'], 'test-1');
      expect(json['name'], 'Test');
    });

    test('fromJson deserializes correctly', () {
      final entity = EntityName.fromJson({'id': 'test-1', 'name': 'Test'});

      expect(entity.id, 'test-1');
      expect(entity.name, 'Test');
    });
  });
}
```

### Repository Test Pattern

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockClient;
  late Repository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = Repository(client: mockClient);
  });

  group('Repository', () {
    test('fetches data successfully', () async {
      when(() => mockClient.get('/api/endpoint'))
          .thenAnswer((_) async => Response(data: mockDataMap));

      final result = await repository.getData();

      expect(result, isNotEmpty);
      expect(result.first.id, 'test-1');
    });

    test('handles empty response', () async {
      when(() => mockClient.get('/api/endpoint'))
          .thenAnswer((_) async => Response(data: []));

      final result = await repository.getData();

      expect(result, isEmpty);
    });

    test('throws on error', () async {
      when(() => mockClient.get('/api/endpoint'))
          .thenThrow(DioException(requestOptions: RequestOptions()));

      expect(() => repository.getData(), throwsException);
    });
  });
}
```

### Screen Test Pattern

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../../helpers/test_helpers.dart';

void main() {
  group('ScreenName', () {
    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          overrides: [
            providerProvider.overrideWith((_) => const AsyncLoading()),
          ],
          child: const ScreenName(),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays data when loaded', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          overrides: [
            providerProvider.overrideWith((_) => AsyncData(mockData)),
          ],
          child: const ScreenName(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Expected Text'), findsOneWidget);
    });

    testWidgets('shows error message on failure', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          overrides: [
            providerProvider.overrideWith(
              (_) => AsyncError(Exception('Error'), StackTrace.empty),
            ),
          ],
          child: const ScreenName(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('error'), findsOneWidget);
    });

    testWidgets('navigates on button tap', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          overrides: [
            providerProvider.overrideWith((_) => AsyncData(mockData)),
          ],
          child: const ScreenName(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // Verify navigation occurred
      expect(find.byType(NextScreen), findsOneWidget);
    });
  });
}
```

## Quick Commands

| Command | Description |
|---------|-------------|
| `/test-coverage` | Analyze coverage and suggest improvements |
| `/test-coverage --report` | Generate detailed HTML coverage report |
| `/test-coverage --generate lib/services/auth_service.dart` | Generate tests for specific file |
| `/test-coverage --provider auth` | Generate tests for auth provider |
| `/test-coverage --widget chat_bubble` | Generate widget tests |
| `/test-coverage --feature chat` | Generate tests for entire feature |
| `/test-coverage --ralph` | Loop until 80% coverage achieved |
| `/test-coverage --ralph --target 90` | Loop until 90% coverage achieved |

## Prerequisites

### Coverage Tools
```bash
# Ensure lcov is installed (macOS)
brew install lcov

# For HTML report generation
flutter pub global activate coverage
```

### Running Tests
```bash
# Run all tests
cd flutter_mobile && flutter test

# Run with coverage
cd flutter_mobile && flutter test --coverage

# Run specific test file
cd flutter_mobile && flutter test test/services/auth_service_test.dart

# Generate HTML report
genhtml flutter_mobile/coverage/lcov.info -o flutter_mobile/coverage/html
open flutter_mobile/coverage/html/index.html
```

## Code Generation Reminder

After generating tests that require mocks of generated classes:
```bash
cd flutter_mobile && dart run build_runner build --delete-conflicting-outputs
```

This ensures freezed classes and riverpod providers are up to date.
