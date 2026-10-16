# frozen_string_literal: true

module Lutaml
  module Xml
    module Leptris
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

            # Strict: the fast path's error contract wraps the engine's
            # parse errors as InvalidFormatError (leptris-model#966).
            # Binding 1.9.361.1 flipped parse()'s default to
            # recover-never-raise (nokogiri parity, ruby#465) — the
            # strict intent must ride explicitly there; older bindings
            # raise by default and reject the kwarg.
            document =
              if ::Leptris::XML::Document.method(:parse)
                   .parameters.any? { |_, key| key == :strict }
                ::Leptris::XML.parse(xml, strict: true)
              else
                ::Leptris::XML.parse(xml)
              end
            root = document.root
            return nil unless root && root.name == plan[:tree][:name]

            PlanHydrator.call(model_class, plan,
                              plan[:descriptor].walk(root),
                              node: root)
          end
        end
      end
    end
  end
end
