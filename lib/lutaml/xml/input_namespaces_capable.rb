# frozen_string_literal: true

module Lutaml
  module Xml
    # Marker module for XML elements that support input_namespaces
    #
    # This module is included by XML adapter elements that parse and preserve
    # namespace declarations from input XML documents. It enables capability
    # detection without relying on respond_to? or specific class checks.
    #
    # Included by:
    # - NokogiriElement (Nokogiri adapter)
    # - Oga::Element (Oga adapter)
    #
    # Not included by:
    # - OxElement (Ox adapter - doesn't support namespace preservation)
    #
    # @example Checking capability
    #   if element.is_a?(InputNamespacesCapable)
    #     namespaces = element.input_namespaces
    #   end
    #
    module InputNamespacesCapable
      # This module is a marker - no methods defined
      # The input_namespaces method is defined in each adapter's element class
    end
  end
end
