# frozen_string_literal: true

require "cgi"

module Lutaml
  module Lml
    module Lsp
      # Conversions between the parser's 1-based positions and LSP's
      # 0-based positions, plus diagnostic records.
      module Conversions
        module_function

        def position(source_position)
          return { line: 0, character: 0 } unless source_position

          {
            line: source_position.line.to_i - 1,
            character: source_position.column.to_i - 1,
          }
        end

        def range(source_position)
          start = position(source_position)
          {
            start: start,
            end: {
              line: start[:line],
              character: start[:character] + source_position.length.to_i,
            },
          }
        end

        def diagnostic(record)
          {
            range: diagnostic_range(record),
            severity: severity(record.severity),
            code: record.code,
            source: "lutaml-lml",
            message: diagnostic_message(record),
          }
        end

        def diagnostic_range(record)
          line = [record.line.to_i - 1, 0].max
          character = [record.column.to_i - 1, 0].max
          length = record.length.to_i
          length = 1 if length.zero?
          {
            start: { line: line, character: character },
            end: { line: line, character: character + length },
          }
        end

        def diagnostic_message(record)
          return record.message.to_s if record.remedy.to_s.empty?

          "#{record.message}\nremedy: #{record.remedy}"
        end

        def severity(value)
          value.to_s == "warning" ? 2 : 1
        end

        # file:///path → local path. Windows drive paths lose the leading
        # slash (file:///C:/x → C:/x).
        def uri_to_path(uri)
          path = uri.to_s.sub(%r{\Afile://}, "")
          path = CGI.unescape(path)
          path.sub(%r{\A/([A-Za-z]:/)}, '\1')
        end

        def path_to_uri(path)
          "file://#{CGI.escape(path.to_s).gsub('+', '%20')}"
        end
      end
    end
  end
end
