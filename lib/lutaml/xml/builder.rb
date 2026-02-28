# frozen_string_literal: true

module Lutaml
  module Xml
    # Builder module for XML generation
    module Builder
      autoload :Nokogiri, "#{__dir__}/builder/nokogiri"
      autoload :Ox, "#{__dir__}/builder/ox"
      autoload :Oga, "#{__dir__}/builder/oga"
      autoload :Rexml, "#{__dir__}/builder/rexml"
    end
  end
end
