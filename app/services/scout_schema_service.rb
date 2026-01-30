class ScoutSchemaService
  def self.get_model_schema(model_name)
    model_class = model_name_to_class(model_name)
    return nil unless model_class

    {
      model_name: model_name,
      table_name: model_class.table_name,
      fields: get_model_fields(model_class),
      required_fields: get_required_fields(model_class),
      relationships: get_model_relationships(model_class),
      example_data: get_example_data(model_class),
      creation_notes: get_creation_notes(model_name)
    }
  end

  def self.get_all_available_models
    available_models = %w[
      campaign
      contact
      contact_group
      landing_page
      email_template
      business_profile
      opportunity
      activity
    ]

    available_models.map do |model_name|
      {
        model_name: model_name,
        description: get_model_description(model_name),
        can_create: can_create_model?(model_name),
        can_query: can_query_model?(model_name)
      }
    end
  end

  def self.get_query_options
    {
      filters: {
        date_fields: [ "created_at", "updated_at", "sent_at", "scheduled_at" ],
        date_ranges: [ "today", "yesterday", "last_7_days", "last_30_days", "this_month", "last_month" ],
        status_values: [ "draft", "scheduled", "sent", "active", "inactive" ],
        boolean_fields: [ "opted_out", "active" ]
      },
      options: {
        limit: "number (max 100, default 20)",
        order_by: "field_name asc|desc",
        include_metrics: "boolean (default true)",
        include_relationships: "array of relationship names"
      }
    }
  end

  private

  def self.model_name_to_class(model_name)
    case model_name.to_s.downcase
    when "campaign"
      Campaign
    when "contact"
      Contact
    when "contact_group"
      ContactGroup
    when "landing_page"
      LandingPage
    when "email_template"
      EmailTemplate
    when "business_profile"
      BusinessProfile
    when "opportunity", "opportunities"
      Opportunity
    when "activity", "activities"
      Activity
    else
      nil
    end
  end

  def self.get_model_fields(model_class)
    fields = {}

    model_class.columns.each do |column|
      next if [ "id", "created_at", "updated_at" ].include?(column.name)

      fields[column.name] = {
        type: column.type.to_s,
        nullable: column.null,
        default: column.default,
        limit: column.limit
      }
    end

    fields
  end

  def self.get_required_fields(model_class)
    required = []

    # Get validation requirements
    model_class.validators.each do |validator|
      if validator.is_a?(ActiveModel::Validations::PresenceValidator)
        required.concat(validator.attributes.map(&:to_s))
      end
    end

    # Add database-level requirements
    model_class.columns.each do |column|
      if !column.null && ![ "id", "created_at", "updated_at" ].include?(column.name)
        required << column.name unless required.include?(column.name)
      end
    end

    required.uniq
  end

  def self.get_model_relationships(model_class)
    relationships = {}

    model_class.reflect_on_all_associations.each do |association|
      relationships[association.name.to_s] = {
        type: association.macro.to_s,
        class_name: association.class_name,
        foreign_key: association.foreign_key
      }
    end

    relationships
  end

  def self.get_example_data(model_class)
    case model_class.name
    when "Campaign"
      {
        name: "Newsletter Campaign",
        subject: "Check out our latest updates!",
        status: "draft"
      }
    when "Contact"
      {
        email: "john@example.com",
        first_name: "John",
        last_name: "Doe",
        metadata: {
          address: "123 Main St, City, State 12345",
          company: "Acme Corp",
          phone: "555-1234",
          title: "Manager"
        }
      }
    when "ContactGroup"
      {
        name: "Newsletter Subscribers",
        description: "Users who signed up for our newsletter"
      }
    when "LandingPage"
      {
        title: "Welcome to Our Product",
        description: "Learn more about what we offer"
      }
    when "EmailTemplate"
      {
        name: "Welcome Email",
        subject: "Welcome to our platform!",
        body: "Thank you for joining us..."
      }
    when "BusinessProfile"
      {
        industry: "Technology",
        company_size: "1-10 employees",
        target_audience: "Small businesses"
      }
    else
      {}
    end
  end

  def self.get_creation_notes(model_name)
    case model_name.to_s.downcase
    when "campaign"
      "Campaigns will be automatically scoped to the current entity. Status defaults to 'draft'."
    when 'contact'
      "Contacts will be automatically scoped to the current entity. Email must be unique within the entity.\n\nIMPORTANT - Metadata Field:\nContact has a 'metadata' JSONB field for flexible data storage. Use it for:\n- address: Full address string\n- company: Company/organization name  \n- phone: Phone number\n- title: Job title\n- notes: Additional notes\n- Any custom fields\n\nExample:\n{\n  first_name: 'John',\n  last_name: 'Doe',\n  email: 'john@example.com',\n  metadata: {\n    address: '123 Main St, City, State 12345',\n    company: 'Acme Corp',\n    phone: '555-1234',\n    title: 'CEO'\n  }\n}"
    when 'contact_group'
      "Contact groups will be automatically scoped to the current entity."
    when "landing_page"
      "Landing pages will be automatically scoped to the current entity."
    when "email_template"
      "Email templates will be automatically scoped to the current entity."
    when "business_profile"
      "Business profiles are tied to the user account."
    else
      "Object will be automatically scoped appropriately."
    end
  end

  def self.get_model_description(model_name)
    case model_name.to_s.downcase
    when "campaign"
      "Email marketing campaigns with metrics like open rates, click rates, etc."
    when "contact"
      "Individual contacts/subscribers with engagement tracking"
    when "contact_group"
      "Groups or segments of contacts for targeted campaigns"
    when "landing_page"
      "Marketing landing pages with conversion tracking"
    when "email_template"
      "Reusable email templates for campaigns"
    when "business_profile"
      "Business information and settings"
    else
      "Available data model"
    end
  end

  def self.can_create_model?(model_name)
    # Most models can be created
    ![ "business_profile" ].include?(model_name.to_s.downcase)
  end

  def self.can_query_model?(model_name)
    # All models can be queried
    true
  end
end
