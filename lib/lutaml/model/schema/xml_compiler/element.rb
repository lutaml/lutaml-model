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

          def initialize(name: nil, ref: nil)
            @name = name
            @ref = ref
          end

          def to_attributes(indent)
            return if skippable?
            return unless resolved_type

            "#{indent}attribute :#{resolved_name}, :#{resolved_type}#{attribute_options}\n"
          end

          def to_xml_mapping(indent)
            return if skippable?
            return unless resolved_type

            "#{indent}map_element :#{resolved_name(change_case: false)}, to: :#{resolved_name}#{render_default_option}\n"
          end

          def required_files
            return if skippable?

            element_type = resolved_type(change_case: false)
            return "require \"bigdecimal\"" if element_type == "decimal"
            return if SimpleType.skippable?(element_type)

            "require_relative \"#{Utils.snake_case(element_type)}\""
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

            min_value = min_occurs.nil? ? 1 : min_occurs.to_i
            ", collection: #{min_value}..#{max_value}"
          end

          def max_value
            return "Float::INFINITY" if max_occurs == "unbounded"
            return 1 if max_occurs.nil?

            max_occurs.to_i
          end

          def default_option
            return if default.nil?

            ", default: -> { #{default.inspect} }"
          end

          def render_default_option
            return if default.nil?

            ", render_default: true"
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
