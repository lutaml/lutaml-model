# frozen_string_literal: true

module Lutaml
  module Xml
    # Builder module for XML generation
    module Builder
      autoload :Base, "#{__dir__}/builder/base"
      autoload :Oga, "#{__dir__}/builder/oga"
      autoload :Rexml, "#{__dir__}/builder/rexml"
      Lutaml::Model::RuntimeCompatibility.autoload_native(
        self,
        Nokogiri: "#{__dir__}/builder/nokogiri",
        Ox: "#{__dir__}/builder/ox",
      )
    end
  end
end
