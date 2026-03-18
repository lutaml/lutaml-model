# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Resolves schema names for serialization
        # Uses the basename directly as provided by the XSD bundler
        # The bundler has already renamed files with namespace prefixes to ensure uniqueness
        # This class provides clean separation of naming concerns from serialization logic
        class SchemaNameResolver
          # Initialize with namespace mappings from repository
          # @param namespace_mappings [Array<NamespaceMapping>] Prefix-to-URI mappings (not used in current implementation)
          def initialize(namespace_mappings)
            @namespace_mappings = namespace_mappings || []
          end

          # Resolve schema name for serialization
          # Simply returns the basename as-is, since the XSD bundler has already
          # renamed files with namespace prefixes to make them unique and semantic
          # @param basename [String] Base filename (e.g., "gco_basicTypes", "basicTypes")
          # @param schema [Schema] Schema object (not used in current implementation)
          # @return [String] The basename to use for serialization
          def resolve_name(basename, _schema)
            # Use basename directly - the bundler has already made it unique
            basename
          end
        end
      end
    end
  end
end
