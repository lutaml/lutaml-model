# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # XSD-only: a complex type with simple content (a typed text
        # body plus optional decorating attributes). The renderer emits
        # `attribute :content, :<base_type>` and any additional
        # attributes after the regular members. RNG leaves this nil.
        class SimpleContent
          attr_accessor :base_class, :additional_attributes

          def initialize(base_class:, additional_attributes: [])
            @base_class = base_class
            @additional_attributes = additional_attributes
          end
        end
      end
    end
  end
end
