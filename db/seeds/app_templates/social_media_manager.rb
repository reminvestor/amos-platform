# frozen_string_literal: true

# Social Media Manager - Reference App Template
#
# This creates a fully functional Social Media Manager app with:
# - Posts module (create, schedule, publish)
# - Media Library module
# - Campaigns module
# - Calendar, Kanban, and List views
# - Approval workflow
# - AI Assistant for content creation
#
module AppTemplates
  class SocialMediaManager
    BLUEPRINT = {
      'app' => {
        'name' => 'Social Media Manager',
        'slug' => 'social_media_manager',
        'description' => 'Plan, create, schedule, and analyze social media content across all platforms',
        'icon' => 'share-2',
        'color' => '#1DA1F2'
      },
      'modules' => [
        {
          'name' => 'Posts',
          'slug' => 'posts',
          'description' => 'Social media posts and content',
          'icon' => 'edit-3',
          'is_primary' => true,
          'fields' => [
            # Content Section
            { 'name' => 'title', 'type' => 'string', 'label' => 'Post Title', 'required' => true, 'section' => 'content', 'order' => 1, 'help' => 'Internal reference name' },
            { 'name' => 'content', 'type' => 'text', 'label' => 'Post Content', 'required' => true, 'section' => 'content', 'order' => 2, 'ui_component' => 'rich_text_editor', 'ai_assist' => true },
            { 'name' => 'platforms', 'type' => 'multi_select', 'label' => 'Platforms', 'required' => true, 'section' => 'content', 'order' => 3, 'options' => ['Instagram', 'LinkedIn', 'Facebook', 'X', 'TikTok'] },
            { 'name' => 'media_urls', 'type' => 'json', 'label' => 'Media', 'section' => 'content', 'order' => 4, 'ui_component' => 'media_gallery' },
            { 'name' => 'hashtags', 'type' => 'string', 'label' => 'Hashtags', 'section' => 'content', 'order' => 5 },
            { 'name' => 'call_to_action', 'type' => 'string', 'label' => 'Call to Action', 'section' => 'content', 'order' => 6 },
            { 'name' => 'cta_link', 'type' => 'string', 'label' => 'CTA Link', 'section' => 'content', 'order' => 7 },
            
            # Scheduling Section
            { 'name' => 'scheduled_for', 'type' => 'datetime', 'label' => 'Scheduled For', 'section' => 'scheduling', 'order' => 1 },
            { 'name' => 'auto_publish', 'type' => 'boolean', 'label' => 'Auto Publish', 'section' => 'scheduling', 'order' => 2, 'default' => false },
            { 'name' => 'timezone', 'type' => 'string', 'label' => 'Timezone', 'section' => 'scheduling', 'order' => 3, 'default' => 'America/Los_Angeles' },
            
            # Workflow Section
            { 'name' => 'status', 'type' => 'select', 'label' => 'Status', 'required' => true, 'section' => 'workflow', 'order' => 1, 
              'options' => [
                { 'value' => 'draft', 'label' => 'Draft', 'color' => '#6B7280' },
                { 'value' => 'pending_review', 'label' => 'Pending Review', 'color' => '#F59E0B' },
                { 'value' => 'approved', 'label' => 'Approved', 'color' => '#10B981' },
                { 'value' => 'rejected', 'label' => 'Rejected', 'color' => '#EF4444' },
                { 'value' => 'scheduled', 'label' => 'Scheduled', 'color' => '#3B82F6' },
                { 'value' => 'published', 'label' => 'Published', 'color' => '#8B5CF6' }
              ], 
              'default' => 'draft' 
            },
            { 'name' => 'assigned_to', 'type' => 'string', 'label' => 'Assigned To', 'section' => 'workflow', 'order' => 2, 'ui_component' => 'user_select' },
            { 'name' => 'reviewer_notes', 'type' => 'text', 'label' => 'Reviewer Notes', 'section' => 'workflow', 'order' => 3, 'visibility' => 'edit_only', 'show_when' => { 'field' => 'status', 'in' => ['rejected', 'pending_review'] } },
            { 'name' => 'campaign_id', 'type' => 'reference', 'label' => 'Campaign', 'section' => 'workflow', 'order' => 4, 'reference_model' => 'campaigns' },
            
            # Metrics Section (read-only, system-managed)
            { 'name' => 'impressions', 'type' => 'integer', 'label' => 'Impressions', 'section' => 'metrics', 'order' => 1, 'visibility' => 'read_only', 'default' => 0 },
            { 'name' => 'reach', 'type' => 'integer', 'label' => 'Reach', 'section' => 'metrics', 'order' => 2, 'visibility' => 'read_only', 'default' => 0 },
            { 'name' => 'engagement', 'type' => 'integer', 'label' => 'Engagement', 'section' => 'metrics', 'order' => 3, 'visibility' => 'read_only', 'default' => 0 },
            { 'name' => 'clicks', 'type' => 'integer', 'label' => 'Clicks', 'section' => 'metrics', 'order' => 4, 'visibility' => 'read_only', 'default' => 0 },
            { 'name' => 'published_at', 'type' => 'datetime', 'label' => 'Published At', 'section' => 'metrics', 'order' => 5, 'visibility' => 'read_only' },
            
            # Advanced Section
            { 'name' => 'notes', 'type' => 'text', 'label' => 'Internal Notes', 'section' => 'advanced', 'order' => 1 },
            { 'name' => 'target_audience', 'type' => 'string', 'label' => 'Target Audience', 'section' => 'advanced', 'order' => 2 }
          ],
          'canvases' => [
            { 'type' => 'list', 'name' => 'All Posts', 'slug' => 'posts_list', 'is_default' => true, 
              'columns' => ['title', 'platforms', 'status', 'scheduled_for'], 
              'filters' => ['status', 'platforms'] },
            { 'type' => 'form', 'name' => 'Post Editor', 'slug' => 'posts_form', 'layout' => 'tabbed',
              'tabs' => [
                { 'name' => 'content', 'label' => 'Content', 'icon' => 'edit-3', 'sections' => ['content'] },
                { 'name' => 'scheduling', 'label' => 'Schedule', 'icon' => 'calendar', 'sections' => ['scheduling'] },
                { 'name' => 'workflow', 'label' => 'Workflow', 'icon' => 'git-branch', 'sections' => ['workflow'] },
                { 'name' => 'metrics', 'label' => 'Performance', 'icon' => 'bar-chart', 'sections' => ['metrics'], 'show_when' => { 'field' => 'status', 'equals' => 'published' } }
              ]
            },
            { 'type' => 'calendar', 'name' => 'Content Calendar', 'slug' => 'posts_calendar',
              'card_config' => { 'date_field' => 'scheduled_for', 'title_field' => 'title', 'color_field' => 'status' } },
            { 'type' => 'kanban', 'name' => 'Workflow Board', 'slug' => 'posts_board',
              'card_config' => { 'column_field' => 'status', 'card_fields' => ['title', 'platforms', 'scheduled_for'] } }
          ],
          'actions' => [
            { 'name' => 'Submit for Review', 'slug' => 'submit_for_review', 'icon' => 'send', 'style' => 'primary', 'location' => 'toolbar',
              'show_when' => { 'field' => 'status', 'equals' => 'draft' },
              'behavior_type' => 'update', 'behavior_config' => { 'updates' => { 'status' => 'pending_review' } } },
            { 'name' => 'Approve', 'slug' => 'approve', 'icon' => 'check', 'style' => 'success', 'location' => 'toolbar',
              'show_when' => { 'field' => 'status', 'equals' => 'pending_review' },
              'behavior_type' => 'update', 'behavior_config' => { 'updates' => { 'status' => 'approved' } } },
            { 'name' => 'Reject', 'slug' => 'reject', 'icon' => 'x', 'style' => 'danger', 'location' => 'toolbar',
              'show_when' => { 'field' => 'status', 'equals' => 'pending_review' },
              'behavior_type' => 'modal_form', 'behavior_config' => { 'fields' => ['reviewer_notes'], 'on_submit' => { 'type' => 'update', 'updates' => { 'status' => 'rejected' } } } },
            { 'name' => 'Schedule', 'slug' => 'schedule', 'icon' => 'calendar', 'style' => 'primary', 'location' => 'toolbar',
              'show_when' => { 'field' => 'status', 'in' => ['draft', 'approved'] },
              'behavior_type' => 'modal_form', 'behavior_config' => { 'fields' => ['scheduled_for', 'auto_publish'], 'on_submit' => { 'type' => 'update', 'updates' => { 'status' => 'scheduled' } } } },
            { 'name' => 'AI Write', 'slug' => 'ai_write', 'icon' => 'sparkles', 'style' => 'outline', 'location' => 'field', 'target_field' => 'content',
              'behavior_type' => 'agent_assist', 'behavior_config' => { 'agent' => 'app_assistant', 'prompt' => 'Help me write an engaging social media post' } }
          ]
        },
        {
          'name' => 'Campaigns',
          'slug' => 'campaigns',
          'description' => 'Marketing campaigns to group related posts',
          'icon' => 'target',
          'is_primary' => false,
          'fields' => [
            { 'name' => 'name', 'type' => 'string', 'label' => 'Campaign Name', 'required' => true, 'section' => 'content', 'order' => 1 },
            { 'name' => 'description', 'type' => 'text', 'label' => 'Description', 'section' => 'content', 'order' => 2 },
            { 'name' => 'start_date', 'type' => 'date', 'label' => 'Start Date', 'section' => 'content', 'order' => 3 },
            { 'name' => 'end_date', 'type' => 'date', 'label' => 'End Date', 'section' => 'content', 'order' => 4 },
            { 'name' => 'status', 'type' => 'select', 'label' => 'Status', 'section' => 'content', 'order' => 5, 'options' => ['planning', 'active', 'completed', 'paused'], 'default' => 'planning' },
            { 'name' => 'goals', 'type' => 'text', 'label' => 'Goals', 'section' => 'content', 'order' => 6 },
            { 'name' => 'budget', 'type' => 'decimal', 'label' => 'Budget', 'section' => 'content', 'order' => 7 }
          ],
          'canvases' => [
            { 'type' => 'list', 'name' => 'All Campaigns', 'slug' => 'campaigns_list', 'is_default' => true, 'columns' => ['name', 'status', 'start_date', 'end_date'] },
            { 'type' => 'form', 'name' => 'Campaign Editor', 'slug' => 'campaigns_form', 'layout' => 'single_column' }
          ],
          'actions' => []
        },
        {
          'name' => 'Media Library',
          'slug' => 'media_library',
          'description' => 'Store and organize images and videos',
          'icon' => 'image',
          'is_primary' => false,
          'fields' => [
            { 'name' => 'name', 'type' => 'string', 'label' => 'Name', 'required' => true, 'section' => 'content', 'order' => 1 },
            { 'name' => 'file_url', 'type' => 'string', 'label' => 'File URL', 'required' => true, 'section' => 'content', 'order' => 2 },
            { 'name' => 'file_type', 'type' => 'select', 'label' => 'Type', 'section' => 'content', 'order' => 3, 'options' => ['image', 'video', 'gif', 'document'] },
            { 'name' => 'alt_text', 'type' => 'string', 'label' => 'Alt Text', 'section' => 'content', 'order' => 4 },
            { 'name' => 'tags', 'type' => 'string', 'label' => 'Tags', 'section' => 'content', 'order' => 5 },
            { 'name' => 'folder', 'type' => 'string', 'label' => 'Folder', 'section' => 'content', 'order' => 6, 'default' => 'Uncategorized' }
          ],
          'canvases' => [
            { 'type' => 'list', 'name' => 'Media Library', 'slug' => 'media_library_list', 'is_default' => true, 'columns' => ['name', 'file_type', 'folder'] },
            { 'type' => 'form', 'name' => 'Upload Media', 'slug' => 'media_library_form', 'layout' => 'single_column' }
          ],
          'actions' => []
        }
      ],
      'workflows' => [
        {
          'name' => 'Auto-Publish Scheduled Posts',
          'trigger' => { 'type' => 'scheduled', 'cron' => '*/5 * * * *' },
          'conditions' => [
            { 'field' => 'status', 'equals' => 'scheduled' },
            { 'field' => 'scheduled_for', 'less_than' => 'now' },
            { 'field' => 'auto_publish', 'equals' => true }
          ],
          'actions' => [
            { 'type' => 'update', 'updates' => { 'status' => 'published', 'published_at' => 'now' } }
          ]
        }
      ],
      'app_assistant' => {
        'name' => 'Social Media Strategist',
        'slug' => 'social_media_strategist',
        'icon' => 'trending-up',
        'persona' => <<~PERSONA,
          You are a social media expert who helps users create engaging content.
          You understand platform best practices:
          - LinkedIn: Professional, thought leadership, industry insights
          - Instagram: Visual storytelling, lifestyle, behind-the-scenes
          - Facebook: Community building, events, longer-form content
          - X/Twitter: Concise, timely, conversational, hashtags
          - TikTok: Trendy, entertaining, short-form video
          
          You help with:
          - Writing compelling post copy
          - Suggesting optimal posting times
          - Recommending hashtags
          - Analyzing what content performs best
          - Planning content calendars
        PERSONA
        'capabilities' => [
          { 'name' => 'Write Posts', 'description' => 'Generate engaging social media content for any platform' },
          { 'name' => 'Suggest Hashtags', 'description' => 'Recommend relevant hashtags for maximum reach' },
          { 'name' => 'Optimize Timing', 'description' => 'Suggest the best times to post for your audience' },
          { 'name' => 'Analyze Performance', 'description' => 'Review what content works and suggest improvements' },
          { 'name' => 'Plan Content', 'description' => 'Help create weekly or monthly content calendars' }
        ],
        'tools' => ['create_post', 'get_posts', 'update_post', 'get_campaigns', 'create_campaign']
      },
      'integrations' => [
        { 'platform' => 'linkedin', 'operations' => ['publish_post', 'get_metrics'] },
        { 'platform' => 'facebook', 'operations' => ['publish_post', 'get_metrics'] }
      ]
    }.freeze
    
    def self.install(entity:, user:)
      Rails.logger.info "[AppTemplates] Installing Social Media Manager for entity #{entity.id}"
      
      # Create the app
      app = App.create!(
        entity: entity,
        created_by: user,
        name: BLUEPRINT['app']['name'],
        slug: BLUEPRINT['app']['slug'],
        description: BLUEPRINT['app']['description'],
        status: 'building',
        blueprint: BLUEPRINT,
        intent: {
          'source' => 'template',
          'template_name' => 'social_media_manager',
          'installed_at' => Time.current.iso8601
        },
        metadata: {}
      )
      
      # Use the build_app tool logic to create everything
      builder = Tools::BuildAppTool.new(user: user, entity: entity)
      result = builder.execute({ app_id: app.id })
      
      if result[:success]
        Rails.logger.info "[AppTemplates] Successfully installed Social Media Manager"
        app.reload
      else
        Rails.logger.error "[AppTemplates] Failed to install: #{result[:error]}"
        app.update!(status: 'designing', metadata: { install_error: result[:error] })
      end
      
      app
    end
  end
end





