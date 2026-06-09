# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # A `choice do ... end` block. Alternatives may be Attribute,
        # Sequence, or nested Choice specs.
        class Choice
          attr_accessor :alternatives, :header

          def initialize(alternatives:, header:)
            @alternatives = alternatives
            @header = header
          end
        end
      end
    end
  end
end
