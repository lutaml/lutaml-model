# frozen_string_literal: true

module Lutaml
  module Model
    # Decides how an attribute shapes incoming raw values: whether an
    # Array is split element-wise (collection semantics) or handed whole
    # to the declared type (value-owning semantics).
    #
    # A user-defined Type::Value subclass may legitimately wrap lists or
    # maps in a singular slot (#752); built-in scalar types keep the
    # "collection: true is missing" guidance error.
    class ValuePolicy
      def initialize(collection:, union:, reference:)
        @collection = collection
        @union = union
        @reference = reference
      end

      # @param type [Class, Symbol] the resolved (or unresolved) type
      # @return [Boolean] whether raw values must reach the type whole
      def whole_value?(type)
        !@collection && !@union && !@reference &&
          type.is_a?(Class) && type < Type::Value && !Type.builtin?(type)
      end
    end
  end
end
