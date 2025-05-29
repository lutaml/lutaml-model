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
            <%= indent %>attribute :<%= resolved_name %>, :<%= resolved_type %>
          TEMPLATE

          XML_MAPPING_TEMPLATE = ERB.new(<<~XML_MAPPING_TEMPLATE, trim_mode: "-")
            <%= indent %>map_element :<%= resolved_name %>, to: :<%= resolved_type %>
          XML_MAPPING_TEMPLATE

          def initialize(name: nil, ref: nil)
            raise "Element name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
          end

          def to_attributes(indent = INDENT)
            TEMPLATE.result(binding) if type
          end

          def to_xml_mapping(indent = INDENT)
            XML_MAPPING_TEMPLATE.result(binding) if type
          end

          private

          def resolved_instance
            @resolved_instance ||= XmlCompiler.instance_variable_get(:@elements)[ref]
          end

          def resolved_type
            @current_type ||= type || resolved_instance&.type
            Utils.snake_case(@current_type.split(":").last)
          end

          def resolved_name
            @current_name ||= name || resolved_instance&.name
          end
        end
      end
    end
  end
end
