# frozen_string_literal: true

module Lutaml
  module Rdf
    module Namespaces
      class RdfSyntaxNamespace < Lutaml::Rdf::Namespace
        uri "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        prefix "rdf"
      end

      RdfNamespace = RdfSyntaxNamespace
    end
  end
end
