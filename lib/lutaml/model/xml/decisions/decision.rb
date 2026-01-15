# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      module Decisions
        # Immutable value object representing a namespace decision
        #
        # @attr_reader [Symbol] format - :prefix or :default
        # @attr_reader [String, nil] prefix - The prefix to use (nil for default format)
        # @attr_reader [Class, nil] namespace_class - The XmlNamespace class
        # @attr_reader [String, nil] reason - Human-readable reason for decision
        class Decision
          attr_reader :format, :prefix, :namespace_class, :reason

          def initialize(format:, prefix: nil, namespace_class: nil, reason: nil)
            raise ArgumentError, "Format must be :prefix or :default" unless [:prefix, :default].include?(format)
            raise ArgumentError, "Prefix required for :prefix format" if format == :prefix && prefix.nil?
            raise ArgumentError, "Prefix must be nil for :default format" if format == :default && !prefix.nil?

            @format = format
            @prefix = prefix
            @namespace_class = namespace_class
            @reason = reason
            freeze
          end

          # Convenience factory for prefix format decisions
          def self.prefix(prefix:, namespace_class:, reason:)
            new(format: :prefix, prefix: prefix, namespace_class: namespace_class, reason: reason)
          end

          # Convenience factory for default format decisions
          def self.default(namespace_class:, reason:)
            new(format: :default, prefix: nil, namespace_class: namespace_class, reason: reason)
          end

          # Check if this decision uses prefix format
          def uses_prefix?
            @format == :prefix
          end

          # Check if this decision uses default format
          def uses_default?
            @format == :default
          end

          # Equality based on format, prefix, and namespace_class
          #
          # Value objects are equal if all their attributes are equal.
          def ==(other)
            return false unless other.is_a?(Decision)
            @format == other.format && @prefix == other.prefix && @namespace_class == other.namespace_class
          end
          alias :eql? :==

          def hash
            [@format, @prefix, @namespace_class].hash
          end

          def to_s
            ns_info = @namespace_class ? "#{@namespace_class}" : "no-namespace"
            if uses_prefix?
              "Decision[#{ns_info}]: format=#{@format}, prefix=#{@prefix}, reason=#{@reason}"
            else
              "Decision[#{ns_info}]: format=#{@format}, reason=#{@reason}"
            end
          end
        end
      end
    end
  end
end
