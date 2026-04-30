# frozen_string_literal: true

module Lutaml
  module Xml
    # Builder module for XML generation
    module Builder
      autoload :Oga, "#{__dir__}/builder/oga"
      Lutaml::Model::RuntimeCompatibility.autoload_native(
        self,
        Nokogiri: "#{__dir__}/builder/nokogiri",
        Ox: "#{__dir__}/builder/ox",
        Rexml: "#{__dir__}/builder/rexml",
      )
    end
  end
end
