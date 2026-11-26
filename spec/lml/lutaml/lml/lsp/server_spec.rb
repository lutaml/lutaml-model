# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"
require "stringio"
require "json"
require "open3"
require "rbconfig"
require "lutaml/lml/lsp"

RSpec.describe "LSP server" do
  def frame(message)
    body = JSON.generate(message)
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def parse_frames(raw)
    scanner = StringIO.new(raw)
    messages = []
    loop do
      headers = {}
      while (line = scanner.gets)
        line = line.chomp
        break if line.empty?

        key, value = line.split(": ", 2)
        headers[key.to_s.downcase] = value
      end
      break unless headers["content-length"]

      messages << JSON.parse(scanner.read(headers["content-length"].to_i))
    end
    messages
  end

  def run_session(messages)
    input = StringIO.new
    messages.each { |message| input.write(frame(message)) }
    input.rewind
    output = StringIO.new
    server = Lutaml::Lml::Lsp::Server.new(
      transport: Lutaml::Lml::Lsp::Transport.new(input: input, output: output),
    )
    code = server.run
    [parse_frames(output.string), code]
  end

  def initialize_message(id = 1)
    { "jsonrpc" => "2.0", "id" => id, "method" => "initialize", "params" => {} }
  end

  def open_message(uri, text)
    {
      "jsonrpc" => "2.0", "method" => "textDocument/didOpen",
      "params" => {
        "textDocument" => {
          "uri" => uri, "languageId" => "lml", "version" => 1, "text" => text
        },
      }
    }
  end

  def request(id, method, params)
    { "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params }
  end

  let(:uri) { "file:///tmp/lsp-model.lml" }

  let(:source) do
    <<~LML
      class Studio {
        attribute glaze, Glaze
      }

      enum Glaze {
        value "matte"
      }
    LML
  end

  def response(messages, id)
    messages.find { |message| message["id"] == id }
  end

  def published(messages)
    messages.find { |message| message["method"] == "textDocument/publishDiagnostics" }
  end

  it "advertises the server capabilities" do
    messages, = run_session([initialize_message])
    capabilities = response(messages, 1)["result"]["capabilities"]

    expect(capabilities["textDocumentSync"]).to eq(1)
    expect(capabilities["documentSymbolProvider"]).to be(true)
    expect(capabilities["hoverProvider"]).to be(true)
    expect(capabilities["documentFormattingProvider"]).to be(true)
    expect(capabilities["diagnosticProvider"]).to include("interFileDependencies" => false)
  end

  it "publishes diagnostics from the parsed document" do
    text = "class Tile { }\nclass Tile { }\n"
    messages, = run_session([initialize_message, open_message(uri, text)])
    diagnostics = published(messages)["params"]["diagnostics"]

    expect(diagnostics.map { |item| item["code"] }).to eq(["validation/LML-V01"])
    expect(diagnostics.first["range"]["start"]).to eq("line" => 0, "character" => 6)
    expect(diagnostics.first["message"]).to include("remedy:")
  end

  it "answers a pull diagnostic request" do
    messages, = run_session([
                              initialize_message, open_message(uri, source),
                              request(2, "textDocument/diagnostic", { "textDocument" => { "uri" => uri } })
                            ])
    report = response(messages, 2)["result"]

    expect(report["kind"]).to eq("full")
    expect(report["items"]).to eq([])
  end

  it "lists document symbols" do
    messages, = run_session([
                              initialize_message, open_message(uri, source),
                              request(2, "textDocument/documentSymbol", { "textDocument" => { "uri" => uri } })
                            ])
    symbols = response(messages, 2)["result"]
    names = symbols.map { |symbol| symbol["name"] }

    expect(names).to include("Studio", "glaze", "Glaze")
    expect(symbols.find { |symbol| symbol["name"] == "Studio" }["kind"]).to eq(5)
    expect(symbols.find { |symbol| symbol["name"] == "matte" }["kind"]).to eq(22)
  end

  it "hovers an attribute with its type and value semantics" do
    messages, = run_session([
                              initialize_message, open_message(uri, source),
                              request(2, "textDocument/hover",
                                      { "textDocument" => { "uri" => uri },
                                        "position" => { "line" => 1, "character" => 12 } })
                            ])
    hover = response(messages, 2)["result"]

    expect(hover["contents"]["value"]).to include("glaze")
    expect(hover["contents"]["value"]).to include("Glaze")
  end

  it "goes to the definition of a type" do
    messages, = run_session([
                              initialize_message, open_message(uri, source),
                              request(2, "textDocument/definition",
                                      { "textDocument" => { "uri" => uri },
                                        "position" => { "line" => 1, "character" => 24 } })
                            ])
    locations = response(messages, 2)["result"]

    expect(locations.first["range"]["start"]["line"]).to eq(4)
  end

  it "finds references including the declaration" do
    messages, = run_session([
                              initialize_message, open_message(uri, source),
                              request(2, "textDocument/references",
                                      { "textDocument" => { "uri" => uri },
                                        "position" => { "line" => 4, "character" => 7 },
                                        "context" => { "includeDeclaration" => true } })
                            ])
    locations = response(messages, 2)["result"]
    lines = locations.map { |location| location["range"]["start"]["line"] }

    expect(lines).to include(1, 4)
  end

  it "completes grammar keywords and model names" do
    messages, = run_session([
                              initialize_message, open_message(uri, source),
                              request(2, "textDocument/completion",
                                      { "textDocument" => { "uri" => uri },
                                        "position" => { "line" => 1, "character" => 2 } })
                            ])
    labels = response(messages, 2)["result"]["items"].map { |item| item["label"] }

    expect(labels).to include("class", "enum", "attribute", "value")
    expect(labels).to include("Studio", "glaze")
  end

  it "returns a canonical formatting edit" do
    messages, = run_session([
                              initialize_message, open_message(uri, "class B { }\nclass A { }\n"),
                              request(2, "textDocument/formatting",
                                      { "textDocument" => { "uri" => uri }, "options" => {} })
                            ])
    edits = response(messages, 2)["result"]

    expect(edits.one?).to be(true)
    expect(edits.first["newText"]).to eq("class B {\n}\n\nclass A {\n}\n")
  end

  it "survives an unparseable document" do
    messages, = run_session([
                              initialize_message,
                              open_message(uri, "class Broken {\n"),
                              request(2, "textDocument/documentSymbol", { "textDocument" => { "uri" => uri } }),
                              request(3, "textDocument/formatting",
                                      { "textDocument" => { "uri" => uri }, "options" => {} }),
                              { "jsonrpc" => "2.0", "id" => 4, "method" => "shutdown", "params" => {} },
                              { "jsonrpc" => "2.0", "method" => "exit", "params" => {} },
                            ])

    expect(published(messages)["params"]["diagnostics"].first["code"]).to eq("parse/LML-001")
    expect(response(messages, 2)["result"]).to eq([])
    expect(response(messages, 3)["result"]).to be_nil
    expect(messages.size).to be >= 4
  end

  it "opens every RS 3001 corpus fixture without crashing" do
    Dir[fixtures_path("rs3001/*.lml")].each_with_index do |path, index|
      text = File.read(path)
      fixture_uri = Lutaml::Lml::Lsp::Conversions.path_to_uri(path)
      messages, = run_session([
                                initialize_message(1),
                                open_message(fixture_uri, text),
                                request(2, "textDocument/documentSymbol",
                                        { "textDocument" => { "uri" => fixture_uri } }),
                                request(3, "textDocument/diagnostic",
                                        { "textDocument" => { "uri" => fixture_uri } }),
                              ])

      expect(response(messages, 2)["result"]).to be_an(Array), "fixture #{index}: #{path}"
      expect(response(messages, 3)["result"]["kind"]).to eq("full")
    end
  end

  it "exits zero after a clean shutdown" do
    messages, code = run_session([
                                   initialize_message,
                                   { "jsonrpc" => "2.0", "id" => 2, "method" => "shutdown", "params" => {} },
                                   { "jsonrpc" => "2.0", "method" => "exit", "params" => {} },
                                 ])

    expect(code).to eq(0)
    expect(response(messages, 2)["result"]).to be_nil
  end

  it "runs as a stdio executable" do
    root = File.expand_path("../../../../..", __dir__)
    frames = [
      initialize_message,
      { "jsonrpc" => "2.0", "id" => 2, "method" => "shutdown", "params" => {} },
      { "jsonrpc" => "2.0", "method" => "exit", "params" => {} },
    ].map { |message| frame(message) }.join

    stdout, _stderr, status = Open3.capture3(
      { "RUBYLIB" => File.join(root, "lib") },
      RbConfig.ruby, File.join(root, "exe", "lutaml-lml-lsp"),
      stdin_data: frames
    )

    expect(status.exitstatus).to eq(0)
    expect(parse_frames(stdout).first["id"]).to eq(1)
  end

  describe "transport" do
    it "round-trips a framed message" do
      input = StringIO.new(frame({ "jsonrpc" => "2.0", "id" => 1, "result" => {} }))
      output = StringIO.new
      transport = Lutaml::Lml::Lsp::Transport.new(input: input, output: output)

      expect(transport.read_message).to include("id" => 1)
      expect(transport.read_message).to be_nil

      transport.write_message(jsonrpc: "2.0", id: 1, result: nil)
      expect(output.string).to start_with("Content-Length: ")
      expect(output.string).to include('"result":null')
    end
  end

  describe "keywords" do
    it "reads the language keywords from the compiled grammar artifact" do
      keywords = Lutaml::Lml::Lsp::Keywords.all

      expect(keywords).to include("class", "enum", "attribute", "value", "instance")
      expect(keywords).to eq(keywords.sort)
    end
  end
end
