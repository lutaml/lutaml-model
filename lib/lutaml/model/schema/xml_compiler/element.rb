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
                        :min_occurs

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>attribute :<%= resolved_name %>, :<%= resolved_type %><%= attribute_options %>
          TEMPLATE

          XML_MAPPING_TEMPLATE = ERB.new(<<~XML_MAPPING_TEMPLATE, trim_mode: "-")
            <%= indent %>map_element :<%= resolved_name(change_case: false) %>, to: :<%= resolved_name %>
          XML_MAPPING_TEMPLATE

          def initialize(name: nil, ref: nil)
            raise "Element name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
          end

          def to_attributes(indent)
            return if skippable?

            TEMPLATE.result(binding) if resolved_type
          end

          def to_xml_mapping(indent)
            return if skippable?

            XML_MAPPING_TEMPLATE.result(binding) if resolved_type
          end

          def required_files
            return if skippable?

            if resolved_type(change_case: false) == "decimal"
              "require \"bigdecimal\""
            elsif !SimpleType::SUPPORTED_DATA_TYPES.dig(resolved_type(change_case: false).to_sym, :skippable)
              "require_relative \"#{Utils.snake_case(resolved_type(change_case: false))}\""
            end
          end

          private

          def resolved_instance
            @resolved_instance ||= XmlCompiler.instance_variable_get(:@elements)[last_of_split]
          end

          def resolved_type(change_case: true)
            @current_type ||= type || resolved_instance&.type
            klass_name = last_of_split(@current_type)
            change_case ? Utils.snake_case(klass_name) : klass_name
          end

          def resolved_name(change_case: true)
            @current_name ||= name || resolved_instance&.name
            change_case ? Utils.snake_case(@current_name) : @current_name
          end

          def collection_option
            return if min_occurs.nil? && max_occurs.nil?

            min_value = min_occurs.nil? ? 1 : min_occurs
            ", collection: #{min_value}..#{max_value}"
          end

          def max_value
            if max_occurs == "unbounded"
              "Float::INFINITY"
            elsif max_occurs.to_i.positive?
              max_occurs.to_i
            elsif max_occurs.nil?
              1
            end
          end

          def default_option
            return if default.nil?

            ", default: #{default}"
          end

          def attribute_options
            [collection_option, default_option].compact.join
          end

          def last_of_split(field = ref)
            field&.split(":")&.last
          end

          def skippable?
            resolved_name == "schema_location"
          end
        end
      end
    end
  end
end
