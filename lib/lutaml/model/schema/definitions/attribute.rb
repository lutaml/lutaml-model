# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # One attribute on a generated class.
        class Attribute
          attr_accessor :name, :type, :xml_name, :kind, :collection,
                        :default, :documentation, :initialize_empty

          def initialize(name:, type:, xml_name:, kind:,
                         collection: false, default: nil,
                         documentation: nil, initialize_empty: false)
            @name = name
            @type = type
            @xml_name = xml_name
            @kind = kind
            @collection = collection
            @default = default
            @documentation = documentation
            @initialize_empty = initialize_empty
          end
        end
      end
    end
  end
end
