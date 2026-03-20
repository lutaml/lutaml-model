# frozen_string_literal: true

module Lutaml
  module Xml
    # XML-specific listener for the listener-based mapping model.
    #
    # XML listeners respond to XML element names and can have custom handler
    # blocks for complex deserialization logic.
    #
    # @example Adding a listener to a mapping class
    #   class MyMapping < Lutaml::Xml::Mapping
    #     on_element "CustomElement" do |element, context|
    #       context[:custom] = CustomParser.parse(element)
    #     end
    #   end
    #
    # @example Listener with ID for override/omit support
    #   class MyMapping < Lutaml::Xml::Mapping
    #     on_element "Documentation", id: :parse_docs do |element, context|
    #       context[:documentation] = Documentation.from_xml(element)
    #     end
    #   end
    class Listener < ::Lutaml::Model::Listener
      # @param id [Symbol, String, nil] Unique identifier for override/omit.
      # @param target [String] XML element name this listener responds to.
      # @param handler [Proc, nil] Custom block handler.
      # @param options [Hash] Additional options.
      def initialize(id:, target:, handler: nil, **)
        super
      end
    end
  end
end
