import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/chat.dart';
import 'package:amos_mobile/models/agent.dart';
import 'package:amos_mobile/models/campaign.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/models/landing_page.dart';
import 'package:amos_mobile/models/model_option.dart';
import 'package:amos_mobile/models/uploaded_file.dart';

// ============ Chat Providers ============
class ChatMessagesNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => [];

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void updateMessage(ChatMessage message) {
    final index = state.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      final newState = [...state];
      newState[index] = message;
      state = newState;
    }
  }

  void updateLastMessage(ChatMessage message) {
    if (state.isEmpty) return;
    state = [...state.sublist(0, state.length - 1), message];
  }

  void clear() => state = [];
}

class ChatLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool loading) => state = loading;
}

// Chat session ID
class ChatSessionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setSession(String sessionId) => state = sessionId;
  void clear() => state = null;
}

// Selected AI model
class SelectedModelNotifier extends Notifier<String> {
  @override
  String build() => ModelOption.defaultModel.id;

  void setModel(String modelId) => state = modelId;
}

// Status message (transient)
class ChatStatusNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setStatus(String? status) => state = status;
  void clear() => state = null;
}

// Attached files for next message
class AttachedFilesNotifier extends Notifier<List<UploadedFile>> {
  @override
  List<UploadedFile> build() => [];

  void addFile(UploadedFile file) {
    state = [...state, file];
  }

  void addFiles(List<UploadedFile> files) {
    state = [...state, ...files];
  }

  void removeFile(String assetId) {
    state = state.where((f) => f.assetId != assetId).toList();
  }

  void clear() => state = [];
}

final chatMessagesProvider =
    NotifierProvider<ChatMessagesNotifier, List<ChatMessage>>(
        ChatMessagesNotifier.new);
final chatLoadingProvider =
    NotifierProvider<ChatLoadingNotifier, bool>(ChatLoadingNotifier.new);
final chatSessionProvider =
    NotifierProvider<ChatSessionNotifier, String?>(ChatSessionNotifier.new);
final selectedModelProvider =
    NotifierProvider<SelectedModelNotifier, String>(SelectedModelNotifier.new);
final chatStatusProvider =
    NotifierProvider<ChatStatusNotifier, String?>(ChatStatusNotifier.new);
final attachedFilesProvider =
    NotifierProvider<AttachedFilesNotifier, List<UploadedFile>>(
        AttachedFilesNotifier.new);

// ============ Agent Providers ============
class AgentsNotifier extends Notifier<List<Agent>> {
  @override
  List<Agent> build() => [];

  void setAgents(List<Agent> agents) => state = agents;
}

class AgentsLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool loading) => state = loading;
}

final agentsProvider =
    NotifierProvider<AgentsNotifier, List<Agent>>(AgentsNotifier.new);
final agentsLoadingProvider =
    NotifierProvider<AgentsLoadingNotifier, bool>(AgentsLoadingNotifier.new);

// ============ Campaign Providers ============
class CampaignsNotifier extends Notifier<List<Campaign>> {
  @override
  List<Campaign> build() => [];

  void setCampaigns(List<Campaign> campaigns) => state = campaigns;
}

class CampaignsLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool loading) => state = loading;
}

final campaignsProvider =
    NotifierProvider<CampaignsNotifier, List<Campaign>>(CampaignsNotifier.new);
final campaignsLoadingProvider =
    NotifierProvider<CampaignsLoadingNotifier, bool>(
        CampaignsLoadingNotifier.new);

// ============ Contact Providers ============
class ContactsNotifier extends Notifier<List<Contact>> {
  @override
  List<Contact> build() => [];

  void setContacts(List<Contact> contacts) => state = contacts;
}

class ContactsLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool loading) => state = loading;
}

final contactsProvider =
    NotifierProvider<ContactsNotifier, List<Contact>>(ContactsNotifier.new);
final contactsLoadingProvider =
    NotifierProvider<ContactsLoadingNotifier, bool>(
        ContactsLoadingNotifier.new);

// ============ Landing Page Providers ============
class LandingPagesNotifier extends Notifier<List<LandingPage>> {
  @override
  List<LandingPage> build() => [];

  void setLandingPages(List<LandingPage> pages) => state = pages;
}

class LandingPagesLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool loading) => state = loading;
}

final landingPagesProvider =
    NotifierProvider<LandingPagesNotifier, List<LandingPage>>(
        LandingPagesNotifier.new);
final landingPagesLoadingProvider =
    NotifierProvider<LandingPagesLoadingNotifier, bool>(
        LandingPagesLoadingNotifier.new);
