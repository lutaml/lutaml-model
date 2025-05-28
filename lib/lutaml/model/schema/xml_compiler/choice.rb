# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Choice
          attr_accessor :instances, :min_occurs, :max_occurs

          INDENT = "  "

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>choice<%= block_options %> do
            <%= instances.map { |instance| instance.to_attributes(indent + INDENT) }.join -%>
            <%= indent %>end
          TEMPLATE

          def initialize
            @instances = []
          end

          def <<(instance)
            return if instance.nil?

            @instances << instance
          end

          def to_attributes(indent = INDENT)
            TEMPLATE.result(binding)
          end

          def to_xml_mapping(indent = INDENT)
            instances.filter_map { |instance| instance.to_xml_mapping(indent) }.join
          end

          def required_files
            @instances.map(&:required_files).flatten.compact
          end

          private

          def min_option
            "min: #{min_occurs.nil? ? 1 : min_occurs.to_i}"
          end

          def max_option
            value = case max_occurs
                    when "unbounded"
                      "Float::INFINITY"
                    when NilClass
                      1
                    else
                      max_occurs.to_i
                    end
            ", max: #{value}"
          end

          def block_options
            ["(", min_option, max_option, ")"].compact.join
          end
        end
      end
    end
  end
end
