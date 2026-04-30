# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      autoload :Xsd, "#{__dir__}/schema/xsd"
      autoload :XsdSchema, "#{__dir__}/schema/xsd_schema"
      autoload :RelaxngSchema, "#{__dir__}/schema/relaxng_schema"
      autoload :Builder, "#{__dir__}/schema/builder"
      autoload :BuiltinTypes, "#{__dir__}/schema/builtin_types"
    end
  end
end
