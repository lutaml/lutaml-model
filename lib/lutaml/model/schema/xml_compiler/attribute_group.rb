# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class AttributeGroup
          attr_accessor :name, :ref, :instances

          def initialize(name: nil, ref: nil)
            raise "AttributeGroup name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
            @instances = []
          end

          def <<(instance)
            @instances << instance
          end

          def to_attributes(indent)
            instances&.map { |instance| instance.to_attributes(indent) }
          end

          def to_xml_mapping(indent)
            instances&.map { |instance| instance.to_xml_mapping(indent) }
          end

          def required_files
            instances&.map(&:required_files)
          end
        end
      end
    end
  end
end
