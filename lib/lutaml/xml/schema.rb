# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      Lutaml::Model::RuntimeCompatibility.autoload_native(
        self,
        Xsd: "#{__dir__}/schema/xsd",
        XsdSchema: "#{__dir__}/schema/xsd_schema",
        RelaxngSchema: "#{__dir__}/schema/relaxng_schema",
        Builder: "#{__dir__}/schema/builder",
        BuiltinTypes: "#{__dir__}/schema/builtin_types",
      )
    end
  end
end
