# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Generates a Lutaml::Model::Type::Value subclass for an RNG union
        # (RELAX NG `<choice>` over multiple `<data>` types). Mirrors
        # XmlCompiler::SimpleType::UNION_MODEL_TEMPLATE.
        class UnionType
          include ClassBoilerplate

          TEMPLATE = ERB.new(<<~TMPL, trim_mode: "-")
            # frozen_string_literal: true
            require "lutaml/model"

            <%= module_opening -%>
            class <%= class_name %> < Lutaml::Model::Type::Value
            <%= sp %>def self.cast(value, options = {})
            <%= sp2 %>return if value.nil?

            <%= sp2 %>[<%= type_list %>].each do |t|
            <%= sp2 %>  begin
            <%= sp2 %>    casted = t.cast(value, options)
            <%= sp2 %>    return casted unless casted.nil?
            <%= sp2 %>  rescue StandardError
            <%= sp2 %>    next
            <%= sp2 %>  end
            <%= sp2 %>end
            <%= sp2 %>value
            <%= sp %>end
            <%= registration_methods -%>
            end
            <%= module_closing -%>
            <%= registration_execution -%>
          TMPL

          # SimpleType-shaped interface for the visitor and registry.
          attr_reader :class_name, :member_types
          attr_accessor :fragment

          def initialize(class_name:, member_types:)
            @class_name = class_name
            @member_types = member_types
            @fragment = true
          end

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

          private

          def sp
            " " * @indent
          end

          def sp2
            sp * 2
          end

          def type_list
            @member_types.map do |t|
              SimpleType::BASE_TYPE_MAP.fetch(t, "Lutaml::Model::Type::String")
            end.join(", ")
          end

          # UnionType registers under its type_symbol like SimpleType.
          def registration_methods
            super(type_symbol)
          end
        end
      end
    end
  end
end
