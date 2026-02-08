# frozen_string_literal: true

module V3
  module Recipes
    # Registry - Finds the right recipe for a given goal
    #
    # Recipes are registered in priority order. The first recipe whose
    # matches? method returns true for the goal is used.
    #
    # This is the "fast path" in the IntentEngine. If a recipe matches,
    # no LLM decomposition is needed -- the recipe executes directly in Ruby.
    #
    class Registry
      class << self
        # Find a recipe that matches the given goal
        # @param goal [String] The goal description
        # @param spec [Hash] The spec data
        # @return [Class<V3::Recipes::Base>, nil] The matching recipe class, or nil
        def find(goal, spec = {})
          normalized_goal = goal.to_s.downcase.strip

          sorted_recipes.find { |recipe_class| recipe_class.matches?(normalized_goal, spec) }
        end

        # All registered recipe classes, sorted by priority (highest first)
        def sorted_recipes
          @sorted_recipes ||= recipe_classes.sort_by { |r| -r.priority }
        end

        # Reset the cache (useful after adding new recipes at runtime)
        def reset!
          @sorted_recipes = nil
          @recipe_classes = nil
        end

        # Register a recipe class
        def register(recipe_class)
          recipe_classes << recipe_class unless recipe_classes.include?(recipe_class)
          @sorted_recipes = nil # Invalidate sort cache
        end

        # List all registered recipes (for debugging/admin)
        def all
          sorted_recipes
        end

        # Get stats about recipe coverage
        def stats
          {
            total_recipes: recipe_classes.size,
            recipes: sorted_recipes.map { |r| { name: r.recipe_name, priority: r.priority } }
          }
        end

        private

        def recipe_classes
          @recipe_classes ||= discover_recipes
        end

        # Auto-discover all recipe classes in the recipes directory
        def discover_recipes
          recipes = []

          # Load all recipe files
          recipe_dir = File.join(__dir__)
          Dir.glob(File.join(recipe_dir, "*_recipe.rb")).each do |file|
            require file
          end

          # Find all subclasses of Base
          ObjectSpace.each_object(Class).select { |klass|
            klass < V3::Recipes::Base && klass != V3::Recipes::Base
          }.each do |klass|
            recipes << klass
          end

          recipes
        rescue => e
          Rails.logger.error "[V3::Recipes::Registry] Discovery failed: #{e.message}"
          []
        end
      end
    end
  end
end
