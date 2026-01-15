# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Configuration for namespace_scope directive
      # Replaces {namespace:, declare:} hash
      #
      # This class maintains MECE responsibility: it only stores scope configuration.
      # Decision-making about declaration belongs in the planner.
      class NamespaceScopeConfig
        attr_reader :namespace_class, :declare_mode

        # Initialize namespace scope configuration
        # @param namespace_class [Class] XmlNamespace class
        # @param declare_mode [Symbol] Declaration mode: :auto or :always
        def initialize(namespace_class, declare_mode = :auto)
          @namespace_class = namespace_class
          @declare_mode = declare_mode
          validate!
        end

        # Determine if namespace should be declared based on usage
        # @param used [Boolean] Whether namespace is actually used
        # @return [Boolean]
        def should_declare?(used)
          case @declare_mode
          when :always
            true
          when :auto
            used
          else
            false
          end
        end

        # Check if this is auto mode
        # @return [Boolean]
        def auto_mode?
          @declare_mode == :auto
        end

        # Check if this is always mode
        # @return [Boolean]
        def always_mode?
          @declare_mode == :always
        end

        # Get namespace key for lookups
        # @return [String]
        def key
          @namespace_class.to_key
        end

        # Get namespace URI
        # @return [String]
        def uri
          @namespace_class.uri
        end

        # Get namespace prefix
        # @return [String, nil]
        def prefix
          @namespace_class.prefix_default
        end

        # String representation for debugging
        # @return [String]
        def inspect
          "#<NamespaceScopeConfig #{@namespace_class} mode=#{@declare_mode}>"
        end

        # Equality check
        # @param other [NamespaceScopeConfig]
        # @return [Boolean]
        def ==(other)
          other.is_a?(NamespaceScopeConfig) &&
            other.namespace_class == @namespace_class &&
            other.declare_mode == @declare_mode
        end

        alias eql? ==

        # Hash code for use in sets/hashes
        # @return [Integer]
        def hash
          [@namespace_class, @declare_mode].hash
        end

        private

        # Validate configuration
        # @raise [ArgumentError] if invalid
        def validate!
          unless [:auto, :always].include?(@declare_mode)
            raise ArgumentError, "Declare mode must be :auto or :always, got #{@declare_mode.inspect}"
          end

          if @namespace_class.nil?
            raise ArgumentError, "Namespace class cannot be nil"
          end

          unless @namespace_class.respond_to?(:to_key)
            raise ArgumentError, "Namespace class must respond to :to_key"
          end
        end
      end
    end
  end
end