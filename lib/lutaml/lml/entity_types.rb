# frozen_string_literal: true

module Lutaml
  module Lml
    # Single source of truth for entity types held on a Document. Each
    # entity model declares self.entity_type (the Document collection
    # name); consumers iterate this registry instead of hardcoding the
    # type list in four places.
    module EntityTypes
      # Registry built lazily (method, not load-time constant): the entity
      # model classes load later in the boot, and eager evaluation breaks
      # Opal's sequential require order.
      def self.all
        @all ||= [UmlClass, Enum, DataType, PrimitiveType].freeze
      end

      def self.by_symbol
        @by_symbol ||= all.to_h { |klass| [klass.entity_type, klass] }
      end

      def self.symbols
        by_symbol.keys
      end

      # Entities that can own attributes/associations (excludes enums).
      def self.classifiable
        all.select(&:classifiable?)
      end
    end
  end
end
