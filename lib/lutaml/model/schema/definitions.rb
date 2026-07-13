# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        autoload :GroupImport,    "#{__dir__}/definitions/group_import"
        autoload :MemberWalk,     "#{__dir__}/definitions/member_walk"
        autoload :TypeRef,        "#{__dir__}/definitions/type_ref"
        autoload :XmlRoot,        "#{__dir__}/definitions/xml_root"
        autoload :Attribute,      "#{__dir__}/definitions/attribute"
        autoload :Choice,         "#{__dir__}/definitions/choice"
        autoload :Sequence,       "#{__dir__}/definitions/sequence"
        autoload :Facet,          "#{__dir__}/definitions/facet"
        autoload :TransformFacet, "#{__dir__}/definitions/transform_facet"
        autoload :SimpleContent,  "#{__dir__}/definitions/simple_content"
        autoload :Model,          "#{__dir__}/definitions/model"
        autoload :RestrictedType, "#{__dir__}/definitions/restricted_type"
        autoload :UnionType,      "#{__dir__}/definitions/union_type"
        autoload :Namespace,      "#{__dir__}/definitions/namespace"
      end
    end
  end
end
