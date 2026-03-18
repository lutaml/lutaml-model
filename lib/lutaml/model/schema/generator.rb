module Lutaml
  module Model
    module Schema
      module Generator
        autoload :Definition, "#{__dir__}/generator/definition"
        autoload :DefinitionsCollection,
                 "#{__dir__}/generator/definitions_collection"
        autoload :PropertiesCollection,
                 "#{__dir__}/generator/properties_collection"
        autoload :Property, "#{__dir__}/generator/property"
        autoload :Ref, "#{__dir__}/generator/ref"
      end
    end
  end
end
