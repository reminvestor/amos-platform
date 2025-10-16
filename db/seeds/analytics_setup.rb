# Analytics Add-On Sample Data
# Run with: rails runner db/seeds/analytics_setup.rb

puts "🔧 Setting up Analytics Add-On..."

# 1. Create sample data contracts
puts "Creating data contracts..."

DataContract.find_or_create_by!(name: 'campaigns', version: '1.0.0') do |contract|
  contract.entity_type = 'Campaign'
  contract.schema_definition = {
    entity_id: 'integer',
    campaign_id: 'integer',
    name: 'string',
    status: 'enum(draft,scheduled,sent,completed)',
    sent_at: 'date',
    channel: 'string',
    emails_sent: 'integer',
    opens: 'integer',
    clicks: 'integer',
    conversions: 'integer'
  }
  contract.privacy_rules = {
    pii_fields: [],
    tokenization: 'none'
  }
  contract.freshness_slo = '<= 5m'
  contract.is_active = true
end

DataContract.find_or_create_by!(name: 'contacts', version: '1.0.0') do |contract|
  contract.entity_type = 'Contact'
  contract.schema_definition = {
    entity_id: 'integer',
    contact_id: 'integer',
    email: 'string',
    created_at: 'date',
    last_activity_at: 'date',
    status: 'enum(active,inactive,unsubscribed)',
    source: 'string',
    tags: 'array'
  }
  contract.privacy_rules = {
    pii_fields: ['email'],
    tokenization: 'deterministic'
  }
  contract.freshness_slo = '<= 5m'
  contract.is_active = true
end

puts "✅ Created #{DataContract.count} data contracts"

# 2. Create sample metric definitions
puts "Creating metric definitions..."

MetricDefinition.find_or_create_by!(name: 'campaign_performance', version: '1.0.0') do |metric|
  metric.description = 'Campaign email performance metrics'
  metric.expression = 'COUNT(DISTINCT campaign_id)'
  metric.source = 'campaigns'
  metric.time_column = 'sent_at'
  metric.grain_default = 'week'
  metric.dimensions = ['channel', 'status']
  metric.filters_default = { status: ['sent', 'completed'] }
  metric.quality_rules = ['emails_sent >= 0', 'opens <= emails_sent']
  metric.owner = 'marketing@company.com'
  metric.category = 'marketing'
  metric.is_active = true
end

MetricDefinition.find_or_create_by!(name: 'email_engagement', version: '1.0.0') do |metric|
  metric.description = 'Email open and click rates'
  metric.expression = 'AVG(CAST(opens AS FLOAT) / NULLIF(emails_sent, 0) * 100)'
  metric.source = 'campaigns'
  metric.time_column = 'sent_at'
  metric.grain_default = 'week'
  metric.dimensions = ['channel']
  metric.filters_default = { status: ['sent', 'completed'] }
  metric.quality_rules = []
  metric.owner = 'marketing@company.com'
  metric.category = 'engagement'
  metric.is_active = true
end

MetricDefinition.find_or_create_by!(name: 'contact_growth', version: '1.0.0') do |metric|
  metric.description = 'New contacts acquired over time'
  metric.expression = 'COUNT(DISTINCT contact_id)'
  metric.source = 'contacts'
  metric.time_column = 'created_at'
  metric.grain_default = 'week'
  metric.dimensions = ['source', 'status']
  metric.filters_default = {}
  metric.quality_rules = []
  metric.owner = 'growth@company.com'
  metric.category = 'growth'
  metric.is_active = true
end

puts "✅ Created #{MetricDefinition.count} metric definitions"

# 3. Create internal analytics connection for each entity
puts "Creating analytics connections..."

Entity.find_each do |entity|
  AnalyticsConnection.find_or_create_by!(entity: entity, connection_type: :internal) do |conn|
    conn.name = "Internal Database"
    conn.status = :connected
    conn.credentials = {}
    conn.config = {
      description: "AMOS internal database for campaign and contact analytics"
    }
    conn.metadata = {
      created_by: 'analytics_setup',
      auto_created: true
    }
  end
  
  # Create tenant quota
  TenantQuota.find_or_create_by!(entity: entity) do |quota|
    quota.row_budget = 1_000_000
    quota.window_days_cap = 400
    quota.qps_limit = 10
    quota.metadata = {
      tier: 'standard',
      created_by: 'analytics_setup'
    }
  end
end

puts "✅ Created analytics connections and quotas for #{Entity.count} entities"

puts "🎉 Analytics Add-On setup complete!"
puts ""
puts "Available metrics:"
MetricDefinition.active.each do |metric|
  puts "  - #{metric.name} (#{metric.category}): #{metric.description}"
end
puts ""
puts "Test with: query_metric(metric: 'campaign_performance', start_date: '2025-01-01', end_date: '2025-10-15')"

