# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedRexml
      autoload :EntityReference,
               "moxml/adapter/customized_rexml/entity_reference"
      autoload :Formatter, "moxml/adapter/customized_rexml/formatter"
    end
  end
end
