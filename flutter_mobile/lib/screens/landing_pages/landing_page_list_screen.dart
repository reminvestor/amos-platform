import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/landing_page.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:intl/intl.dart';

class LandingPageListScreen extends ConsumerStatefulWidget {
  const LandingPageListScreen({super.key});

  @override
  ConsumerState<LandingPageListScreen> createState() =>
      _LandingPageListScreenState();
}

class _LandingPageListScreenState extends ConsumerState<LandingPageListScreen> {
  @override
  void initState() {
    super.initState();
    _loadLandingPages();
  }

  Future<void> _loadLandingPages() async {
    ref.read(landingPagesLoadingProvider.notifier).setLoading(true);
    // TODO: Implement actual API call
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock data
    ref.read(landingPagesProvider.notifier).setLandingPages([
      LandingPage(
        id: '1',
        entityId: 'e1',
        title: 'Product Launch',
        slug: 'product-launch',
        status: LandingPageStatus.published,
        htmlContent: '',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        updatedAt: DateTime.now(),
        viewCount: 1250,
        submissionCount: 85,
        publishedAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      LandingPage(
        id: '2',
        entityId: 'e1',
        title: 'Holiday Sale',
        slug: 'holiday-sale',
        status: LandingPageStatus.draft,
        htmlContent: '',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now(),
      ),
      LandingPage(
        id: '3',
        entityId: 'e1',
        title: 'Newsletter Signup',
        slug: 'newsletter',
        status: LandingPageStatus.published,
        htmlContent: '',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        updatedAt: DateTime.now(),
        viewCount: 3400,
        submissionCount: 420,
        publishedAt: DateTime.now().subtract(const Duration(days: 9)),
      ),
    ]);

    ref.read(landingPagesLoadingProvider.notifier).setLoading(false);
  }

  @override
  Widget build(BuildContext context) {
    final landingPages = ref.watch(landingPagesProvider);
    final isLoading = ref.watch(landingPagesLoadingProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Landing Pages'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () {
              // TODO: Create landing page
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : landingPages.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadLandingPages,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: landingPages.length,
                    itemBuilder: (context, index) {
                      final page = landingPages[index];
                      return _LandingPageCard(
                        landingPage: page,
                        onTap: () {
                          // TODO: View landing page
                        },
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.layoutGrid,
              size: 64,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Landing Pages',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first landing page to capture leads.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: Create landing page
              },
              icon: const Icon(LucideIcons.plus),
              label: const Text('Create Landing Page'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingPageCard extends StatelessWidget {
  final LandingPage landingPage;
  final VoidCallback onTap;

  const _LandingPageCard({
    required this.landingPage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPublished = landingPage.status == LandingPageStatus.published;
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.layoutGrid,
                      color: context.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          landingPage.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          '/${landingPage.slug}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isPublished
                          ? Colors.green.withOpacity(0.1)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isPublished ? 'Published' : 'Draft',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isPublished ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              if (isPublished) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    _StatItem(
                      icon: LucideIcons.eye,
                      value: '${landingPage.viewCount ?? 0}',
                      label: 'Views',
                    ),
                    const SizedBox(width: 24),
                    _StatItem(
                      icon: LucideIcons.userCheck,
                      value: '${landingPage.submissionCount ?? 0}',
                      label: 'Submissions',
                    ),
                    const Spacer(),
                    Text(
                      dateFormat.format(landingPage.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textTertiary,
                          ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: context.textTertiary),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.textTertiary,
              ),
        ),
      ],
    );
  }
}
