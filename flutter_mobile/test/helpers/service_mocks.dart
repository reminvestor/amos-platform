import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/agent.dart';
import 'package:amos_mobile/models/campaign.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/models/document.dart';
import 'package:amos_mobile/models/scheduled_task.dart';

/// Sets up common platform channel mocks needed for widget testing
///
/// Call this in setUpAll() for any test that uses platform channels:
/// ```dart
/// setUpAll(() {
///   setupPlatformChannelMocks();
/// });
/// ```
void setupPlatformChannelMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock flutter_secure_storage
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'read':
          return null;
        case 'write':
          return null;
        case 'delete':
          return null;
        case 'deleteAll':
          return null;
        case 'readAll':
          return <String, String>{};
        case 'containsKey':
          return false;
        default:
          return null;
      }
    },
  );

  // Mock path_provider
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getTemporaryDirectory':
          return '/tmp';
        case 'getApplicationDocumentsDirectory':
          return '/tmp/docs';
        case 'getApplicationSupportDirectory':
          return '/tmp/support';
        default:
          return null;
      }
    },
  );
}

/// Clears all platform channel mocks
///
/// Call this in tearDownAll():
/// ```dart
/// tearDownAll(() {
///   clearPlatformChannelMocks();
/// });
/// ```
void clearPlatformChannelMocks() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    null,
  );
}

/// Factory for creating mock data objects for testing

class MockDataFactory {
  /// Creates a mock Agent for testing
  static Agent createAgent({
    String id = '1',
    String name = 'Test Agent',
    String description = 'A test agent for testing purposes',
    AgentType agentType = AgentType.executor,
    bool interactive = false,
    String icon = 'bot',
    List<String>? capabilities,
    List<AgentTool>? tools,
  }) {
    return Agent(
      id: id,
      name: name,
      description: description,
      agentType: agentType,
      interactive: interactive,
      icon: icon,
      capabilities: capabilities,
      tools: tools,
      createdAt: DateTime.now(),
    );
  }

  /// Creates a list of mock Agents
  static List<Agent> createAgentList({int count = 3}) {
    return List.generate(
      count,
      (i) => createAgent(
        id: '${i + 1}',
        name: 'Agent ${i + 1}',
        description: 'Description for agent ${i + 1}',
        agentType: AgentType.values[i % AgentType.values.length],
      ),
    );
  }

  /// Creates a mock Campaign for testing
  static Campaign createCampaign({
    int id = 1,
    String name = 'Test Campaign',
    String subject = 'Test Subject',
    String status = 'draft',
    int recipientCount = 100,
    int sentCount = 0,
    int openedCount = 0,
    int clickedCount = 0,
  }) {
    return Campaign(
      id: id,
      name: name,
      subject: subject,
      status: status,
      recipientCount: recipientCount,
      sentCount: sentCount,
      openedCount: openedCount,
      clickedCount: clickedCount,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a list of mock Campaigns
  static List<Campaign> createCampaignList({int count = 3}) {
    final statuses = ['draft', 'scheduled', 'sending', 'sent'];
    return List.generate(
      count,
      (i) => createCampaign(
        id: i + 1,
        name: 'Campaign ${i + 1}',
        status: statuses[i % statuses.length],
      ),
    );
  }

  /// Creates a mock Contact for testing
  static Contact createContact({
    int id = 1,
    String email = 'test@example.com',
    String? firstName,
    String? lastName,
    String? phone,
    String? company,
    String status = 'active',
  }) {
    return Contact(
      id: id,
      email: email,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      company: company,
      status: status,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a list of mock Contacts
  static List<Contact> createContactList({int count = 5}) {
    return List.generate(
      count,
      (i) => createContact(
        id: i + 1,
        email: 'contact${i + 1}@example.com',
        firstName: 'First$i',
        lastName: 'Last$i',
      ),
    );
  }

  /// Creates a mock Document for testing
  static Document createDocument({
    int id = 1,
    String title = 'Test Document',
    String? description,
    String contentType = 'application/pdf',
    String status = 'ready',
    int fileSize = 1024,
  }) {
    return Document(
      id: id,
      title: title,
      description: description,
      contentType: contentType,
      status: status,
      fileSize: fileSize,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a mock ScheduledTask for testing
  static ScheduledTask createScheduledTask({
    int id = 1,
    String name = 'Test Task',
    String? description,
    String taskType = 'custom',
    String scheduleType = 'daily',
    String status = 'active',
    bool enabled = true,
    int runCount = 0,
    int failureCount = 0,
  }) {
    return ScheduledTask(
      id: id,
      name: name,
      description: description,
      taskType: taskType,
      taskTypeInfo: TaskTypeInfo(
        name: 'Custom',
        description: 'Custom task type',
        icon: '',
      ),
      scheduleType: scheduleType,
      status: status,
      enabled: enabled,
      runCount: runCount,
      failureCount: failureCount,
      consecutiveFailures: 0,
      canRun: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a list of mock ScheduledTasks
  static List<ScheduledTask> createScheduledTaskList({int count = 3}) {
    final statuses = ['active', 'paused', 'completed', 'failed'];
    return List.generate(
      count,
      (i) => createScheduledTask(
        id: i + 1,
        name: 'Task ${i + 1}',
        status: statuses[i % statuses.length],
      ),
    );
  }
}
