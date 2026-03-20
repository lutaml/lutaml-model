# frozen_string_literal: true

module Lutaml
  module Model
    # Base listener class for the listener-based mapping model.
    #
    # Listeners are handlers that respond to format elements/keys (e.g., XML
    # element names, JSON keys). Multiple listeners per element are allowed,
    # and all matching listeners are invoked during parsing.
    #
    # There are two types of listeners:
    # - Simple listeners: Created via map_element/map_attribute DSL (no handler block).
    #   The framework handles the default deserialization behavior.
    # - Complex listeners: Created via on_element/on_attribute DSL (with handler block).
    #   The block provides custom deserialization logic.
    #
    # @example Simple listener (implicit handler)
    #   Lutaml::Xml::Mapping do
    #     map_element "Documentation", to: :documentation
    #   end
    #
    # @example Complex listener (explicit handler)
    #   Lutaml::Xml::Mapping do
    #     on_element "CustomElement", id: :custom_parse do |element, context|
    #       context[:custom] = CustomParser.parse(element)
    #     end
    #   end
    #
    # @example Multiple listeners for same element
    #   class MyMapping < Lutaml::Xml::Mapping
    #     on_element "Documentation", id: :parse_docs do |element, context|
    #       context[:documentation] = Documentation.from_xml(element)
    #     end
    #
    #     on_element "Documentation", id: :log_docs do |element, context|
    #       logger.info("Parsing docs")
    #     end
    #   end
    #
    # @example Inheritance with override
    #   class ExtendedMapping < BaseMapping
    #     # Overrides parent's :parse_docs listener
    #     on_element "Documentation", id: :parse_docs do |element, context|
    #       context[:documentation] = EnhancedDocs.from_xml(element)
    #     end
    #
    #     # New listener (added to parent's)
    #     on_element "Extension", id: :parse_ext do |element, context|
    #       context[:extension] = Extension.from_xml(element)
    #     end
    #
    #     # Remove a specific parent listener
    #     omit_listener "TaggedValue", id: :validate_tags
    #
    #     # Remove all listeners for an element
    #     omit_element "UnusedElement"
    #   end
    class Listener
      attr_reader :id, :target, :handler, :options

      # @param id [Symbol, String, nil] Unique identifier for this listener.
      #   Used for override/omit operations. Defaults to nil (no override/omit support).
      # @param target [String, Symbol] The element name or key this listener responds to.
      # @param handler [Proc, nil] Custom handler block for complex listeners.
      #   Nil for simple listeners (framework handles deserialization).
      # @param options [Hash] Additional options for the listener.
      def initialize(id:, target:, handler: nil, **options)
        @id = id
        @target = target.to_s if target
        @handler = handler
        @options = options.freeze
        freeze
      end

      # Returns true if this is a simple listener (no custom handler).
      # Simple listeners rely on framework default deserialization behavior.
      #
      # @return [Boolean]
      def simple?
        @handler.nil?
      end

      # Returns true if this is a complex listener (has a custom handler).
      #
      # @return [Boolean]
      def complex?
        !simple?
      end

      # Invoke the listener's handler with the given arguments.
      #
      # @param args [Array] Arguments to pass to the handler block
      # @return [Object] Result of the handler invocation
      def call(*)
        if simple?
          raise NoHandlerError,
                "Cannot call simple listener #{id.inspect}"
        end

        @handler.call(*)
      end

      # Error raised when attempting to invoke a simple listener as a complex one.
      class NoHandlerError < StandardError; end

      def inspect
        "#<#{self.class.name} id=#{id.inspect} target=#{target.inspect} " \
          "simple=#{simple?}>"
      end

      def to_s
        inspect
      end

      # Equality based on id and target (for deduplication)
      def eql?(other)
        other.is_a?(Listener) &&
          id == other.id &&
          target == other.target
      end
      alias == eql?
    end
  end
end
