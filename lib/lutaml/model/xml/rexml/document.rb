require_relative "element"

module Lutaml
  module Model
    module Xml
      module Rexml
        class Document
          attr_reader :root

          def initialize(root)
            @root = root
          end

          def to_xml(options = {})
            @root.to_xml(options)
          end
        end
      end
    end
  end
end
