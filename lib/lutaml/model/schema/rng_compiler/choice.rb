# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # A choice group of alternatives. Renders as a `choice do ... end`
        # block in the generated class. Each alternative is an Attribute or a
        # nested Sequence/Choice. The xml-mapping side emits one entry per
        # leaf attribute (Sequences wrap in `sequence do ... end`).
        class Choice
          attr_reader :alternatives

          def initialize
            @alternatives = []
          end

          def add_alternative(spec)
            @alternatives << spec
          end

          def header
            "choice"
          end
        end
      end
    end
  end
end
