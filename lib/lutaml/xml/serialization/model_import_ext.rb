# frozen_string_literal: true

module Lutaml
  module Xml
    module Serialization
      # XML-specific overrides for ModelImport methods.
      #
      # Prepended into Serialize::ModelImport when XML is loaded.
      # Provides XML-specific implementations for:
      # - root? (checks XML mapping for root element)
      # - ensure_format_mapping_imports! (resolves XML mapping imports)
      # - collection_with_conflicting_sort? (checks XML ordered? vs sort_by)
      module ModelImportExt
        # Check if register has an XML root mapping
        #
        # @param register [Symbol, nil] The register to check
        # @return [Boolean] True if the model has an XML root mapping
        def root?(register = nil)
          mappings_for(:xml, register)&.root? || false
        end

        # Resolve XML mapping imports
        #
        # @param register [Symbol, nil] The register context
        def ensure_format_mapping_imports!(register = nil)
          mappings[:xml]&.ensure_mappings_imported!(register)
        end

        # Check for conflicting sort configurations with XML ordered mapping
        #
        # @return [Boolean] True if there's a conflict
        def collection_with_conflicting_sort?
          self <= Lutaml::Model::Collection &&
            @mappings[:xml]&.ordered? &&
            !!@sort_by_field
        end
      end
    end
  end
end
