# frozen_string_literal: true

# Backward compatibility stub.
# SchemaLocation and Location have moved to Lutaml::Xml module.
# This file provides aliases for code that references Lutaml::Model::SchemaLocation.

begin
  require_relative "../xml/schema_location"

  module Lutaml
    module Model
      Location = ::Lutaml::Xml::Location
      SchemaLocation = ::Lutaml::Xml::SchemaLocation
    end
  end
rescue LoadError
  # XML module not available - SchemaLocation requires XML
end
