# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Sequence
          attr_accessor :instances

          INDENT = "  "

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= instances.map { |instance| instance.to_attributes(indent) }.join -%>
          TEMPLATE

          XML_MAPPING_TEMPLATE = ERB.new(<<~XML_MAPPING_TEMPLATE, trim_mode: "-")
            <%= indent %>sequence do
            <%= block_content(indent) -%>
            <%= indent %>end
          XML_MAPPING_TEMPLATE

          def initialize
            @instances = []
          end

          def <<(instance)
            @instances << instance
          end

          def to_attributes(indent = INDENT)
            TEMPLATE.result(binding)
          end

          def to_xml_mapping(indent = INDENT)
            return "" if block_content(indent).empty?

            XML_MAPPING_TEMPLATE.result(binding)
          end

          def required_files
            @instances.map(&:required_files)
          end

          def block_content(indent)
            instances.map { |instance| instance.to_xml_mapping(indent + INDENT) }.compact.join
          end
        end
      end
    end
  end
end
