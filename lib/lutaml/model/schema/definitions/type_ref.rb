# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # Reference to a Ruby type used in a generated attribute.
        # kind ∈ {:symbol, :class_ref, :w3c}.
        class TypeRef
          attr_accessor :kind, :value

          def initialize(kind:, value:)
            @kind = kind
            @value = value
          end
        end
      end
    end
  end
end
