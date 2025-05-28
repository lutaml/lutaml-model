# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class AttributeGroup
          attr_accessor :name, :ref, :attributes, :attribute_groups

          def initialize(name: nil, ref: nil)
            raise "AttributeGroup name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
          end
        end
      end
    end
  end
end
