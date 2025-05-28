module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class ComplexContentRestriction
          attr_accessor :base, :instances

          def initialize(base: nil, instances: [])
            @base = base
            @instances = instances
          end

          def <<(instance)
            return if instance.nil?

            @instances << instance
          end

          def to_attributes(indent)
            instances.map { |instance| instance.to_attributes(indent) }
          end

          def to_xml_mapping(indent)
            instances.map { |instance| instance.to_xml_mapping(indent) }
          end

          def required_files
            instances.map(&:required_files)
          end
        end
      end
    end
  end
end
