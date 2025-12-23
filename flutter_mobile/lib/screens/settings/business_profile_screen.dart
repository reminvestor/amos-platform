import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/services/business_profile_service.dart';

class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  ConsumerState<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final BusinessProfileService _service = BusinessProfileService();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  BusinessProfile? _profile;

  // Form controllers
  final _nameController = TextEditingController();
  final _industryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _websiteController = TextEditingController();
  final _foundedYearController = TextEditingController();
  final _valuesController = TextEditingController();
  final _targetAudienceController = TextEditingController();
  final _toneOfVoiceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _industryController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    _foundedYearController.dispose();
    _valuesController.dispose();
    _targetAudienceController.dispose();
    _toneOfVoiceController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile = await _service.getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _nameController.text = profile.name ?? '';
          _industryController.text = profile.industry ?? '';
          _descriptionController.text = profile.description ?? '';
          _websiteController.text = profile.website ?? '';
          _foundedYearController.text = profile.foundedYear?.toString() ?? '';
          _valuesController.text = profile.values ?? '';
          _targetAudienceController.text = profile.targetAudience ?? '';
          _toneOfVoiceController.text = profile.toneOfVoice ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final data = {
        'name': _nameController.text,
        'industry': _industryController.text,
        'description': _descriptionController.text,
        'website': _websiteController.text.isNotEmpty ? _websiteController.text : null,
        'founded_year': _foundedYearController.text.isNotEmpty
            ? int.tryParse(_foundedYearController.text)
            : null,
        'values': _valuesController.text.isNotEmpty ? _valuesController.text : null,
        'target_audience': _targetAudienceController.text.isNotEmpty
            ? _targetAudienceController.text
            : null,
        'tone_of_voice': _toneOfVoiceController.text.isNotEmpty
            ? _toneOfVoiceController.text
            : null,
      };

      await _service.updateProfile(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Business profile updated'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Business Profile'),
        actions: [
          if (!_isLoading && _profile != null)
            TextButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.save, size: 18),
              label: const Text('Save'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _buildForm(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.circleAlert, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 16),
          Text('Failed to load profile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _loadProfile, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Business Info Section
          _SectionHeader(
            title: 'Business Information',
            icon: LucideIcons.building2,
          ),
          const SizedBox(height: 12),

          _buildTextField(
            controller: _nameController,
            label: 'Business Name',
            hint: 'Your company name',
            icon: LucideIcons.building,
            required: true,
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _industryController,
            label: 'Industry',
            hint: 'e.g., Technology, Healthcare, Finance',
            icon: LucideIcons.briefcase,
            required: true,
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _descriptionController,
            label: 'Description',
            hint: 'Brief description of your business',
            icon: LucideIcons.fileText,
            maxLines: 3,
            required: true,
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _websiteController,
                  label: 'Website',
                  hint: 'https://example.com',
                  icon: LucideIcons.globe,
                  keyboardType: TextInputType.url,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: _buildTextField(
                  controller: _foundedYearController,
                  label: 'Founded',
                  hint: '2020',
                  icon: LucideIcons.calendar,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Brand Voice Section
          _SectionHeader(
            title: 'Brand Voice',
            icon: LucideIcons.megaphone,
          ),
          const SizedBox(height: 12),

          _buildTextField(
            controller: _valuesController,
            label: 'Core Values',
            hint: 'Innovation, integrity, customer-first...',
            icon: LucideIcons.heart,
            maxLines: 2,
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _targetAudienceController,
            label: 'Target Audience',
            hint: 'Who are your ideal customers?',
            icon: LucideIcons.users,
            maxLines: 2,
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _toneOfVoiceController,
            label: 'Tone of Voice',
            hint: 'Professional, friendly, casual...',
            icon: LucideIcons.messageCircle,
            maxLines: 2,
          ),
          const SizedBox(height: 32),

          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.sparkles, color: context.primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This information helps Amos generate content that matches your brand voice and style.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      validator: required
          ? (value) {
              if (value == null || value.isEmpty) {
                return '$label is required';
              }
              return null;
            }
          : null,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: context.primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
