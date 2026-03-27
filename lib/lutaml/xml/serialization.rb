# frozen_string_literal: true

module Lutaml
  module Xml
    # XML Serialization module
    #
    # Contains XML-specific serialization logic extracted from
    # Lutaml::Model::Serialize for better separation of concerns.
    module Serialization
      autoload :FormatConversion, "#{__dir__}/serialization/format_conversion"
      autoload :ModelImportExt, "#{__dir__}/serialization/model_import_ext"
      autoload :InstanceMethods, "#{__dir__}/serialization/instance_methods"
    end
  end
end
