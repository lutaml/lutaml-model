# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Renderers
        autoload :Registration,   "#{__dir__}/renderers/registration"
        autoload :MemberDecls,    "#{__dir__}/renderers/member_decls"
        autoload :Mappings,       "#{__dir__}/renderers/mappings"
        autoload :Model,          "#{__dir__}/renderers/model"
        autoload :RestrictedType, "#{__dir__}/renderers/restricted_type"
        autoload :Union,          "#{__dir__}/renderers/union"
        autoload :Namespace,      "#{__dir__}/renderers/namespace"
      end
    end
  end
end
