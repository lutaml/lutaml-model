# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class AttributeGroup
          attr_accessor :name, :ref, :instances

          def initialize(name: nil, ref: nil)
            @name = name
            @ref = ref
            @instances = []
          end

          def <<(instance)
            return if instance.nil?

            @instances << instance
          end

          def to_attributes(indent)
            resolved_instances.map { |instance| instance.to_attributes(indent) }
          end

          def to_xml_mapping(indent)
            resolved_instances.map do |instance|
              instance.to_xml_mapping(indent)
            end
          end

          def required_files
            resolved_instances.map(&:required_files)
          end

          private

          def resolved_instances
            return @instances unless Utils.present?(@ref)

            XmlCompiler.attribute_groups[@ref]&.instances
          end
        end
      end
    end
  end
end
