# frozen_string_literal: true

module Lutaml
  module Xml
    module Serialization
      # XML-specific format conversion hooks for Serialize module
      #
      # This module provides XML-specific serialization logic that extends
      # the format-agnostic Lutaml::Model::Serialize::FormatConversion.
      #
      # It is included into Serialize::ClassMethods when XML format is loaded.
      module FormatConversion
        # XML-specific pre-processing before deserialization
        #
        # @param format [Symbol] The format (:xml)
        # @param register [Lutaml::Model::Register] The register for type resolution
        def pre_process_xml_deserialization(register)
          return unless mappings[:xml]

          mappings[:xml].ensure_mappings_imported!(register)
        end

        # XML-specific pre-processing before serialization
        #
        # @param format [Symbol] The format (:xml)
        # @param register [Lutaml::Model::Register] The register for type resolution
        def pre_process_xml_serialization(register)
          return unless mappings[:xml]

          mappings[:xml].ensure_mappings_imported!(register)
        end

        # Validate XML format for deserialization
        #
        # @param doc [Object] The parsed document
        # @param options [Hash] Additional options
        # @param register [Lutaml::Model::Register] The register
        def validate_xml_deserialization(doc, options, register)
          valid = root?(register) || options[:from_collection]
          raise Lutaml::Model::NoRootMappingError.new(self) unless valid

          options[:encoding] = doc.encoding
          if doc.respond_to?(:doctype) && doc.doctype
            options[:doctype] = doc.doctype
          end
        end

        # Validate XML format for serialization
        #
        # @param options [Hash] Additional options
        def validate_xml_serialization(options)
          # No additional validation needed for serialization
        end

        # Process XML-specific options for serialization
        #
        # @param options [Hash] The options hash
        # @return [Hash] The modified options hash
        def process_xml_serialization_options(options)
          options[:mapper_class] = self

          # Handle prefix option for XML
          if options.key?(:prefix)
            prefix_option = options[:prefix]

            case prefix_option
            when true
              # Force prefix format for all namespaces
              options[:use_prefix] = true
            when String
              # Use specific custom prefix
              options[:use_prefix] = prefix_option
            when false
              # Explicitly force default format (disable format preservation)
              options[:use_prefix] = false
            end
            # If prefix_option is nil, don't set use_prefix (allow format preservation)
            options.delete(:prefix)
          end

          # Apply namespace prefix overrides for XML format
          if options[:namespaces]
            options = apply_namespace_overrides(options)
          end

          options
        end

        # Apply namespace prefix overrides for XML serialization
        #
        # @param options [Hash] The options hash
        # @return [Hash] The modified options hash
        def apply_namespace_overrides(options)
          namespaces = options[:namespaces]
          return options unless namespaces.is_a?(Array)

          # Build a namespace URI to prefix mapping
          ns_prefix_map = {}
          namespaces.each do |ns_config|
            if ns_config.is_a?(Hash)
              ns_class = ns_config[:namespace]
              prefix = ns_config[:prefix]

              if ns_class.is_a?(Class) && ns_class < Lutaml::Xml::Namespace && prefix
                ns_prefix_map[ns_class.uri] = prefix.to_s
              end
            end
          end

          unless ns_prefix_map.empty?
            options[:namespace_prefix_map] = ns_prefix_map
          end
          options
        end

        # XML-specific mapping processing
        #
        # @param block [Proc] The DSL block to evaluate
        def process_xml_mapping(&)
          mappings[:xml] ||= Lutaml::Xml::Mapping.new
          mappings[:xml].instance_eval(&)

          if mappings[:xml].respond_to?(:finalize)
            mappings[:xml].finalize(self)
          end

          check_sort_configs!
        end
      end
    end
  end
end
