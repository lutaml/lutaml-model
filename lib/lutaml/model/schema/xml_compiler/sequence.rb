# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Sequence
          attr_accessor :instances

          XML_MAPPING_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= indent %>sequence do
            <%= content -%>
            <%= indent %>end
          TEMPLATE

          def initialize
            @instances = []
          end

          def <<(instance)
            return if instance.nil?

            @instances << instance
          end

          def to_attributes(indent)
            instances.filter_map { |instance| instance.to_attributes(indent) }.join
          end

          def to_xml_mapping(indent)
            content = xml_block_content(indent)
            return "" if content.empty?

            XML_MAPPING_TEMPLATE.result(binding)
          end

          def required_files
            @instances.map(&:required_files)
          end

          private

          def xml_block_content(indent)
            instances.filter_map { |instance| instance.to_xml_mapping(indent * 2) }.join
          end
        end
      end
    end
  end
end
