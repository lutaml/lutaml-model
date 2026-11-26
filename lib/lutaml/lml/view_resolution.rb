# frozen_string_literal: true

module Lutaml
  module Lml
    # Post-parse step: expand view imports, apply show/hide filters,
    # rebuild the document's entity collections, and enrich association
    # labels. Import expansion runs only when the document declares
    # view imports; label enrichment always runs.
    class ViewResolution
      def self.call(document, base_dir)
        document = resolve_imports(document, base_dir) if document.view_imports.any?
        AssociationLabelResolver.new.enrich(document)
      end

      def self.resolve_imports(document, base_dir)
        entity_index, associations = ImportResolver.new(base_dir).resolve(document)
        entities, associations = ViewResolver.new.resolve(document, entity_index, associations)
        rebuild_document(document, entities, associations)
      end

      def self.rebuild_document(document, entities, associations)
        grouped = entities.group_by { |e| e.class.entity_type }

        EntityTypes.symbols.each do |symbol|
          document.public_send("#{symbol}=", grouped[symbol] || [])
        end
        document.associations = associations
        document
      end
    end
  end
end
