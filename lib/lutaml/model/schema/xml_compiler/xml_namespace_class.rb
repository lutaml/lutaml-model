# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD XmlNamespace subclass — inherits the full render flow and
        # URI heuristics from Lutaml::Model::Schema::NamespaceRenderer.
        # No XSD-specific overrides needed.
        class XmlNamespaceClass < Lutaml::Model::Schema::NamespaceRenderer
        end
      end
    end
  end
end
