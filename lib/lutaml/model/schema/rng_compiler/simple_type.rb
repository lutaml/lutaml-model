# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Generates a type-subclass for a restricted simple type, mirroring
        # XmlCompiler::SimpleType::INSTANCE_MODEL_TEMPLATE.
        #
        # Output shape:
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
        class SimpleType
          include ClassBoilerplate

          TEMPLATE = ERB.new(<<~TMPL, trim_mode: "-")
            # frozen_string_literal: true
            require "lutaml/model"

            <%= module_opening -%>
            class <%= class_name %> < <%= parent_class %>
            <%= sp %>def self.cast(value, options = {})
            <%= sp2 %>return if value.nil?

            <%= restriction.to_method_body(sp2) -%>
            <%= sp2 %>value = super(value, options)
            <%= sp2 %>value
            <%= sp %>end
            <%= registration_methods -%>
            end
            <%= module_closing -%>
            <%= registration_execution -%>
          TMPL

          BASE_TYPE_MAP = {
            string:    "Lutaml::Model::Type::String",
            integer:   "Lutaml::Model::Type::Integer",
            boolean:   "Lutaml::Model::Type::Boolean",
            float:     "Lutaml::Model::Type::Float",
            decimal:   "Lutaml::Model::Type::Decimal",
            date:      "Lutaml::Model::Type::Date",
            date_time: "Lutaml::Model::Type::DateTime",
            time:      "Lutaml::Model::Type::Time",
          }.freeze

          attr_reader :class_name, :restriction
          attr_accessor :base_type, :fragment

          def initialize(class_name:, base_type:, restriction:)
            @class_name = class_name
            @base_type = base_type
            @restriction = restriction
            @fragment = true # SimpleTypes are always type-only, no XML element
          end

          # Type symbol used when an attribute references this generated type.
          def type_symbol
            Utils.snake_case(class_name).to_sym
          end

          def render(indent: 2, module_namespace: nil, register_id: :default)
            @indent = indent
            @module_namespace = module_namespace
            @register_id = register_id
            @modules = Array(module_namespace&.split("::"))
            TEMPLATE.result(binding)
          end

          # The base class used to extend, e.g. "Lutaml::Model::Type::Integer".
          def parent_class
            BASE_TYPE_MAP.fetch(@base_type, BASE_TYPE_MAP[:string])
          end

          private

          def sp
            " " * @indent
          end

          def sp2
            sp * 2
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
