# frozen_string_literal: true

require_relative "xml/namespace"

module Lutaml
  module Model
    # Backward compatibility alias for Xml::Namespace
    # @deprecated Use Lutaml::Model::Xml::Namespace instead
    XmlNamespace = Xml::Namespace
  end
end
