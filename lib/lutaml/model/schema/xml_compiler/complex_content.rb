module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class ComplexContent
          attr_accessor :restriction

          def initialize(restriction = nil)
            @restriction = restriction
          end

          def to_attributes(indent)
            restriction&.to_attributes(indent)
          end

          def to_xml_mapping(indent)
            restriction&.to_xml_mapping(indent)
          end

          def required_files
            restriction&.required_files
          end
        end
      end
    end
  end
end
