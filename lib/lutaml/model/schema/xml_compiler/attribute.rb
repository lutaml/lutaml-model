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


          DEFAULT_XML_NAMESPACES = %w[xml]
          INDENT = "  "

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>attribute :<%= resolved_name %>, :<%= resolved_type %>
          TEMPLATE

          XML_MAPPING_TEMPLATE = ERB.new(<<~XML_MAPPING_TEMPLATE, trim_mode: "-")
            <%= indent %>map_attribute :<%= resolved_name(change_case: false) %>, to: :<%= resolved_name %>
          XML_MAPPING_TEMPLATE

          def initialize(name: nil, ref: nil)
            raise "Attribute name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
          end

          def to_attributes(indent = INDENT)
            return if skippable?

            TEMPLATE.result(binding)
          end

          def to_xml_mapping(indent = INDENT)
            XML_MAPPING_TEMPLATE.result(binding)
          end

          def required_files
            raw_type = resolved_type(change_case: false)
            if raw_type == "decimal"
              "require \"bigdecimal\""
            elsif !SimpleType::SUPPORTED_DATA_TYPES.dig(raw_type.to_sym, :skippable)
              "require_relative \"#{Utils.snake_case(raw_type)}\""
            end
          end

          private

          def resolved_name(change_case: true)
            @current_name ||= name || referenced_instance&.name
            change_case ? Utils.snake_case(@current_name) : @current_name
          end

          def resolved_type(change_case: true)
            @current_type ||= type || referenced_instance&.type
            klass_name = @current_type&.split(":").last
            change_case ? Utils.snake_case(klass_name) : klass_name
          end

          def referenced_instance
            @referenced_instance ||= XmlCompiler.instance_variable_get(:"@attributes")[ref]
          end

          def skippable?
            DEFAULT_XML_NAMESPACES.include?(ref&.split(":")&.first)
          end
        end
      end
    end
  end
end
