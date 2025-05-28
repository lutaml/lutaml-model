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

          INDENT = "  "

          TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            class <%= Utils.camel_case(name) %> < Lutaml::Model::Serializable
            <%= sequence.to_class(indent) -%>
            end
          TEMPLATE

          def initialize
            @attributes = []
            @attribute_groups = []
          end

          def to_class(indent = INDENT)
            TEMPLATE.result(binding)
          end
        end
      end
    end
  end
end
