module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class ComplexType
          attr_accessor :id,
                        :name,
                        :mixed,
                        :group,
                        :choice,
                        :sequence,
                        :attributes,
                        :simple_content,
                        :complex_content,
                        :attribute_groups

          def initialize
            @attributes = []
            @attribute_groups = []
          end
        end
      end
    end
  end
end
