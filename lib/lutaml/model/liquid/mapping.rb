require_relative "../mapping/mapping"

module Lutaml
  module Model
    module Liquid
      class Mapping < Mapping
        attr_reader :drop_mappings

        def initialize
          super
          @drop_mappings = {}
        end

        def map(key, to:)
          @drop_mappings[key.to_s] = to.to_sym
        end

        def deep_dup
          self.class.new.tap do |new_mapping|
            new_mapping.instance_variable_set(:@drop_mappings,
                                              @drop_mappings.dup)
          end
        end

        def mappings
          @drop_mappings
        end
      end
    end
  end
end
