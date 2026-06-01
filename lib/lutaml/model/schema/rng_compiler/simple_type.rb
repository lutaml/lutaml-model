# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Restricted simple-type subclass.
        #
        # Output shape (rendered by the base via
        # Lutaml::Model::Schema::Templates::RESTRICTED_SIMPLE_TYPE):
        #
        #   class StIntegerRange < Lutaml::Model::Type::Integer
        #     def self.cast(value, options = {})
        #       return if value.nil?
        #       options[:min] = 1
        #       options[:max] = 255
        #       value = super(value, options)
        #       value
        #     end
        #     ...registration methods...
        #   end
        #   StIntegerRange.register_class_with_id
        class SimpleType < Lutaml::Model::Schema::RestrictedSimpleTypeRenderer
          attr_reader :class_name, :restriction
          attr_accessor :base_type, :fragment

          def initialize(class_name:, base_type:, restriction:)
            super()
            @class_name = class_name
            @base_type = base_type
            @restriction = restriction
            @fragment = true # SimpleTypes are always type-only, no XML element
          end

          # Type symbol used when an attribute references this generated type.
          def type_symbol
            Utils.snake_case(class_name).to_sym
          end

          # --- RestrictedSimpleTypeRenderer overrides ---

          def rendered_class_name
            class_name
          end

          # Looked up in the canonical Lutaml::Model::Type::TYPE_CODES map.
          def parent_class
            Lutaml::Model::Type::TYPE_CODES.fetch(
              @base_type, Lutaml::Model::Type::TYPE_CODES[:string]
            )
          end

          def restricted_simple_type_cast_body
            restriction.to_method_body(boilerplate_indent_str * 2)
          end

          # SimpleType registers under its type_symbol (e.g. :st_color)
          # rather than the default snake_cased class name.
          def registration_methods
            super(type_symbol)
          end
        end
      end
    end
  end
end
