# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # XSD-only string transform (e.g. uppercase / lowercase) applied
        # during cast. RNG leaves this nil.
        class TransformFacet
          attr_accessor :kind

          def initialize(kind:)
            @kind = kind
          end
        end
      end
    end
  end
end
