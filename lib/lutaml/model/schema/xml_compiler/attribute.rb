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

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>attribute :<%= resolved_name %>, <%= type_reference %>
          TEMPLATE

          XML_MAPPING_TEMPLATE = ERB.new(<<~XML_MAPPING_TEMPLATE, trim_mode: "-")
            <%= indent %>map_attribute :<%= resolved_name(change_case: false) %>, to: :<%= resolved_name %><%= namespace_prefix_option %>
          XML_MAPPING_TEMPLATE

          def initialize(name: nil, ref: nil)
            @name = name
            @ref = ref
          end

          def to_attributes(indent)
            return if skippable?

            TEMPLATE.result(binding)
          end

          def to_xml_mapping(indent)
            return if skippable?

            XML_MAPPING_TEMPLATE.result(binding)
          end

          def required_files
            return if skippable?

            files = []

            raw_type = resolved_type(change_case: false)

            # Add W3C require for xml: attributes
            if w3c_type?(raw_type)
              files << "require \"lutaml/model/xml/w3c\""
            elsif raw_type == "decimal"
              files << "require \"bigdecimal\""
            elsif !SimpleType.skippable?(raw_type)
              files << "require_relative \"#{Utils.snake_case(raw_type)}\""
            end

            files.compact # Return all files as array
          end

          private

          def resolved_name(change_case: true)
            @current_name ||= name || referenced_instance&.name
            change_case ? Utils.snake_case(@current_name) : @current_name
          end

          def resolved_type(change_case: true)
            @current_type ||= type || referenced_instance&.type

            # For W3C types, return the full class name
            return @current_type if w3c_type?(@current_type)

            klass_name = last_of_split(@current_type)
            change_case ? Utils.snake_case(klass_name) : klass_name
          end

          def type_reference
            raw_type = resolved_type(change_case: false)

            # W3C types are full class names, use directly
            if w3c_type?(raw_type)
              "::#{raw_type}"
            else
              # Regular types are symbols
              ":#{resolved_type}"
            end
          end

          def w3c_type?(type_name)
            type_name&.to_s&.start_with?("Lutaml::Model::Xml::W3c::")
          end

          def referenced_instance
            @referenced_instance ||= XmlCompiler.attributes[last_of_split]
          end

          def last_of_split(field = ref)
            field&.split(":")&.last
          end

          def skippable?
            resolved_name == "schema_location"
          end

          def namespace_prefix_option
            return "" unless Utils.present?(ref)
            return "" unless ref.start_with?("xml:")

            # Use built-in W3C XmlNamespace for xml: prefixed attributes
            ", namespace: ::Lutaml::Model::Xml::W3c::XmlNamespace"
          end
        end
      end
    end
  end
end
