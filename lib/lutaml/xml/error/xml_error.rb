# frozen_string_literal: true

module Lutaml
  module Xml
    module Error
      # Base class for all XML-related errors
      #
      # Provides a common base for XML-specific error handling
      # that can be caught separately from general Lutaml::Model::Error.
      #
      # @example Catching all XML errors
      #   begin
      #     model.to_xml
      #   rescue Lutaml::Xml::Error::XmlError => e
      #     puts "XML error: #{e.message}"
      #   end
      class XmlError < Lutaml::Model::Error
      end
    end
  end
end
