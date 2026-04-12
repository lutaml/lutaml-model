# frozen_string_literal: true

require_relative "attribute_grouper"
require_relative "dispatcher"
require_relative "pattern_chunker"

module Lutaml
  module Model
    module Consolidation
      class Engine
        # @param collection [Collection] the collection instance
        # @param consolidation_map [ConsolidationMap] the format-level config
        # @param raw_data [Array] raw items (Pattern A) or mixed content tokens (Pattern B)
        def self.run(collection, consolidation_map, raw_data)
          strategy = strategy_for(consolidation_map)
          strategy.process(collection, consolidation_map, raw_data)
        end

        class << self
          private

          def strategy_for(consolidation_map)
            if consolidation_map.pattern?
              PatternChunker.new
            else
              AttributeGrouper.new
            end
          end
        end
      end
    end
  end
end
