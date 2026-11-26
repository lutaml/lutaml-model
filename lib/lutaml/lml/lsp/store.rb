# frozen_string_literal: true

module Lutaml
  module Lml
    module Lsp
      # The open-document store. Every change reparses the full text
      # (full-document sync) and recomputes diagnostics.
      class Store
        Entry = Struct.new(:uri, :text, :version, :model, :diagnostics,
                           keyword_init: true)

        def initialize
          @entries = {}
        end

        def open(uri:, text:, version: nil)
          entry = Entry.new(uri: uri, text: text, version: version)
          parse(entry)
          @entries[uri] = entry
        end

        def change(uri:, text:, version: nil)
          entry = @entries[uri]
          return nil unless entry

          entry.text = text
          entry.version = version
          parse(entry)
          entry
        end

        def close(uri)
          @entries.delete(uri)
        end

        def [](uri)
          @entries[uri]
        end

        private

        def parse(entry)
          path = Conversions.uri_to_path(entry.uri)
          entry.model = Lutaml::Lml.parse_document(entry.text)
          entry.model.source_path = path
          entry.diagnostics = Validator.diagnostics(entry.model)
        rescue Lutaml::Lml::Error => e
          entry.model = nil
          entry.diagnostics = [diagnostic_for(e, path)]
        end

        def diagnostic_for(error, path)
          record = error.diagnostic
          return record if record&.file

          Diagnostic.build(
            record&.code || 'parse/LML-001',
            message: record&.message || error.message.lines.first.to_s.strip,
            file: path,
            line: record&.line,
            column: record&.column,
            length: record&.length,
          )
        end
      end
    end
  end
end
