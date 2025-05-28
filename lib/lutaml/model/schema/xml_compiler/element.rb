# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Element
          attr_accessor :id,
                        :ref,
                        :name,
                        :type,
                        :fixed,
                        :default,
                        :max_occurs,
                        :min_occurs,
                        :simple_type,
                        :complex_type

          INDENT = "  "

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>attribute :<%= name %>, :<%= attribute_type %>
          TEMPLATE

          def initialize(name: nil, ref: nil)
            raise "Element name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
          end

          def to_class(indent = INDENT)
            TEMPLATE.result(binding) if type
          end

          def attribute_type
            Utils.snake_case(type.split(":").last) if type
          end
        end
      end
    end
  end
end
