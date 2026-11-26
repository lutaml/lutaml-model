# frozen_string_literal: true

module Lutaml
  module Lml
    module Lsp
      # The stdio JSON-RPC server. One message at a time; every document
      # change reparses the full text. Errors are contained per message
      # so a broken document never crashes the server.
      class Server
        WORD = /[A-Za-z0-9_:.-]/

        CAPABILITIES = {
          textDocumentSync: 1,
          documentSymbolProvider: true,
          definitionProvider: true,
          referencesProvider: true,
          hoverProvider: true,
          completionProvider: { triggerCharacters: [' ', ':'] },
          documentFormattingProvider: true,
          diagnosticProvider: {
            interFileDependencies: false,
            workspaceDiagnostics: false,
          },
        }.freeze

        def initialize(transport: Transport.new, store: Store.new)
          @transport = transport
          @store = store
          @shutdown = false
          @stopped = false
        end

        # Runs the message loop; returns the process exit code.
        def run
          until @stopped
            message = @transport.read_message
            break if message.nil?

            dispatch(message)
          end
          @shutdown ? 0 : 1
        end

        private

        def dispatch(message)
          id = message['id']
          method = message['method']
          params = message['params'] || {}

          case method
          when 'initialize' then respond(id, initialize_result)
          when 'initialized' then nil
          when 'shutdown'
            @shutdown = true
            respond(id, nil)
          when 'exit'
            @stopped = true
          when 'textDocument/didOpen' then did_open(params)
          when 'textDocument/didChange' then did_change(params)
          when 'textDocument/didClose' then did_close(params)
          when 'textDocument/diagnostic' then respond(id, diagnostic_report(params))
          when 'textDocument/documentSymbol' then respond(id, document_symbols(params))
          when 'textDocument/definition' then respond(id, definition(params))
          when 'textDocument/references' then respond(id, references(params))
          when 'textDocument/hover' then respond(id, hover(params))
          when 'textDocument/completion' then respond(id, completion(params))
          when 'textDocument/formatting' then respond(id, formatting(params))
          else
            respond_error(id, -32_601, "Method not found: #{method}") unless id.nil?
          end
        rescue StandardError => e
          respond_error(id, -32_603, e.message) unless id.nil?
        end

        def initialize_result
          {
            capabilities: CAPABILITIES,
            serverInfo: { name: 'lutaml-lml-lsp', version: Lutaml::Lml::VERSION },
          }
        end

        # ---- documents ----

        def did_open(params)
          document = params['textDocument'] || {}
          entry = @store.open(
            uri: document['uri'], text: document['text'].to_s,
            version: document['version']
          )
          publish(entry)
        end

        def did_change(params)
          document = params['textDocument'] || {}
          changes = params['contentChanges'] || []
          text = changes.last.is_a?(Hash) ? changes.last['text'].to_s : ''
          entry = @store.change(
            uri: document['uri'], text: text, version: document['version'],
          )
          publish(entry) if entry
        end

        def did_close(params)
          document = params['textDocument'] || {}
          uri = document['uri']
          @store.close(uri)
          @transport.write_message(
            jsonrpc: '2.0', method: 'textDocument/publishDiagnostics',
            params: { uri: uri, diagnostics: [] }
          )
        end

        def publish(entry)
          @transport.write_message(
            jsonrpc: '2.0', method: 'textDocument/publishDiagnostics',
            params: {
              uri: entry.uri,
              diagnostics: entry.diagnostics.map { |record| Conversions.diagnostic(record) },
            }
          )
        end

        def diagnostic_report(params)
          entry = entry_for(params)
          return { kind: 'full', items: [] } unless entry

          {
            kind: 'full',
            items: entry.diagnostics.map { |record| Conversions.diagnostic(record) },
          }
        end

        # ---- symbols ----

        def document_symbols(params)
          entry = entry_for(params)
          return [] unless entry&.model

          SymbolIndex.new(entry.model).entries.map do |symbol|
            {
              name: symbol.name,
              kind: SymbolIndex::KINDS.fetch(symbol.kind),
              location: location(entry.uri, symbol.position),
              containerName: symbol.container,
            }.compact
          end
        end

        def definition(params)
          entry = entry_for(params)
          return nil unless entry&.model

          token = token_at(entry, params['position'])
          return nil if token.empty?

          index = SymbolIndex.new(entry.model)
          locations = resolve(index, token).map { |symbol| location(entry.uri, symbol.position) }
          locations.empty? ? nil : locations
        end

        def references(params)
          entry = entry_for(params)
          return [] unless entry&.model

          token = token_at(entry, params['position'])
          return [] if token.empty?

          index = SymbolIndex.new(entry.model)
          symbols = index.uses(token)
          symbols += index.definitions(token) if params.dig('context', 'includeDeclaration')

          symbols.map { |symbol| location(entry.uri, symbol.position) }.uniq
        end

        def hover(params)
          entry = entry_for(params)
          return nil unless entry&.model

          position = params['position']
          token = token_at(entry, position)
          return nil if token.empty?

          symbol = resolve(SymbolIndex.new(entry.model), token).first
          return nil unless symbol

          {
            contents: { kind: 'markdown', value: hover_markdown(symbol) },
            range: token_range(entry, position, token),
          }
        end

        def hover_markdown(symbol)
          case symbol.kind
          when :class then class_markdown(symbol.record)
          when :enum then enum_markdown(symbol.record)
          when :field then field_markdown(symbol.record)
          when :instance then instance_markdown(symbol.record)
          when :enum_member then enum_member_markdown(symbol.record)
          else "**#{symbol.name}**"
          end
        end

        def class_markdown(klass)
          text = "```lml\nclass #{klass.name}"
          text << " < #{klass.parent_class}" unless klass.parent_class.to_s.empty?
          text << "\n```"
          append_definition(text, klass.definition)
        end

        def enum_markdown(enum)
          members = Array(enum.attributes).map { |member| member.name.to_s }
          text = "```lml\nenum #{enum.name}\n```"
          text << "\n\nMembers: #{members.join(', ')}" unless members.empty?
          append_definition(text, enum.definition)
        end

        def field_markdown(attribute)
          label = attribute.name.to_s
          type = attribute.type.to_s
          text = "```lml\n#{label}"
          text << ": #{type}" unless type.empty?
          cardinality = attribute.cardinality
          if cardinality
            max = cardinality.max.to_s
            text << " [#{cardinality.min}#{"..#{max}" unless max.empty?}]"
          end
          text << "\n```"
          text << "\n\ndefault: `#{attribute.default}`" if attribute.default
          text << "\npattern: `#{attribute.pattern}`" if attribute.pattern
          text << "\nvalues: #{attribute.value_set.join(', ')}" if Array(attribute.value_set).any?
          append_definition(text, attribute.definition)
          text << "\n\n`null`, `\"\"`, and an unassigned attribute are distinct." if type == 'String'
          text
        end

        def instance_markdown(instance)
          label = instance.type.to_s.empty? ? instance.name.to_s : instance.type.to_s
          text = "```lml\ninstance #{label}\n```"
          text << "\n\n#{Array(instance.attributes).size} assignment(s)"
          text
        end

        def enum_member_markdown(member)
          text = "**value #{member.name}**"
          description = Array(member.attributes).find { |attribute| attribute.name == 'description' }
          text << "\n\n#{description.type}" if description
          text
        end

        def append_definition(text, definition)
          value = definition.to_s
          text << "\n\n#{value}" unless value.empty?
          text
        end

        # ---- completion ----

        def completion(params)
          entry = entry_for(params)
          prefix = completion_prefix(entry, params['position'])
          items = completion_items(entry)
          items = items.select { |item| item[:label].start_with?(prefix) } unless prefix.empty?

          { isIncomplete: false, items: items }
        end

        def completion_items(entry)
          items = Keywords.all.map do |keyword|
            { label: keyword, kind: 14, detail: 'LML keyword' }
          end
          return dedupe(items) unless entry&.model

          index = SymbolIndex.new(entry.model)
          index.entity_entries.each do |symbol|
            items << {
              label: symbol.name,
              kind: SymbolIndex::KINDS.fetch(symbol.kind),
              detail: symbol.detail || symbol.container,
            }
          end
          index.attribute_entries.each do |symbol|
            items << { label: symbol.name, kind: 8, detail: symbol.detail }
          end
          dedupe(items)
        end

        def dedupe(items)
          seen = {}
          items.each_with_object([]) do |item, result|
            next if seen[item[:label]]

            seen[item[:label]] = true
            result << item.compact
          end
        end

        # ---- formatting ----

        def formatting(params)
          entry = entry_for(params)
          return nil unless entry&.model

          canonical = Lutaml::Formatter::Canonical.new(entry.model).render
          return [] if canonical == entry.text

          [{ range: full_range(entry.text), newText: canonical }]
        end

        def full_range(text)
          {
            start: { line: 0, character: 0 },
            end: { line: text.lines.length, character: 0 },
          }
        end

        # ---- helpers ----

        def entry_for(params)
          document = params['textDocument'] || {}
          @store[document['uri']]
        end

        def location(uri, position)
          { uri: uri, range: Conversions.range(position) }
        end

        def resolve(index, token)
          symbols = index.definitions(token)
          return symbols unless symbols.empty?

          token.split('.').flat_map { |segment| index.definitions(segment) }.uniq
        end

        def token_at(entry, position)
          line = entry.text.lines[position['line'].to_i].to_s
          index = [position['character'].to_i, line.length].min
          start = index
          start -= 1 while start.positive? && line[start - 1].match?(WORD)
          finish = index
          finish += 1 while finish < line.length && line[finish].match?(WORD)
          line[start...finish].to_s
        end

        def token_range(entry, position, token)
          line = entry.text.lines[position['line'].to_i].to_s
          finish = [position['character'].to_i, line.length].min
          start = [finish - token.length, 0].max
          {
            start: { line: position['line'].to_i, character: start },
            end: { line: position['line'].to_i, character: start + token.length },
          }
        end

        def completion_prefix(entry, position)
          return '' unless entry

          line = entry.text.lines[position['line'].to_i].to_s
          before = line[0...[position['character'].to_i, line.length].min].to_s
          before[/[A-Za-z0-9_]*\z/].to_s
        end

        def respond(id, result)
          return if id.nil?

          @transport.write_message(jsonrpc: '2.0', id: id, result: result)
        end

        def respond_error(id, code, message)
          @transport.write_message(
            jsonrpc: '2.0', id: id,
            error: { code: code, message: message }
          )
        end
      end
    end
  end
end
