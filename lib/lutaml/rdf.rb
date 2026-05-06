# frozen_string_literal: true

require_relative "model"

module Lutaml
  module Rdf
    autoload :Error, "#{__dir__}/rdf/error"
    autoload :Iri, "#{__dir__}/rdf/iri"
    autoload :LanguageTagged, "#{__dir__}/rdf/language_tagged"
    autoload :Literal, "#{__dir__}/rdf/literal"
    autoload :Namespace, "#{__dir__}/rdf/namespace"
    autoload :NamespaceSet, "#{__dir__}/rdf/namespace_set"
    autoload :Mapping, "#{__dir__}/rdf/mapping"
    autoload :MappingRule, "#{__dir__}/rdf/mapping_rule"
    autoload :MemberRule, "#{__dir__}/rdf/member_rule"
    autoload :Namespaces, "#{__dir__}/rdf/namespaces"
    autoload :Transform, "#{__dir__}/rdf/transform"
  end
end
