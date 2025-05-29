# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Attribute
          attr_accessor :id,
                        :ref,
                        :name,
                        :type,
                        :default

          INDENT = "  "

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>attribute :<%= resolved_name %>, :<%= resolved_type %>
          TEMPLATE

          XML_MAPPING_TEMPLATE = ERB.new(<<~XML_MAPPING_TEMPLATE, trim_mode: "-")
            <%= indent %>map_attribute :<%= resolved_name %>, to: :<%= resolved_type %>
          XML_MAPPING_TEMPLATE

          def initialize(name: nil, ref: nil)
            raise "Attribute name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
          end

          def to_attributes(indent = INDENT)
            TEMPLATE.result(binding)
          end

          def to_xml_mapping(indent = INDENT)
            XML_MAPPING_TEMPLATE.result(binding)
          end

          private

          def resolved_name
            return @name if @name

            referenced_instance&.name
          end

          def resolved_type
            current_type = type || referenced_instance&.type
            Utils.snake_case(current_type.split(":").last)
          end

          def referenced_instance
            @referenced_instance ||= XmlCompiler.instance_variable_get(:"@attributes")[ref]
          end
        end
      end
    end
  end
end
