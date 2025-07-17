# Scout AI Universal Tool System Design

## Overview
Create a generic, extensible AI tool system where Scout can autonomously access, analyze, and create ANY data object in the system through universal tools rather than object-specific tools.

## Revolutionary Approach: Universal Tools + Data Object Registry

### Current Problem (Specific Tools)
```ruby
# ❌ Not Scalable - Need new tools for each object type
'get_recent_campaigns' 
'get_landing_page_metrics'
'get_ad_performance'
'create_email_campaign'
'create_landing_page'
# ... endless specific tools
```

### New Solution (Universal Tools)
```ruby
# ✅ Infinitely Extensible - Works for ANY object
'get_data'      # Query any data object(s)
'analyze_data'  # Analyze any dataset with user context  
'create_object' # Create any creatable object
'update_object' # Modify any existing object
```

## Architecture

### 1. Data Object Registry
```ruby
class ScoutDataRegistry
  AVAILABLE_OBJECTS = {
    'campaigns' => {
      model: 'Campaign',
      queryable_fields: ['name', 'status', 'created_at', 'sent_at', 'subject'],
      metrics: ['open_rate', 'click_rate', 'conversion_rate', 'unsubscribe_rate'],
      relationships: ['email_deliveries', 'contact_groups', 'email_template'],
      creatable: true,
      creation_schema: {
        required: ['name', 'email_template_id', 'contact_group_ids'],
        optional: ['subject', 'scheduled_at', 'description']
      }
    },
    'landing_pages' => {
      model: 'LandingPage',
      queryable_fields: ['title', 'slug', 'status', 'created_at'],
      metrics: ['view_count', 'conversion_rate', 'bounce_rate', 'avg_time_on_page'],
      relationships: ['landing_page_versions', 'campaigns'],
      creatable: true,
      creation_schema: {
        required: ['title', 'description'],
        optional: ['slug', 'campaign_id', 'template_type']
      }
    },
    'contacts' => {
      model: 'Contact',
      queryable_fields: ['email', 'first_name', 'last_name', 'created_at', 'last_engagement'],
      metrics: ['engagement_score', 'lifetime_opens', 'lifetime_clicks'],
      relationships: ['contact_groups', 'email_deliveries'],
      creatable: true,
      creation_schema: {
        required: ['email'],
        optional: ['first_name', 'last_name', 'contact_group_ids']
      }
    },
    'contact_groups' => {
      model: 'ContactGroup',
      queryable_fields: ['name', 'description', 'created_at'],
      metrics: ['contact_count', 'avg_engagement_rate'],
      relationships: ['contacts', 'campaigns'],
      creatable: true
    },
    'ad_campaigns' => {  # Future: When ads are added
      model: 'AdCampaign',
      queryable_fields: ['name', 'platform', 'status', 'budget'],
      metrics: ['impressions', 'clicks', 'ctr', 'cpc', 'conversions'],
      creatable: true
    }
  }
end
```

### 2. Universal Tool System
```ruby
class UniversalScoutTools
  TOOLS = {
    'get_data' => {
      description: 'Retrieve and query any data objects in the system',
      parameters: {
        objects: { 
          type: 'array', 
          description: 'Object types to query (campaigns, landing_pages, contacts, etc.)' 
        },
        filters: { 
          type: 'object', 
          optional: true,
          description: 'Filtering criteria like date_range, status, etc.' 
        },
        include_metrics: { 
          type: 'boolean', 
          default: true,
          description: 'Whether to include performance metrics' 
        },
        include_relationships: { 
          type: 'array', 
          optional: true,
          description: 'Related objects to include' 
        },
        limit: { 
          type: 'integer', 
          default: 10,
          description: 'Maximum number of records to return' 
        }
      }
    },
    
    'analyze_data' => {
      description: 'Perform analysis on any dataset with user context and questions',
      parameters: {
        data_context: { 
          type: 'string', 
          description: 'What data to analyze (from previous get_data calls or user description)' 
        },
        analysis_type: { 
          type: 'string',
          description: 'Type of analysis: trends, comparison, performance, forecasting, correlation' 
        },
        user_question: { 
          type: 'string', 
          description: 'The specific question or goal for the analysis' 
        },
        benchmark_against: { 
          type: 'string', 
          optional: true,
          description: 'What to compare against: previous_period, industry_standards, goals' 
        }
      }
    },
    
    'create_object' => {
      description: 'Create new objects like campaigns, landing pages, contacts, etc.',
      parameters: {
        object_type: { 
          type: 'string', 
          description: 'Type of object to create (campaigns, landing_pages, contacts, etc.)' 
        },
        object_data: { 
          type: 'object', 
          description: 'Data for the new object based on the creation schema' 
        },
        auto_populate: { 
          type: 'boolean', 
          default: true,
          description: 'Whether to intelligently populate optional fields based on context' 
        }
      }
    },
    
    'update_object' => {
      description: 'Update existing objects with new data',
      parameters: {
        object_type: { type: 'string', description: 'Type of object to update' },
        object_id: { type: 'integer', description: 'ID of object to update' },
        updates: { type: 'object', description: 'Fields to update' }
      }
    }
  }
end
```

### 3. Universal Query Engine
```ruby
class UniversalQueryEngine
  def execute_get_data(params)
    results = {}
    
    params[:objects].each do |object_type|
      object_config = ScoutDataRegistry::AVAILABLE_OBJECTS[object_type]
      model_class = object_config[:model].constantize
      
      # Build base query with entity scoping
      query = model_class.where(entity: @entity)
      
      # Apply filters
      query = apply_filters(query, params[:filters], object_config)
      
      # Include metrics if requested
      if params[:include_metrics]
        query = query.includes(metric_associations(object_config))
      end
      
      # Include relationships if requested
      if params[:include_relationships]
        query = query.includes(params[:include_relationships])
      end
      
      # Execute query
      records = query.limit(params[:limit] || 10)
      
      # Format results
      results[object_type] = format_records_with_metrics(records, object_config)
    end
    
    results
  end
end
```

## Powerful New Capabilities

### Cross-Object Analysis
```
User: "Compare my email campaign performance vs my landing page conversion rates"

Scout calls:
1. get_data(objects: ['campaigns', 'landing_pages'], include_metrics: true)
2. analyze_data(analysis_type: 'correlation', user_question: 'email vs landing page performance')

Result: "Your landing pages convert 23% better when linked from email campaigns vs direct traffic..."
```

### Intelligent Object Creation
```
User: "Create a campaign for my top performing contact segment"

Scout calls:
1. get_data(objects: ['contact_groups'], include_metrics: true) 
2. analyze_data(analysis_type: 'performance', user_question: 'best performing segments')
3. create_object(object_type: 'campaigns', object_data: {contact_group_ids: [top_segment_id]}, auto_populate: true)

Result: Creates campaign with optimized settings based on segment data
```

### Multi-Object Insights  
```
User: "What's my overall marketing ROI?"

Scout calls:
1. get_data(objects: ['campaigns', 'landing_pages', 'contacts'], filters: {date_range: 'last_quarter'})
2. analyze_data(analysis_type: 'performance', user_question: 'overall marketing ROI calculation')

Result: "Your Q3 marketing ROI is 340%. Email campaigns drive 67% of conversions..."
```

## Implementation Benefits

### 🚀 **Infinite Extensibility**
- Add new data objects by just updating the registry
- No new tools needed for new object types
- Works with any future data model

### 🧠 **AI Intelligence**  
- LLM decides what data to query based on user questions
- Can combine data from multiple sources
- Performs complex analysis across object types

### ⚡ **Powerful Queries**
```ruby
# LLM can make complex requests like:
get_data(
  objects: ['campaigns', 'landing_pages'], 
  filters: { 
    date_range: 'last_30_days',
    status: 'completed',
    performance_threshold: 'above_average'
  },
  include_relationships: ['contact_groups', 'email_deliveries']
)
```

### 🎯 **Smart Creation**
```ruby
# LLM can create objects with intelligent defaults:
create_object(
  object_type: 'campaigns',
  object_data: {
    name: 'Holiday Promotion',
    contact_group_ids: [5, 8], # Top performing segments
    # AI populates optimal send times, subject patterns, etc.
  },
  auto_populate: true
)
```

## Technical Implementation

### Phase 1: Universal Infrastructure
1. Build Data Object Registry
2. Create Universal Query Engine  
3. Implement get_data tool

### Phase 2: Analysis Engine
1. Build analyze_data tool
2. Cross-object analysis capabilities
3. Performance benchmarking

### Phase 3: Creation Engine  
1. Implement create_object tool
2. Intelligent auto-population
3. Validation and error handling

### Phase 4: Advanced Features
1. Update/delete capabilities
2. Bulk operations
3. Advanced analytics

## Example Conversations

### Marketing Analysis
```
User: "How are all my marketing channels performing?"
Scout: [get_data: campaigns, landing_pages, contacts with metrics]
       [analyze_data: cross-channel performance analysis]
Scout: "Here's your complete marketing overview:
       📧 Email: 24% open rate, $3.20 ROI per email
       🎯 Landing Pages: 12% conversion rate, 2.3min avg time
       👥 Audience Growth: +15% this month
       
       Your email → landing page flow is your top performer!"
```

### Campaign Creation
```
User: "Create a campaign for my most engaged contacts about our new feature"
Scout: [get_data: contact_groups with engagement metrics]
       [analyze_data: identify top performers]
       [create_object: campaign with optimal settings]
Scout: "I've created 'New Feature Announcement' campaign targeting your 'High Engagement' segment (2,847 contacts with 45% avg open rate). 
       
       Optimized for Tuesday 2pm send based on this segment's behavior.
       Want me to help craft the email content too?"
```

This universal approach transforms Scout from a "database query assistant" into a true "marketing intelligence partner" that can work with any data and create anything in your system! 