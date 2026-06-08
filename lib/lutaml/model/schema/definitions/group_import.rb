# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # An inline `<xs:group ref="..."/>` reference appearing as a
        # member inside a Choice / Sequence / Model. Renders as
        # `import_model_attributes :name` in the attribute-decl block
        # and `import_model_mappings :name` in the xml-mapping block.
        # name is the snake_case symbol form (without leading colon).
        class GroupImport
          attr_accessor :name

          def initialize(name:)
            @name = name
          end
        end
      end
    end
  end
end
