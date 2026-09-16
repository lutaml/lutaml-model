# frozen_string_literal: true

module Lutaml
  module Xml
    # Public consumer surface for the plan fast path: one engine
    # parse + descriptor walk and direct model hydration, bypassing
    # the wrapper-tree construction that dominates large-document
    # consumer paths. The returned object is the mapped model root;
    # collection attributes remain collections on that model.
    module PlanWalk
      class << self
        # Build the plan, walk the document, and hydrate the mapped
        # root. Returns nil when the model is not plan-compilable.
        def call(model_class, xml, _options = {})
          register = Lutaml::Model::Config.default_register
          plan = PlanCompiler.compile(model_class, register)
          return nil unless plan

          document = ::Leptris::XML.parse(xml)
          root = document.root
          return nil unless root && root.name == plan[:tree][:name]

          PlanHydrator.call(model_class, plan,
                            plan[:descriptor].walk(root))
        end
      end
    end
  end
end
