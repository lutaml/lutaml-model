# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # XML root directive of a generated class.
        # kind ∈ {:element, :type_name, :fragment}. name is nil for :fragment.
        class XmlRoot
          attr_accessor :kind, :name

          def initialize(kind:, name: nil)
            @kind = kind
            @name = name
          end
        end
      end
    end
  end
end
