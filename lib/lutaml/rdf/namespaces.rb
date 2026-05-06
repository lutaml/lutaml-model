# frozen_string_literal: true

module Lutaml
  module Rdf
    module Namespaces
      autoload :SkosNamespace, "#{__dir__}/namespaces/skos_namespace"
      autoload :DctermsNamespace, "#{__dir__}/namespaces/dcterms_namespace"
      autoload :RdfNamespace, "#{__dir__}/namespaces/rdf_namespace"
      autoload :RdfsNamespace, "#{__dir__}/namespaces/rdfs_namespace"
      autoload :OwlNamespace, "#{__dir__}/namespaces/owl_namespace"
      autoload :XsdNamespace, "#{__dir__}/namespaces/xsd_namespace"
    end
  end
end
