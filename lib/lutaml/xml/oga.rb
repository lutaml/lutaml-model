# frozen_string_literal: true

module Lutaml
  module Xml
    # Module namespace for Oga adapter supporting classes
    module Oga
      autoload :Element, "#{__dir__}/oga/element"
      autoload :Document, "#{__dir__}/oga/document"
    end
  end
end
