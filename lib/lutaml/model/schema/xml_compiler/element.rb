# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Element
          attr_accessor :id,
                        :ref,
                        :name,
                        :type,
                        :fixed,
                        :default,
                        :max_occurs,
                        :min_occurs,
                        :simple_type,
                        :complex_type

          def initialize(name: nil, ref: nil)
            raise "Element name is required" if Utils.blank?(name) && Utils.blank?(ref)

            @name = name
            @ref = ref
          end
        end
      end
    end
  end
end
