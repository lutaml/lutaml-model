# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Decorators
        autoload :Attribute, "#{__dir__}/decorators/attribute"
        autoload :Choices, "#{__dir__}/decorators/choices"
        autoload :ClassDefinition, "#{__dir__}/decorators/class_definition"
        autoload :DefinitionCollection,
                 "#{__dir__}/decorators/definition_collection"
      end
    end
  end
end
