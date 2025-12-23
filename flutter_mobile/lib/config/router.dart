import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/screens/auth/login_screen.dart';
import 'package:amos_mobile/screens/auth/signup_screen.dart';
import 'package:amos_mobile/screens/auth/forgot_password_screen.dart';
import 'package:amos_mobile/screens/auth/mfa_verification_screen.dart';
import 'package:amos_mobile/screens/main/main_shell.dart';
import 'package:amos_mobile/screens/home/home_screen.dart';
import 'package:amos_mobile/screens/chat/chat_screen.dart';
import 'package:amos_mobile/screens/agents/agent_list_screen.dart';
import 'package:amos_mobile/screens/agents/agent_detail_screen.dart';
import 'package:amos_mobile/screens/settings/settings_screen.dart';
import 'package:amos_mobile/screens/settings/api_keys_screen.dart';
import 'package:amos_mobile/screens/settings/mfa_setup_screen.dart';
import 'package:amos_mobile/screens/settings/business_profile_screen.dart';
import 'package:amos_mobile/screens/campaigns/campaign_list_screen.dart';
import 'package:amos_mobile/screens/campaigns/campaign_detail_screen.dart';
import 'package:amos_mobile/screens/campaigns/campaign_form_screen.dart';
import 'package:amos_mobile/screens/contacts/contact_list_screen.dart';
import 'package:amos_mobile/screens/contacts/contact_detail_screen.dart';
import 'package:amos_mobile/screens/contacts/contact_form_screen.dart';
import 'package:amos_mobile/screens/contacts/contact_import_screen.dart';
import 'package:amos_mobile/screens/landing_pages/landing_page_list_screen.dart';
import 'package:amos_mobile/screens/landing_pages/landing_page_detail_screen.dart';
import 'package:amos_mobile/screens/tasks/task_list_screen.dart';
import 'package:amos_mobile/screens/tasks/task_detail_screen.dart';
import 'package:amos_mobile/screens/tasks/scheduled_task_form_screen.dart';
import 'package:amos_mobile/screens/connections/connections_list_screen.dart';
import 'package:amos_mobile/screens/analytics/analytics_screen.dart';
import 'package:amos_mobile/screens/email_templates/email_template_list_screen.dart';
import 'package:amos_mobile/screens/email_templates/email_template_detail_screen.dart';
import 'package:amos_mobile/screens/email_templates/email_template_form_screen.dart';
import 'package:amos_mobile/screens/notifications/notifications_screen.dart';
import 'package:amos_mobile/screens/inbox/inbox_screen.dart';
import 'package:amos_mobile/screens/marketplace/marketplace_screen.dart';
import 'package:amos_mobile/screens/profile/profile_screen.dart';
// Team Space screens
import 'package:amos_mobile/screens/team/team_channels_screen.dart';
import 'package:amos_mobile/screens/team/team_chat_screen.dart';
import 'package:amos_mobile/screens/team/team_members_screen.dart';
// Personal Space screens
import 'package:amos_mobile/screens/personal/personal_notes_screen.dart';
// Contact Groups screens
import 'package:amos_mobile/screens/contact_groups/contact_group_list_screen.dart';
import 'package:amos_mobile/screens/contact_groups/contact_group_detail_screen.dart';
// Documents screens
import 'package:amos_mobile/screens/documents/document_list_screen.dart';
import 'package:amos_mobile/screens/documents/document_detail_screen.dart';
// Hub screens
import 'package:amos_mobile/screens/marketing/marketing_hub_screen.dart';
import 'package:amos_mobile/screens/tools/tools_hub_screen.dart';
import 'package:amos_mobile/screens/more/more_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _GoRouterRefreshStream(ref, authStateProvider),
    redirect: (context, state) {
      // Read auth state directly in redirect callback, not in provider build
      final authState = ref.read(authStateProvider);
      final isLoggedIn = authState.isAuthenticated;
      final mfaRequired = authState.mfaRequired;
      final user = authState.user;
      final mfaEnabled = user?.mfaEnabled ?? false;

      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/forgot-password' ||
          state.matchedLocation == '/mfa-verification';
      final isMfaSetupRoute = state.matchedLocation == '/mfa-setup';

      // Allow MFA verification screen when MFA is required (during login)
      if (mfaRequired && state.matchedLocation != '/mfa-verification') {
        return '/mfa-verification';
      }

      // Force MFA setup if logged in but MFA not enabled
      if (isLoggedIn && !mfaEnabled && !isMfaSetupRoute) {
        return '/mfa-setup';
      }

      // Don't allow leaving MFA setup until it's enabled
      if (isLoggedIn && !mfaEnabled && isMfaSetupRoute) {
        return null; // Stay on MFA setup
      }

      if (!isLoggedIn && !isAuthRoute && !mfaRequired) {
        return '/login';
      }
      if (isLoggedIn && mfaEnabled && isAuthRoute) {
        return '/chat';  // Chat-first architecture
      }
      return null;
    },
    routes: [
      // Auth routes
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/mfa-verification',
        name: 'mfa-verification',
        builder: (context, state) => const MFAVerificationScreen(),
      ),

      // Main app shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          // Workspace routes (default)
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (context, state) => const HomeScreen(),
            routes: [
              GoRoute(
                path: 'campaigns',
                name: 'campaigns',
                builder: (context, state) => const CampaignListScreen(),
              ),
              GoRoute(
                path: 'campaigns/new',
                name: 'campaign-new',
                builder: (context, state) => const CampaignFormScreen(),
              ),
              GoRoute(
                path: 'campaigns/:id',
                name: 'campaign-detail',
                builder: (context, state) =>
                    CampaignDetailScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'campaigns/:id/edit',
                name: 'campaign-edit',
                builder: (context, state) =>
                    CampaignFormScreen(campaignId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'landing-pages',
                name: 'landing-pages',
                builder: (context, state) => const LandingPageListScreen(),
              ),
              GoRoute(
                path: 'landing-pages/:id',
                name: 'landing-page-detail',
                builder: (context, state) =>
                    LandingPageDetailScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'connections',
                name: 'connections',
                builder: (context, state) => const ConnectionsListScreen(),
              ),
              GoRoute(
                path: 'analytics',
                name: 'analytics',
                builder: (context, state) => const AnalyticsScreen(),
              ),
              GoRoute(
                path: 'email-templates',
                name: 'email-templates',
                builder: (context, state) => const EmailTemplateListScreen(),
              ),
              GoRoute(
                path: 'email-templates/new',
                name: 'email-template-new',
                builder: (context, state) => const EmailTemplateFormScreen(),
              ),
              GoRoute(
                path: 'email-templates/:id',
                name: 'email-template-detail',
                builder: (context, state) =>
                    EmailTemplateDetailScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'email-templates/:id/edit',
                name: 'email-template-edit',
                builder: (context, state) =>
                    EmailTemplateFormScreen(templateId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/chat',
            name: 'chat',
            builder: (context, state) {
              final initialPrompt = state.uri.queryParameters['prompt'];
              return ChatScreen(initialPrompt: initialPrompt);
            },
          ),
          GoRoute(
            path: '/agents',
            name: 'agents',
            builder: (context, state) => const AgentListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'agent-detail',
                builder: (context, state) =>
                    AgentDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/api-keys',
            name: 'api-keys',
            builder: (context, state) => const ApiKeysScreen(),
          ),
          GoRoute(
            path: '/mfa-setup',
            name: 'mfa-setup',
            builder: (context, state) => const MfaSetupScreen(),
          ),
          GoRoute(
            path: '/business-profile',
            name: 'business-profile',
            builder: (context, state) => const BusinessProfileScreen(),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/tasks',
            name: 'tasks',
            builder: (context, state) => const TaskListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                name: 'task-new',
                builder: (context, state) => const ScheduledTaskFormScreen(),
              ),
              GoRoute(
                path: ':id',
                name: 'task-detail',
                builder: (context, state) =>
                    TaskDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/notifications',
            name: 'notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/inbox',
            name: 'inbox',
            builder: (context, state) => const InboxScreen(),
          ),
          GoRoute(
            path: '/marketplace',
            name: 'marketplace',
            builder: (context, state) => const MarketplaceScreen(),
          ),
          GoRoute(
            path: '/contacts',
            name: 'contacts',
            builder: (context, state) => const ContactListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                name: 'contact-new',
                builder: (context, state) => const ContactFormScreen(),
              ),
              GoRoute(
                path: 'import',
                name: 'contact-import',
                builder: (context, state) => const ContactImportScreen(),
              ),
              GoRoute(
                path: ':id',
                name: 'contact-detail',
                builder: (context, state) =>
                    ContactDetailScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: ':id/edit',
                name: 'contact-edit',
                builder: (context, state) =>
                    ContactFormScreen(contactId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/contact-groups',
            name: 'contact-groups',
            builder: (context, state) => const ContactGroupListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'contact-group-detail',
                builder: (context, state) =>
                    ContactGroupDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/documents',
            name: 'documents',
            builder: (context, state) => const DocumentListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'document-detail',
                builder: (context, state) =>
                    DocumentDetailScreen(documentId: state.pathParameters['id']!),
              ),
            ],
          ),

          // Hub screens for 5-tab navigation
          GoRoute(
            path: '/marketing',
            name: 'marketing-hub',
            builder: (context, state) => const MarketingHubScreen(),
          ),
          GoRoute(
            path: '/tools',
            name: 'tools-hub',
            builder: (context, state) => const ToolsHubScreen(),
          ),
          GoRoute(
            path: '/more',
            name: 'more',
            builder: (context, state) => const MoreScreen(),
          ),

          // Team Space routes
          GoRoute(
            path: '/team-channels',
            name: 'team-channels',
            builder: (context, state) => const TeamChannelsScreen(),
          ),
          GoRoute(
            path: '/team-chat/:channelId',
            name: 'team-chat',
            builder: (context, state) => TeamChatScreen(
              channelId: state.pathParameters['channelId'],
            ),
          ),
          GoRoute(
            path: '/team-dm/:threadId',
            name: 'team-dm',
            builder: (context, state) => TeamChatScreen(
              threadId: state.pathParameters['threadId'],
            ),
          ),
          GoRoute(
            path: '/team-members',
            name: 'team-members',
            builder: (context, state) => const TeamMembersScreen(),
          ),

          // Personal Space routes
          GoRoute(
            path: '/personal-notes',
            name: 'personal-notes',
            builder: (context, state) => const PersonalNotesScreen(),
          ),
        ],
      ),
    ],
  );
});

// Helper class to refresh GoRouter when auth state changes
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(
    Ref ref,
    NotifierProvider<AuthNotifier, AuthState> provider,
  ) {
    // Listen to auth state changes via ref.listen
    ref.listen(provider, (previous, next) {
      notifyListeners();
    });
  }
}
