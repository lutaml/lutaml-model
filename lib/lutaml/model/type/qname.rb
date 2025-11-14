require_relative "value"

module Lutaml
  module Model
    module Type
      # QName (Qualified Name) type
      #
      # Represents XML qualified names in prefix:localName format
      #
      # @example Using QName type
      #   attribute :ref_type, :qname
      class QName < Value
        attr_reader :prefix, :local_name, :namespace_uri

        def initialize(value)
          if value.is_a?(QName)
            @prefix = value.prefix
            @local_name = value.local_name
            @namespace_uri = value.namespace_uri
            @value = value.to_s
          else
            @value = self.class.cast(value)
            parse_qname(@value) if @value
          end
        end

        def self.cast(value, _options = {})
          return nil if value.nil?
          return value.to_s if value.is_a?(QName)

          value.to_s
        end

        def self.serialize(value)
          return nil if value.nil?
          return value.to_s if value.is_a?(QName)

          value.to_s
        end

        # XSD type for QName
        #
        # @return [String] xs:QName
        def self.xsd_type
          "xs:QName"
        end

        def to_s
          @value
        end

        # Create QName from components
        #
        # @param prefix [String, nil] the namespace prefix
        # @param local_name [String] the local name
        # @param namespace_uri [String, nil] the namespace URI
        # @return [QName] the QName instance
        def self.from_parts(prefix: nil, local_name:, namespace_uri: nil)
          qname_str = prefix ? "#{prefix}:#{local_name}" : local_name
          new(qname_str).tap do |qname|
            qname.instance_variable_set(:@namespace_uri, namespace_uri)
          end
        end

        private

        def parse_qname(str)
          return unless str

          parts = str.split(":", 2)
          if parts.length == 2
            @prefix = parts[0]
            @local_name = parts[1]
          else
            @prefix = nil
            @local_name = parts[0]
          end
          @namespace_uri = nil # Will be resolved from context
        end
      end
    end
  end
end