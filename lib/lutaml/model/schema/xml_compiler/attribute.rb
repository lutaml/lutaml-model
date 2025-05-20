# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Attribute
          attr_accessor :id,
                        :ref,
                        :name,
                        :type,
                        :default,
                        :simple_type

          def initialize(name: nil, ref: nil)
            raise "Attribute name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
          end
        end
      end
    end
  end
end
