# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # A `sequence do ... end` group. Transparent in attribute
        # declarations; wraps with `sequence do` only in xml mappings.
        class Sequence
          attr_accessor :members

          def initialize(members:)
            @members = members
          end
        end
      end
    end
  end
end
