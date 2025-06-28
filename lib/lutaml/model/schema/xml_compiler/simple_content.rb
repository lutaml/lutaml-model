# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class SimpleContent
          attr_accessor :instances, :base_class

          def initialize
            @instances = []
            @base_class = nil
          end

          def <<(instance)
            @instances << instance
          end

          def instances?
            Utils.present?(instances)
          end

          def to_attributes(indent = nil)
            return nil unless instances?

            instances.filter_map { |instance| instance.to_attributes(indent) }.join("\n")
          end

          def to_xml_mapping(indent = nil)
            return nil unless instances?

            instances.filter_map { |instance| instance.to_xml_mapping(indent) }.join("\n")
          end

          def required_files
            instances.map(&:required_files).flatten.compact.uniq
          end
        end
      end
    end
  end
end
