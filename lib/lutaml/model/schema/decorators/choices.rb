# frozen_string_literal: true

require_relative "attribute"

module Lutaml
  module Model
    module Schema
      module Decorators
        class Choices
          attr_reader :attributes

          # Decorates a collection of choice attributes.
          # This class is used to handle attributes that are part of a choice
          # constraint in a JSON schema. It provides a way to access the choice
          # attributes in a structured manner.
          def initialize(attributes)
            @attributes = attributes.values
          end

          def choice?
            true
          end

          def polymorphic?
            false
          end
        end
      end
    end
  end
end
