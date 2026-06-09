# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # XSD-only value transform applied during cast. The expression
        # is raw Ruby emitted as `value = <expression>` before super.
        # E.g. "value.gsub(/[\\r\\n\\t]/, ' ')" or "value.upcase". RNG
        # leaves this nil.
        class TransformFacet
          attr_accessor :expression

          def initialize(expression:)
            @expression = expression
          end
        end
      end
    end
  end
end
