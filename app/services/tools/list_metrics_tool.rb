module Tools
  class ListMetricsTool < BaseTool
    def self.read_only?
      true
    end
    
    def self.metadata
      {
        name: 'list_metrics',
        description: 'Discover available analytics metrics, datasets, and dimensions',
        category: 'analytics',
        input_schema: {
          type: 'object',
          properties: {
            category: {
              type: 'string',
              description: 'Filter by category (optional)'
            },
            search: {
              type: 'string',
              description: 'Search metrics by name or description'
            }
          }
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      category = get_arg(args, :category)
      search = get_arg(args, :search)
      
      begin
        # Get catalog from Analytics::CatalogService
        catalog = Analytics::CatalogService.get_catalog(entity: @entity)
        
        # Filter if requested
        metrics = catalog[:metrics]
        
        if category
          metrics = metrics.select { |m| m[:category] == category }
        end
        
        if search
          search_term = search.downcase
          metrics = metrics.select do |m|
            m[:name].downcase.include?(search_term) ||
            m[:description]&.downcase&.include?(search_term)
          end
        end
        
        success_response(
          metrics: metrics,
          datasets: catalog[:datasets],
          dimensions: catalog[:dimensions],
          total_metrics: metrics.count,
          total_datasets: catalog[:datasets].count,
          message: "Found #{metrics.count} metrics across #{catalog[:datasets].count} datasets"
        )
      rescue => e
        Rails.logger.error "List metrics failed: #{e.message}"
        error_response("Failed to list metrics: #{e.message}")
      end
    end
  end
end

