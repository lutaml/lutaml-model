# frozen_string_literal: true

module Lutaml
  module Xml
    module TypeNamespace
      autoload :Collector, "#{__dir__}/type_namespace/collector"
      autoload :Reference, "#{__dir__}/type_namespace/reference"
      autoload :Resolver, "#{__dir__}/type_namespace/resolver"
      autoload :Planner, "#{__dir__}/type_namespace/planner"
      autoload :Declaration, "#{__dir__}/type_namespace/declaration"
    end
  end
end
