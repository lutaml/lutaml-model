# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Data for a namespace declaration
      # NO XML construction - that's the adapter's job
      #
      # This class maintains MECE responsibility: it only stores declaration data.
      # XML string building belongs in adapters, NOT here.
      #
      # CRITICAL ARCHITECTURAL PRINCIPLE:
      # This class stores WHAT to declare and HOW to format it (data decisions).
      # Adapters build the actual xmlns="uri" or xmlns:prefix="uri" strings.
      class NamespaceDeclarationData
        attr_reader :namespace_class, :format, :declared_at,
                    :prefix_override, :source

        # Initialize namespace declaration data
        # @param namespace_class [Class] XmlNamespace class
        # @param format [Symbol] Format: :default or :prefix
        # @param declared_at [Symbol] Location: :here, :inherited, or :local_on_use
        # @param prefix_override [String, nil] Custom prefix from options
        # @param source [Symbol, nil] Source: :input if from parsed XML
        def initialize(namespace_class:, format:, declared_at:,
                       prefix_override: nil, source: nil)
          @namespace_class = namespace_class
          @format = format
          @declared_at = declared_at
          @prefix_override = prefix_override
          @source = source
          validate!
        end

        # Check if prefix format
        # @return [Boolean]
        def prefix_format?
          @format == :prefix
        end

        # Check if default format
        # @return [Boolean]
        def default_format?
          @format == :default
        end

        # Check if declared at this location
        # @return [Boolean]
        def declared_here?
          @declared_at == :here
        end

        # Check if inherited from parent
        # @return [Boolean]
        def inherited?
          @declared_at == :inherited
        end

        # Check if local on use
        # @return [Boolean]
        def local_on_use?
          @declared_at == :local_on_use
        end

        # Check if from parsed input
        # @return [Boolean]
        def from_input?
          @source == :input
        end

        # Get namespace URI
        # @return [String]
        def uri
          @namespace_class.uri
        end

        # Get effective prefix (override or default)
        # @return [String, nil]
        def prefix
          @prefix_override || @namespace_class.prefix_default
        end

        # Get namespace key for lookups
        # @return [String]
        def key
          @namespace_class.to_key
        end

        # Check if namespace has a prefix defined
        # @return [Boolean]
        def has_prefix?
          !prefix.nil?
        end

        # Get element_form_default setting
        # @return [Symbol] :qualified or :unqualified
        def element_form_default
          if @namespace_class.respond_to?(:element_form_default)
            @namespace_class.element_form_default
          else
            :qualified  # W3C default
          end
        end

        # Get attribute_form_default setting
        # @return [Symbol] :qualified or :unqualified
        def attribute_form_default
          if @namespace_class.respond_to?(:attribute_form_default)
            @namespace_class.attribute_form_default
          else
            :unqualified  # W3C default
          end
        end

        # String representation for debugging
        # @return [String]
        def inspect
          "#<NamespaceDeclarationData #{@namespace_class} format=#{@format} declared_at=#{@declared_at}>"
        end

        # Equality check
        # @param other [NamespaceDeclarationData]
        # @return [Boolean]
        def ==(other)
          other.is_a?(NamespaceDeclarationData) &&
            other.namespace_class == @namespace_class &&
            other.format == @format &&
            other.declared_at == @declared_at &&
            other.prefix_override == @prefix_override &&
            other.source == @source
        end

        alias eql? ==

        # Hash code for use in sets/hashes
        # @return [Integer]
        def hash
          [@namespace_class, @format, @declared_at, @prefix_override, @source].hash
        end

        private

        # Validate declaration data
        # @raise [ArgumentError] if invalid
        def validate!
          unless [:default, :prefix].include?(@format)
            raise ArgumentError, "Format must be :default or :prefix, got #{@format.inspect}"
          end

          unless [:here, :inherited, :local_on_use].include?(@declared_at)
            raise ArgumentError, "declared_at must be :here, :inherited, or :local_on_use, got #{@declared_at.inspect}"
          end

          if @namespace_class.nil?
            raise ArgumentError, "Namespace class cannot be nil"
          end

          if @source && @source != :input
            raise ArgumentError, "Source must be nil or :input, got #{@source.inspect}"
          end

          # Validate prefix override if present
          if @prefix_override && !@prefix_override.is_a?(String)
            raise ArgumentError, "Prefix override must be a String, got #{@prefix_override.class}"
          end

          # Validate that namespace class has required methods
          unless @namespace_class.respond_to?(:uri)
            raise ArgumentError, "Namespace class must respond to :uri"
          end

          unless @namespace_class.respond_to?(:to_key)
            raise ArgumentError, "Namespace class must respond to :to_key"
          end
        end
      end
    end
  end
end