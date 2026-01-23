import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/genui/amos_catalog.dart';
import 'package:amos_mobile/config/theme.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  /// Helper widget that builds GenUI content with proper context
  Widget buildWithContext(Widget Function(BuildContext context) builder) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (context) => builder(context),
          ),
        ),
      ),
    );
  }

  group('GenUIWidgetType', () {
    test('has all expected widget types', () {
      expect(GenUIWidgetType.values.length, equals(6));
      expect(GenUIWidgetType.values, contains(GenUIWidgetType.campaignCard));
      expect(GenUIWidgetType.values, contains(GenUIWidgetType.contactCard));
      expect(GenUIWidgetType.values, contains(GenUIWidgetType.landingPagePreview));
      expect(GenUIWidgetType.values, contains(GenUIWidgetType.statCard));
      expect(GenUIWidgetType.values, contains(GenUIWidgetType.taskCard));
      expect(GenUIWidgetType.values, contains(GenUIWidgetType.quickActionButton));
    });
  });

  group('CampaignCardData', () {
    test('creates with required fields', () {
      final data = CampaignCardData(name: 'Test Campaign');

      expect(data.name, equals('Test Campaign'));
      expect(data.status, equals('draft'));
      expect(data.recipientCount, equals(0));
      expect(data.id, isNull);
      expect(data.subject, isNull);
      expect(data.openRate, isNull);
      expect(data.clickRate, isNull);
    });

    test('creates with all fields', () {
      final data = CampaignCardData(
        id: 123,
        name: 'Summer Sale',
        subject: 'Big discounts!',
        status: 'sent',
        recipientCount: 5000,
        openRate: 45.5,
        clickRate: 12.3,
      );

      expect(data.id, equals(123));
      expect(data.name, equals('Summer Sale'));
      expect(data.subject, equals('Big discounts!'));
      expect(data.status, equals('sent'));
      expect(data.recipientCount, equals(5000));
      expect(data.openRate, equals(45.5));
      expect(data.clickRate, equals(12.3));
    });

    test('fromJson parses all fields', () {
      final json = {
        'id': 456,
        'name': 'Newsletter',
        'subject': 'Weekly Update',
        'status': 'scheduled',
        'recipientCount': 1000,
        'openRate': 35.0,
        'clickRate': 8.5,
      };

      final data = CampaignCardData.fromJson(json);

      expect(data.id, equals(456));
      expect(data.name, equals('Newsletter'));
      expect(data.subject, equals('Weekly Update'));
      expect(data.status, equals('scheduled'));
      expect(data.recipientCount, equals(1000));
      expect(data.openRate, equals(35.0));
      expect(data.clickRate, equals(8.5));
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final data = CampaignCardData.fromJson(json);

      expect(data.name, equals('Untitled Campaign'));
      expect(data.status, equals('draft'));
      expect(data.recipientCount, equals(0));
    });

    test('toJson returns correct map', () {
      final data = CampaignCardData(
        id: 1,
        name: 'Test',
        subject: 'Subject',
        status: 'sent',
        recipientCount: 100,
        openRate: 50.0,
        clickRate: 10.0,
      );

      final json = data.toJson();

      expect(json['id'], equals(1));
      expect(json['name'], equals('Test'));
      expect(json['subject'], equals('Subject'));
      expect(json['status'], equals('sent'));
      expect(json['recipientCount'], equals(100));
      expect(json['openRate'], equals(50.0));
      expect(json['clickRate'], equals(10.0));
    });
  });

  group('ContactCardData', () {
    test('creates with required fields', () {
      final data = ContactCardData(
        name: 'John Doe',
        email: 'john@example.com',
      );

      expect(data.name, equals('John Doe'));
      expect(data.email, equals('john@example.com'));
      expect(data.id, isNull);
      expect(data.company, isNull);
      expect(data.tags, isEmpty);
    });

    test('creates with all fields', () {
      final data = ContactCardData(
        id: 789,
        name: 'Jane Smith',
        email: 'jane@example.com',
        company: 'Acme Corp',
        tags: ['vip', 'premium'],
      );

      expect(data.id, equals(789));
      expect(data.company, equals('Acme Corp'));
      expect(data.tags, equals(['vip', 'premium']));
    });

    test('fromJson parses all fields', () {
      final json = {
        'id': 100,
        'name': 'Test User',
        'email': 'test@test.com',
        'company': 'Test Corp',
        'tags': ['tag1', 'tag2', 'tag3'],
      };

      final data = ContactCardData.fromJson(json);

      expect(data.id, equals(100));
      expect(data.name, equals('Test User'));
      expect(data.email, equals('test@test.com'));
      expect(data.company, equals('Test Corp'));
      expect(data.tags, equals(['tag1', 'tag2', 'tag3']));
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final data = ContactCardData.fromJson(json);

      expect(data.name, equals('Unknown'));
      expect(data.email, equals(''));
      expect(data.tags, isEmpty);
    });

    test('toJson returns correct map', () {
      final data = ContactCardData(
        id: 1,
        name: 'Test',
        email: 'test@test.com',
        company: 'Corp',
        tags: ['a', 'b'],
      );

      final json = data.toJson();

      expect(json['id'], equals(1));
      expect(json['name'], equals('Test'));
      expect(json['email'], equals('test@test.com'));
      expect(json['company'], equals('Corp'));
      expect(json['tags'], equals(['a', 'b']));
    });
  });

  group('StatCardData', () {
    test('creates with required fields', () {
      final data = StatCardData(
        label: 'Revenue',
        value: '\$1,000',
      );

      expect(data.label, equals('Revenue'));
      expect(data.value, equals('\$1,000'));
      expect(data.change, isNull);
      expect(data.icon, equals('trending-up'));
      expect(data.color, equals('blue'));
    });

    test('creates with all fields', () {
      final data = StatCardData(
        label: 'Users',
        value: '5,000',
        change: 25.5,
        icon: 'users',
        color: 'green',
      );

      expect(data.change, equals(25.5));
      expect(data.icon, equals('users'));
      expect(data.color, equals('green'));
    });

    test('fromJson parses all fields', () {
      final json = {
        'label': 'Conversions',
        'value': '123',
        'change': -5.2,
        'icon': 'target',
        'color': 'red',
      };

      final data = StatCardData.fromJson(json);

      expect(data.label, equals('Conversions'));
      expect(data.value, equals('123'));
      expect(data.change, equals(-5.2));
      expect(data.icon, equals('target'));
      expect(data.color, equals('red'));
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final data = StatCardData.fromJson(json);

      expect(data.label, equals(''));
      expect(data.value, equals('0'));
      expect(data.icon, equals('trending-up'));
      expect(data.color, equals('blue'));
    });

    test('toJson returns correct map', () {
      final data = StatCardData(
        label: 'Test',
        value: '42',
        change: 10.0,
        icon: 'mail',
        color: 'purple',
      );

      final json = data.toJson();

      expect(json['label'], equals('Test'));
      expect(json['value'], equals('42'));
      expect(json['change'], equals(10.0));
      expect(json['icon'], equals('mail'));
      expect(json['color'], equals('purple'));
    });
  });

  group('LandingPagePreviewData', () {
    test('creates with required fields', () {
      final data = LandingPagePreviewData(name: 'My Page');

      expect(data.name, equals('My Page'));
      expect(data.status, equals('draft'));
      expect(data.visits, equals(0));
      expect(data.conversions, equals(0));
      expect(data.id, isNull);
      expect(data.headline, isNull);
    });

    test('creates with all fields', () {
      final data = LandingPagePreviewData(
        id: 555,
        name: 'Product Launch',
        headline: 'Introducing our new product',
        status: 'published',
        visits: 10000,
        conversions: 500,
      );

      expect(data.id, equals(555));
      expect(data.headline, equals('Introducing our new product'));
      expect(data.status, equals('published'));
      expect(data.visits, equals(10000));
      expect(data.conversions, equals(500));
    });

    test('fromJson parses all fields', () {
      final json = {
        'id': 999,
        'name': 'Test Page',
        'headline': 'Test Headline',
        'status': 'published',
        'visits': 1234,
        'conversions': 56,
      };

      final data = LandingPagePreviewData.fromJson(json);

      expect(data.id, equals(999));
      expect(data.name, equals('Test Page'));
      expect(data.headline, equals('Test Headline'));
      expect(data.status, equals('published'));
      expect(data.visits, equals(1234));
      expect(data.conversions, equals(56));
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final data = LandingPagePreviewData.fromJson(json);

      expect(data.name, equals('Untitled Page'));
      expect(data.status, equals('draft'));
      expect(data.visits, equals(0));
      expect(data.conversions, equals(0));
    });

    test('toJson returns correct map', () {
      final data = LandingPagePreviewData(
        id: 1,
        name: 'Page',
        headline: 'Head',
        status: 'published',
        visits: 100,
        conversions: 10,
      );

      final json = data.toJson();

      expect(json['id'], equals(1));
      expect(json['name'], equals('Page'));
      expect(json['headline'], equals('Head'));
      expect(json['status'], equals('published'));
      expect(json['visits'], equals(100));
      expect(json['conversions'], equals(10));
    });
  });

  group('TaskCardData', () {
    test('creates with required fields', () {
      final data = TaskCardData(name: 'My Task');

      expect(data.name, equals('My Task'));
      expect(data.status, equals('active'));
      expect(data.id, isNull);
      expect(data.taskType, isNull);
      expect(data.scheduleType, isNull);
    });

    test('creates with all fields', () {
      final data = TaskCardData(
        id: 777,
        name: 'Daily Report',
        taskType: 'Email Report',
        status: 'completed',
        scheduleType: 'daily',
      );

      expect(data.id, equals(777));
      expect(data.taskType, equals('Email Report'));
      expect(data.status, equals('completed'));
      expect(data.scheduleType, equals('daily'));
    });

    test('fromJson parses all fields', () {
      final json = {
        'id': 888,
        'name': 'Weekly Backup',
        'taskType': 'Backup',
        'status': 'paused',
        'scheduleType': 'weekly',
      };

      final data = TaskCardData.fromJson(json);

      expect(data.id, equals(888));
      expect(data.name, equals('Weekly Backup'));
      expect(data.taskType, equals('Backup'));
      expect(data.status, equals('paused'));
      expect(data.scheduleType, equals('weekly'));
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final data = TaskCardData.fromJson(json);

      expect(data.name, equals('Untitled Task'));
      expect(data.status, equals('active'));
    });

    test('toJson returns correct map', () {
      final data = TaskCardData(
        id: 1,
        name: 'Task',
        taskType: 'Type',
        status: 'active',
        scheduleType: 'monthly',
      );

      final json = data.toJson();

      expect(json['id'], equals(1));
      expect(json['name'], equals('Task'));
      expect(json['taskType'], equals('Type'));
      expect(json['status'], equals('active'));
      expect(json['scheduleType'], equals('monthly'));
    });
  });

  group('GenUIWidgetBuilder.buildCampaignCard', () {
    testWidgets('renders draft campaign card', (tester) async {
      final data = CampaignCardData(
        name: 'Draft Campaign',
        subject: 'Test Subject',
        status: 'draft',
        recipientCount: 50,
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildCampaignCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Draft Campaign'), findsOneWidget);
      expect(find.text('Test Subject'), findsOneWidget);
      expect(find.text('DRAFT'), findsOneWidget);
      expect(find.textContaining('50 recipients'), findsOneWidget);
    });

    testWidgets('renders sent campaign with metrics', (tester) async {
      final data = CampaignCardData(
        name: 'Sent Campaign',
        status: 'sent',
        recipientCount: 1000,
        openRate: 45.5,
        clickRate: 12.3,
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildCampaignCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('SENT'), findsOneWidget);
      expect(find.textContaining('45.5% opens'), findsOneWidget);
      expect(find.textContaining('12.3% clicks'), findsOneWidget);
    });

    testWidgets('renders scheduled campaign', (tester) async {
      final data = CampaignCardData(
        name: 'Scheduled Campaign',
        status: 'scheduled',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildCampaignCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('SCHEDULED'), findsOneWidget);
    });
  });

  group('GenUIWidgetBuilder.buildContactCard', () {
    testWidgets('renders contact with basic info', (tester) async {
      final data = ContactCardData(
        name: 'John Doe',
        email: 'john@example.com',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildContactCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('john@example.com'), findsOneWidget);
      expect(find.text('J'), findsOneWidget); // Avatar initial
    });

    testWidgets('renders contact with company', (tester) async {
      final data = ContactCardData(
        name: 'Jane Smith',
        email: 'jane@acme.com',
        company: 'Acme Corp',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildContactCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Acme Corp'), findsOneWidget);
    });

    testWidgets('renders contact with tags', (tester) async {
      final data = ContactCardData(
        name: 'Tagged User',
        email: 'user@test.com',
        tags: ['vip', 'premium', 'enterprise'],
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildContactCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('vip'), findsOneWidget);
      expect(find.text('premium'), findsOneWidget);
      expect(find.text('enterprise'), findsOneWidget);
    });

    testWidgets('handles empty name with placeholder', (tester) async {
      final data = ContactCardData(
        name: '',
        email: 'empty@test.com',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildContactCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('?'), findsOneWidget); // Placeholder initial
    });
  });

  group('GenUIWidgetBuilder.buildStatCard', () {
    testWidgets('renders stat card with positive change', (tester) async {
      final data = StatCardData(
        label: 'Revenue',
        value: '\$10,000',
        change: 15.5,
        color: 'green',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildStatCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Revenue'), findsOneWidget);
      expect(find.text('\$10,000'), findsOneWidget);
      expect(find.textContaining('+15.5%'), findsOneWidget);
    });

    testWidgets('renders stat card with negative change', (tester) async {
      final data = StatCardData(
        label: 'Churn',
        value: '5%',
        change: -2.5,
        color: 'red',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildStatCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Churn'), findsOneWidget);
      expect(find.textContaining('-2.5%'), findsOneWidget);
    });

    testWidgets('renders stat card without change indicator', (tester) async {
      final data = StatCardData(
        label: 'Total Users',
        value: '1,234',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildStatCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Total Users'), findsOneWidget);
      expect(find.text('1,234'), findsOneWidget);
      // No percentage indicator
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('uses correct icon for mail', (tester) async {
      final data = StatCardData(
        label: 'Emails Sent',
        value: '500',
        icon: 'mail',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildStatCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.mail), findsOneWidget);
    });

    testWidgets('uses correct icon for users', (tester) async {
      final data = StatCardData(
        label: 'Active Users',
        value: '100',
        icon: 'users',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildStatCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.users), findsOneWidget);
    });
  });

  group('GenUIWidgetBuilder.buildLandingPagePreview', () {
    testWidgets('renders draft landing page', (tester) async {
      final data = LandingPagePreviewData(
        name: 'My Landing Page',
        headline: 'Welcome to our site',
        status: 'draft',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildLandingPagePreview(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('My Landing Page'), findsOneWidget);
      expect(find.text('Welcome to our site'), findsOneWidget);
      expect(find.text('DRAFT'), findsOneWidget);
    });

    testWidgets('renders published landing page with stats', (tester) async {
      final data = LandingPagePreviewData(
        name: 'Published Page',
        status: 'published',
        visits: 5000,
        conversions: 250,
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildLandingPagePreview(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PUBLISHED'), findsOneWidget);
      expect(find.textContaining('5000 visits'), findsOneWidget);
      expect(find.textContaining('250 conversions'), findsOneWidget);
    });

    testWidgets('has edit and view buttons', (tester) async {
      final data = LandingPagePreviewData(
        id: 123,
        name: 'Test Page',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildLandingPagePreview(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
    });
  });

  group('GenUIWidgetBuilder.buildTaskCard', () {
    testWidgets('renders active task', (tester) async {
      final data = TaskCardData(
        name: 'Daily Report',
        taskType: 'Email Report',
        status: 'active',
        scheduleType: 'daily',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildTaskCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Daily Report'), findsOneWidget);
      expect(find.text('Email Report'), findsOneWidget);
      expect(find.textContaining('daily'), findsOneWidget);
    });

    testWidgets('renders completed task', (tester) async {
      final data = TaskCardData(
        name: 'Completed Task',
        status: 'completed',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildTaskCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Completed Task'), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
    });

    testWidgets('renders paused task', (tester) async {
      final data = TaskCardData(
        name: 'Paused Task',
        status: 'paused',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildTaskCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Paused Task'), findsOneWidget);
      expect(find.byIcon(LucideIcons.pause), findsOneWidget);
    });

    testWidgets('renders failed task', (tester) async {
      final data = TaskCardData(
        name: 'Failed Task',
        status: 'failed',
      );

      await tester.pumpWidget(buildWithContext(
        (context) => GenUIWidgetBuilder.buildTaskCard(context, data),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Failed Task'), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleX), findsOneWidget);
    });
  });
}
