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

            # TODO: NEEDS MORE IMPLEMENTATION THAN THIS
            instances.map { |instance| instance.to_attributes(indent) }.compact.join("\n")
          end
        end
      end
    end
  end
end
