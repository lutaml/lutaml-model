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
            return if instance.nil?

            @instances << instance
          end

          def to_attributes(indent = nil)
            instances.filter_map do |instance|
              instance.to_attributes(indent)
            end.join("\n")
          end

          def to_xml_mapping(indent = nil)
            instances.filter_map do |instance|
              instance.to_xml_mapping(indent)
            end.join("\n")
          end

          def required_files
            instances.map(&:required_files).flatten.compact.uniq
          end
        end
      end
    end
  end
end
