module Analytics
  class CatalogService
    def self.get_catalog(entity:)
      new(entity: entity).get_catalog
    end
    
    def initialize(entity:)
      @entity = entity
    end
    
    def get_catalog
      {
        datasets: list_datasets,
        metrics: list_metrics,
        dimensions: list_dimensions
      }
    end
    
    private
    
    def list_datasets
      DataContract.active.map do |contract|
        {
          name: contract.name,
          entity: contract.entity_type,
          version: contract.version,
          owner: contract.metadata&.dig('owner') || 'system',
          freshness_slo: contract.freshness_slo,
          pii: contract.has_pii?,
          schema: contract.schema_definition
        }
      end
    end
    
    def list_metrics
      MetricDefinition.active.map do |metric|
        {
          name: metric.name,
          version: metric.version,
          description: metric.description,
          owner: metric.owner,
          category: metric.category,
          grain: metric.default_grain,
          dimensions: metric.available_dimensions,
          filters: metric.default_filters
        }
      end
    end
    
    def list_dimensions
      # Get unique dimensions across all metrics
      all_dimensions = MetricDefinition.active.flat_map(&:available_dimensions).uniq
      
      all_dimensions.map do |dim|
        {
          name: dim,
          pii: check_if_pii(dim)
        }
      end
    end
    
    def check_if_pii(dimension_name)
      # Check if dimension is marked as PII in any contract
      DataContract.active.any? do |contract|
        contract.pii_fields.include?(dimension_name)
      end
    end
  end
end

