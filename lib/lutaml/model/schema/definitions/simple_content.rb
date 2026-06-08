# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # XSD-only: a complex type with simple content (attributes plus
        # a text body of a built-in type). RNG leaves this nil.
        class SimpleContent
          attr_accessor :base_class, :required_files

          def initialize(base_class:, required_files: [])
            @base_class = base_class
            @required_files = required_files
          end
        end
      end
    end
  end
end
