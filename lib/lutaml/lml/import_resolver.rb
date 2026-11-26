# frozen_string_literal: true

require "set"

module Lutaml
  module Lml
    # Resolves `view import` paths and merges the imported entities.
    class ImportResolver
      def initialize(base_dir)
        @base_dir = base_dir
      end

      # Returns [entity_index, associations] where entity_index maps
      # entity name → entity. ViewResolver consumes the index without
      # rebuilding it.
      def resolve(document)
        @failures = []
        entity_index = {}
        associations = []
        visited = Set.new

        document.view_imports.each do |import|
          resolve_import(import.path, entity_index, associations, visited, @base_dir)
        end

        collect_local_entities(document, entity_index, associations)

        if @failures.any?
          raise ImportError.new(
            @failures.join("\n"),
            diagnostic: Diagnostic.build(
              'contract/LML-C05',
              message: @failures.first,
              file: document.source_path,
            ),
          )
        end

        [entity_index, associations]
      end

      private

      def resolve_import(path, entity_index, associations, visited, base_dir)
        abs_pattern = File.expand_path(path, base_dir)
        files = Dir.glob(abs_pattern)
        @failures << "import matched no files: #{path} (resolved to #{abs_pattern})" if files.empty?

        files.each do |file_path|
          next if visited.include?(file_path)

          visited.add(file_path)

          doc = parse_file(file_path)
          collect_local_entities(doc, entity_index, associations)

          doc.view_imports.each do |import|
            resolve_import(import.path, entity_index, associations, visited, File.dirname(file_path))
          end
        end
      end

      # The grammar root accepts every file shape (diagram, view,
      # models block, bare definitions) — no content sniffing needed.
      def parse_file(file_path)
        File.open(file_path) { |file| Pipeline.call(file) }
      rescue Errno::ENOENT, Errno::EACCES => e
        @failures << "cannot read import #{file_path}: #{e.message}"
        Document.new
      end

      def collect_local_entities(doc, entity_index, associations)
        EntityTypes.all.each do |type|
          merge_entities(doc.public_send(type.entity_type), entity_index)
        end
        associations.concat(doc.associations.to_a)
      end

      # Re-importing the same entity through two paths is legitimate
      # (dedup silently); the same name with different content is a
      # conflict that must not resolve to a silently wrong diagram.
      def merge_entities(collection, entity_index)
        collection.each do |entity|
          next if entity.name.nil?

          existing = entity_index[entity.name]
          if existing.nil?
            entity_index[entity.name] = entity
          elsif existing.to_hash != entity.to_hash
            @failures << "entity '#{entity.name}' is defined differently in two imports"
          end
        end
      end
    end
  end
end
