# frozen_string_literal: true

module Lutaml
  module Xml
    module Error
      # Raised when there is a general XML configuration error
      #
      # This error is raised for XML configuration issues that don't fit
      # into more specific error categories.
      #
      # @example
      #   raise XmlConfigurationError.new("Missing required namespace declaration")
      class XmlConfigurationError < XmlError
      end
    end
  end
end
