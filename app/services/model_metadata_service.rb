# == Model Metadata Service
#
# This service provides comprehensive metadata and descriptions for all business models
# in the system. It helps AI assistants (like Claude) understand:
# - What each model represents
# - How models relate to each other  
# - What fields are available
# - Usage patterns and examples
# - Business context and purpose
#
# == Usage:
# metadata = ModelMetadataService.get_model_info('Campaign')
# all_models = ModelMetadataService.all_models
# description = ModelMetadataService.get_model_description('Contact')
#
class ModelMetadataService
  
  # Get metadata for a specific model
  # @param model_name [String] The model class name (e.g., 'Campaign', 'Contact')
  # @return [Hash] Complete metadata for the model
  def self.get_model_info(model_name)
    model_metadata[model_name.to_s] || {}
  end
  
  # Get just the description for a model
  # @param model_name [String] The model class name
  # @return [String] Description of what the model represents
  def self.get_model_description(model_name)
    get_model_info(model_name)[:description] || "Unknown model: #{model_name}"
  end
  
  # Get all available models with their basic info
  # @return [Hash] Hash of model names to basic descriptions
  def self.all_models
    model_metadata.transform_values { |info| info[:description] }
  end
  
  # Get models related to a specific model
  # @param model_name [String] The model class name
  # @return [Array] Array of related model names
  def self.related_models(model_name)
    get_model_info(model_name)[:relationships]&.keys || []
  end
  
  # Get business context for a model
  # @param model_name [String] The model class name  
  # @return [String] Business purpose and usage context
  def self.business_context(model_name)
    get_model_info(model_name)[:business_context] || ""
  end
  
  private
  
  # Complete metadata for all business models
  def self.model_metadata
    {
      'Campaign' => {
        description: 'Email marketing campaigns that send messages to groups of contacts',
        purpose: 'Drive engagement, conversions, and customer communication through targeted email messaging',
        business_context: 'Campaigns are the core marketing tool for reaching customers. They can be one-time sends or drip sequences.',
        key_fields: {
          name: 'Campaign title/name',
          subject: 'Email subject line',
          content: 'Email body content (HTML/text)',
          status: 'draft, sent, or scheduled',
          send_at: 'When to send (for scheduled campaigns)',
          mailgun_stats: 'Delivery statistics (sent, delivered, opened, clicked, bounced)',
          entity_id: 'Organization that owns this campaign',
          user_id: 'Creator of the campaign',
          contact_group_id: 'Target audience for the campaign'
        },
        relationships: {
          belongs_to: ['Entity', 'User', 'ContactGroup'],
          has_many: ['EmailDeliveries', 'LandingPages']
        },
        usage_examples: [
          'Newsletter campaigns to subscribers',
          'Product launch announcements',
          'Welcome email sequences for new customers',
          'Re-engagement campaigns for inactive users',
          'Promotional offers and discounts'
        ],
        typical_queries: [
          'Recent campaign performance',
          'Best performing campaigns by open rate',
          'Campaigns with low engagement',
          'Campaign delivery statistics'
        ]
      },
      
      'Contact' => {
        description: 'Individual people/customers that can receive marketing campaigns',
        purpose: 'Store customer information and track engagement for personalized marketing',
        business_context: 'Contacts are the foundation of marketing - they represent real people who have shown interest in the business.',
        key_fields: {
          first_name: 'Contact first name',
          last_name: 'Contact last name', 
          email: 'Primary email address (required)',
          phone: 'Phone number',
          company: 'Company/organization name',
          job_title: 'Professional title',
          lead_source: 'How they found you (website, referral, etc.)',
          tags: 'Categorization labels',
          entity_id: 'Organization that owns this contact',
          user_id: 'User who created/manages this contact'
        },
        relationships: {
          belongs_to: ['Entity', 'User'],
          has_many: ['EmailDeliveries', 'ContactGroupsContacts'],
          has_many_through: ['ContactGroups']
        },
        usage_examples: [
          'Website visitors who fill out forms',
          'Customers who make purchases',
          'Newsletter subscribers',
          'Event attendees',
          'Demo request leads'
        ],
        typical_queries: [
          'Most engaged contacts',
          'Recent sign-ups',
          'Contacts by lead source',
          'Unengaged contacts for re-activation'
        ]
      },
      
      'ContactGroup' => {
        description: 'Collections/segments of contacts for targeted marketing campaigns',
        purpose: 'Organize contacts into meaningful groups for segmented messaging',
        business_context: 'Groups allow targeted marketing - send different messages to different audiences based on interests, behavior, or demographics.',
        key_fields: {
          name: 'Group name/title',
          description: 'What this group represents',
          entity_id: 'Organization that owns this group',
          user_id: 'Creator of the group'
        },
        relationships: {
          belongs_to: ['Entity', 'User'],
          has_many: ['ContactGroupsContacts', 'Campaigns'],
          has_many_through: ['Contacts']
        },
        usage_examples: [
          'Newsletter subscribers',
          'Premium customers',
          'Trial users',
          'Geographic segments (US, Europe)',
          'Industry segments (healthcare, tech)',
          'Engagement segments (highly engaged, at-risk)'
        ],
        typical_queries: [
          'Largest contact groups',
          'Groups with highest engagement',
          'Recently created segments',
          'Group performance comparison'
        ]
      },
      
      'LandingPage' => {
        description: 'Standalone web pages designed for marketing campaigns and lead generation',
        purpose: 'Convert visitors into leads/customers through focused, single-purpose pages',
        business_context: 'Landing pages are crucial for marketing campaigns - they provide targeted experiences that drive specific actions.',
        key_fields: {
          title: 'Page title/name',
          slug: 'URL identifier (auto-generated)',
          description: 'Brief description of page purpose',
          html_content: 'Complete HTML content generated by AI',
          status: 'draft, published, or archived',
          entity_id: 'Organization that owns this page',
          user_id: 'Creator of the page',
          campaign_id: 'Associated campaign (optional)'
        },
        relationships: {
          belongs_to: ['Entity', 'User', 'Campaign (optional)'],
          has_many: ['LandingPageChatMessages', 'LandingPageVersions']
        },
        usage_examples: [
          'Lead generation forms for ebook downloads',
          'Product demo request pages',
          'Free trial signup pages',
          'Event registration pages',
          'Newsletter subscription pages',
          'Contact/sales inquiry forms'
        ],
        typical_queries: [
          'Best converting landing pages',
          'Recently created pages',
          'Pages needing content updates',
          'Campaign-specific landing pages'
        ]
      },
      
      'Entity' => {
        description: 'Organizations/businesses that use the marketing platform (multi-tenant)',
        purpose: 'Separate data and functionality for different organizations using the system',
        business_context: 'Entities provide data isolation - each business has their own campaigns, contacts, and landing pages.',
        key_fields: {
          name: 'Organization name',
          subdomain: 'URL subdomain for this organization',
          settings: 'Organization-specific configuration'
        },
        relationships: {
          has_many: ['Users', 'Campaigns', 'Contacts', 'ContactGroups', 'LandingPages', 'SocialMediaAccounts']
        },
        usage_examples: [
          'Marketing agencies managing multiple clients',
          'Separate business units',
          'Different brands under one company',
          'Franchise locations'
        ],
        typical_queries: [
          'Entity performance metrics',
          'Most active entities',
          'Entity growth trends'
        ]
      },
      
      'User' => {
        description: 'People who use the marketing platform (marketers, admins, etc.)',
        purpose: 'Authentication, authorization, and ownership tracking for platform activities',
        business_context: 'Users are the people operating the marketing campaigns and managing customer relationships.',
        key_fields: {
          email: 'Login email address',
          first_name: 'User first name',
          last_name: 'User last name',
          role: 'Permission level (admin, user, etc.)',
          entity_id: 'Organization this user belongs to'
        },
        relationships: {
          belongs_to: ['Entity'],
          has_many: ['Campaigns', 'Contacts', 'ContactGroups', 'LandingPages']
        },
        usage_examples: [
          'Marketing managers creating campaigns',
          'Sales people managing contacts',
          'Admins configuring settings',
          'Content creators building landing pages'
        ],
        typical_queries: [
          'Most active users',
          'User activity summaries',
          'Recent user actions'
        ]
      },
      
      'EmailDelivery' => {
        description: 'Individual email send records tracking delivery status for each contact',
        purpose: 'Track email delivery, opens, clicks, and bounces at the individual recipient level',
        business_context: 'Email deliveries provide detailed tracking - know exactly who received, opened, and clicked each email.',
        key_fields: {
          campaign_id: 'Which campaign this email belongs to',
          contact_id: 'Who received the email',
          email: 'Email address used',
          status: 'delivered, bounced, failed, etc.',
          delivered_at: 'When email was delivered',
          opened_at: 'When email was first opened',
          clicked_at: 'When first link was clicked',
          bounced_at: 'When email bounced (if applicable)',
          mailgun_id: 'External delivery service identifier'
        },
        relationships: {
          belongs_to: ['Campaign', 'Contact']
        },
        usage_examples: [
          'Track campaign delivery rates',
          'Identify engaged vs unengaged contacts',
          'Monitor email reputation and deliverability',
          'Calculate campaign ROI and effectiveness'
        ],
        typical_queries: [
          'Campaign delivery statistics',
          'Contact engagement history',
          'Bounce rate analysis',
          'Email performance trends'
        ]
      },
      
      'SocialMediaAccount' => {
        description: 'Connected social media accounts for cross-platform marketing',
        purpose: 'Extend marketing reach beyond email to social platforms',
        business_context: 'Social accounts enable omnichannel marketing - coordinate messaging across email and social media.',
        key_fields: {
          platform: 'facebook, instagram, twitter, etc.',
          account_name: 'Social media handle/username',
          access_token: 'API credentials for posting',
          connected: 'Whether account is currently connected',
          entity_id: 'Organization that owns this account'
        },
        relationships: {
          belongs_to: ['Entity'],
          has_many: ['SocialPosts']
        },
        usage_examples: [
          'Facebook business pages',
          'Instagram business accounts',
          'Twitter business profiles',
          'LinkedIn company pages'
        ],
        typical_queries: [
          'Connected social accounts',
          'Social media performance',
          'Cross-platform campaign reach'
        ]
      },
      
      'SocialPost' => {
        description: 'Social media posts created and scheduled through the platform',
        purpose: 'Manage social media content as part of integrated marketing campaigns',
        business_context: 'Social posts work alongside email campaigns to create cohesive marketing messages across channels.',
        key_fields: {
          content: 'Post text/content',
          scheduled_for: 'When to publish',
          status: 'draft, scheduled, published, failed',
          platform_post_id: 'ID from the social platform',
          social_media_account_id: 'Which account to post from',
          entity_id: 'Organization that owns this post'
        },
        relationships: {
          belongs_to: ['Entity', 'SocialMediaAccount'],
          has_many: ['SocialPostAnalytics']
        },
        usage_examples: [
          'Product launch announcements',
          'Blog post promotions',
          'Event marketing',
          'Customer testimonials',
          'Behind-the-scenes content'
        ],
        typical_queries: [
          'Top performing social posts',
          'Scheduled content calendar',
          'Social engagement rates',
          'Cross-platform content performance'
        ]
      }
    }
  end
end 