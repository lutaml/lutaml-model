# frozen_string_literal: true

module Lutaml
  module Lml
    # Single source of truth for entity types held on a Document. Each
    # entity model declares self.entity_type (the Document collection
    # name); consumers iterate this registry instead of hardcoding the
    # type list in four places.
    module EntityTypes
      ALL = [UmlClass, Enum, DataType, PrimitiveType].freeze

      def self.all
        ALL
      end

      def self.by_symbol
        @by_symbol ||= ALL.each_with_object({}) { |klass, index| index[klass.entity_type] = klass }
      end

      def self.symbols
        by_symbol.keys
      end

      # Entities that can own attributes/associations (excludes enums).
      def self.classifiable
        ALL.select(&:classifiable?)
      end
    end
  end
end
