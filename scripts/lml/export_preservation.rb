# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "lutaml/model"
require "json"
require "yaml"
require "digest"
require "rexml/document"
require "optparse"
require "fileutils"

# Ruby-authored preservation package; no dependency on another corpus index.
module LmlPreservation
  GENERATION = "preservation-v1"
  SOURCE_REVISION = "8a8ef040963b7965388b01b58af33af2b0995f91"
  XML_PROFILE = "expanded-names-text-v1"

  class Namespace < Lutaml::Xml::W3c::XmlNamespace
    uri "urn:lml:preservation"
    prefix_default "p"
    element_form_default :qualified
  end

  class Namespaces < Lutaml::Model::Serializable
    attribute :qualified, :string
    attribute :plain, :string
    xml do
      root "record"
      namespace Namespace
      map_element "qualified", to: :qualified
      map_element "plain", to: :plain, form: :unqualified
    end
  end

  class Mixed < Lutaml::Model::Serializable
    attribute :text, :string, collection: true
    attribute :em, :string, collection: true
    xml do
      root "mixed"
      mixed_content
      map_content to: :text
      map_element "em", to: :em
    end
  end

  class Ordered < Lutaml::Model::Serializable
    attribute :a, :string, collection: true
    attribute :b, :string, collection: true
    xml do
      root "ordered", ordered: true
      map_element "a", to: :a
      map_element "b", to: :b
    end
  end

  class Cdata < Lutaml::Model::Serializable
    attribute :text, :string
    xml do
      root "cdata"
      map_content to: :text, cdata: true
    end
  end

  class States < Lutaml::Model::Serializable
    attribute :value, :string
    attribute :fallback, :string, default: "default"
    attribute :items, :string, collection: true, initialize_empty: true
    json do
      map "value", to: :value, render_nil: true, render_empty: true
      map "fallback", to: :fallback, render_default: true
      map "items", to: :items, render_empty: true
    end
  end

  class Bounded < Lutaml::Model::Serializable
    attribute :items, :string, collection: 1..2
    json { map "items", to: :items }
  end

  class TypedEnum < Lutaml::Model::Serializable
    attribute :number, :integer, values: [1, 2]
    attribute :flag, :boolean, values: [true, false]
    json do
      map "number", to: :number
      map "flag", to: :flag
    end
  end

  class Source < Lutaml::Model::Serializable
    attribute :name, :string
    json { map "name", to: :name }
  end

  Lutaml::Model::GlobalRegister.register(Lutaml::Model::Register.new(:oracle))

  class Imported < Lutaml::Model::Serializable
    import_model Source, :oracle
  end

  module_function

  def canonical(value)
    case value
    when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def json(value)
    JSON.generate(canonical(value))
  end

  def digest(bytes)
    "sha256:#{Digest::SHA256.hexdigest(bytes)}"
  end

  def inputs
    namespace_input = '<p:record xmlns:p="urn:lml:preservation"><p:qualified>Q</p:qualified><plain>P</plain></p:record>'
    mixed_input = "<mixed>before<em>one</em>between<em>two</em>after</mixed>"
    [
      ["namespace-tree", Namespaces, "xml", "xml_tree", namespace_input],
      ["namespace-bytes", Namespaces, "xml", "bytes", namespace_input],
      ["mixed-order-tree", Mixed, "xml", "xml_tree", mixed_input],
      ["mixed-order-bytes", Mixed, "xml", "bytes", mixed_input],
      ["ordered-tree", Ordered, "xml", "xml_tree", "<ordered><b>one</b><a>two</a><b>three</b></ordered>"],
      ["ordered-bytes", Ordered, "xml", "bytes", "<ordered><b>one</b><a>two</a><b>three</b></ordered>"],
      ["cdata-bytes", Cdata, "xml", "bytes", "<cdata><![CDATA[a < b & c]]></cdata>"],
      ["state-absent", States, "json", "data", "{}"],
      ["state-null", States, "json", "data", '{"value":null,"fallback":null}'],
      ["state-empty", States, "json", "data", '{"value":"","items":[]}'],
      ["state-explicit-default", States, "json", "data", '{"fallback":"default"}'],
      ["cardinality-valid", Bounded, "json", "data", '{"items":["one","two"]}'],
      ["cardinality-invalid", Bounded, "json", "data", '{"items":["one","two","three"]}'],
      ["cardinality-missing", Bounded, "json", "data", '{"items":[]}'],
      ["typed-enum-valid", TypedEnum, "json", "data", '{"number":2,"flag":false}'],
      ["typed-enum-invalid", TypedEnum, "json", "data", '{"number":3,"flag":true}'],
      ["imported-context", Imported, "json", "data", '{"name":"contextual"}'],
    ]
  end

  def model_id(klass)
    "#{klass.name}@#{klass == Imported ? 'oracle' : 'default'}"
  end

  def neutral(value)
    case value
    when Lutaml::Model::UninitializedClass then { "state" => "absent" }
    when Integer then value.to_s
    when Array then value.map { |item| neutral(item) }
    else value
    end
  end

  def register_for(klass)
    return :default unless klass == Imported

    # GlobalContext.reset! removes contexts while GlobalRegister keeps registers.
    if !Lutaml::Model::GlobalContext.context(:oracle) || !Lutaml::Model::GlobalRegister.lookup(:oracle)
      Lutaml::Model::GlobalRegister.register(Lutaml::Model::Register.new(:oracle))
    end
    :oracle
  end

  def attributes_for(klass)
    klass.attributes(register_for(klass))
  end

  def normalized(record, klass, input, format)
    data = attributes_for(klass).keys.to_h { |name| [name.to_s, neutral(record.public_send(name))] }
    if klass == States
      authored = JSON.parse(input)
      data = data.to_h do |name, value|
        state = if authored.key?(name)
                  "present"
                elsif name == "fallback"
                  "default"
                elsif name == "items"
                  "initialized_empty"
                else
                  "absent"
                end
        [name, { "state" => state, "value" => value }]
      end
    elsif [Mixed, Ordered].include?(klass) && format == "xml"
      # Preserve real per-instance order through the Ruby serialized tree, and
      # expose portable member/index tokens alongside the parsed member values.
      counters = Hash.new(0)
      data["__lml_content"] = record.element_order.map do |node|
        member = node.element? ? node.name : "text"
        kind = node.element? ? "element" : node.node_type.to_s
        token = { "kind" => kind, "attribute" => member, "index" => counters[member] }
        counters[member] += 1
        token
      end
    end
    data
  end

  def execute(entry, klass)
    format = entry.fetch("format")
    register = register_for(klass)
    Lutaml::Model::Config.with_adapter(xml: :nokogiri, json: :standard) do
      record = klass.public_send("from_#{format}", entry.fetch("input"), register: register)
      errors = record.validate(register: register)
      if errors.any?
        return invalid_result(klass, format, errors)
      end

      { "data" => normalized(record, klass, entry.fetch("input"), format),
        "output" => record.public_send("to_#{format}", register: register) }
    end
  rescue Lutaml::Model::CollectionCountOutOfRangeError, Lutaml::Model::InvalidValueError => e
    invalid_result(klass, format, [e])
  end

  def invalid_result(klass, format, errors)
    { "error" => { "reason" => "invalid_document", "model_id" => model_id(klass),
                   "format" => format, "location" => "/input",
                   "ruby_errors" => errors.map { |error| error.class.name } } }
  end

  def cases
    inputs.map do |id, klass, format, comparison, input|
      entry = { "id" => id, "model_id" => model_id(klass), "lml_checksum" => checksum,
                "format" => format, "input" => input, "comparison" => comparison }
      result = execute(entry, klass)
      entry.merge("expected_data" => result["data"], "expected_output" => result["output"],
                  "expected_error" => result["error"])
    end
  end

  def schema
    models = inputs.map { |entry| entry[1] }.uniq.to_h do |klass|
      fields = attributes_for(klass).map do |name, attribute|
        builtin = if klass == TypedEnum && name == :number
                    "integer"
                  elsif klass == TypedEnum && name == :flag
                    "boolean"
                  else
                    "string"
                  end
        collection = if [Mixed, Ordered, Bounded].include?(klass) || name == :items
                       { "min" => klass == Bounded ? 1 : 0, "max" => klass == Bounded ? 2 : nil }
                     else
                       false
                     end
        field = { "name" => name.to_s, "type" => { "kind" => "builtin", "name" => builtin },
                  "required" => false, "collection" => collection,
                  "default" => name == :fallback ? { "present" => true, "value" => "default" } : { "present" => false },
                  "initialize_empty" => klass == States && name == :items }
        field["values"] = attribute.options[:values] if klass == TypedEnum
        field
      end
      document = { "lml" => 2, "model" => klass.name, "register" => klass == Imported ? "oracle" : "default",
                   "attributes" => fields, "mappings" => schema_mappings(klass, fields) }
      document["ordered_content"] = { "member" => "__lml_content", "version" => 1 } if [Mixed, Ordered].include?(klass)
      [model_id(klass), document]
    end
    { "lml_bundle" => 1, "roots" => models.keys.sort, "models" => models,
      "value_types" => {}, "capabilities" => %w[json xml],
      "provenance" => { "source_revision" => SOURCE_REVISION } }
  end

  def schema_mappings(klass, fields)
    if [States, Bounded, TypedEnum, Imported].include?(klass)
      return { "json" => { "rules" => fields.map do |field|
        rule = { "key" => [field.fetch("name")], "to" => field.fetch("name") }
        if klass == States
          rule["render"] = case field.fetch("name")
                           when "value" then { "nil" => true, "empty" => true, "default" => false }
                           when "fallback" then { "default" => true }
                           else { "empty" => true }
                           end
        end
        rule
      end } }
    end
    root = { Namespaces => "record", Mixed => "mixed", Ordered => "ordered", Cdata => "cdata" }.fetch(klass)
    rules = fields.map do |field|
      name = field.fetch("name")
      content = name == "text"
      namespace = if klass == Namespaces
                    name == "plain" ? { "mode" => "unqualified" } : { "mode" => "inherit" }
                  else
                    { "mode" => "inherit" }
                  end
      rule = { "kind" => content ? "content" : "element", "to" => name, "namespace" => namespace }
      rule["name"] = [name] unless content
      rule["cdata"] = true if klass == Cdata
      rule
    end
    namespace = klass == Namespaces ? { "mode" => "uri", "uri" => "urn:lml:preservation", "prefix" => "p" } : { "mode" => "inherit" }
    { "xml" => { "root" => { "element" => root }, "namespace" => namespace, "rules" => rules } }
  end

  def checksum
    digest(json(schema.except("provenance")))
  end

  def source_expectations
    %w[mixed_content_spec.rb cdata_spec.rb collection_spec.rb register_spec.rb].map do |name|
      path = "spec/lutaml/model/#{name}"
      # Pin repository source text independent of Windows CRLF checkout conversion.
      { "path" => path, "sha256" => digest(File.binread(File.expand_path("../../#{path}", __dir__)).gsub("\r\n", "\n")) }
    end
  end

  def files
    index = { "corpus" => 1, "generation" => GENERATION, "source_revision" => SOURCE_REVISION,
              "xml_canon_profile" => XML_PROFILE, "wire_profile" => "ruby-native",
              "data_profile" => "exact-values-decimal-v1",
              "source_expectations" => source_expectations, "cases" => cases }
    payload = { "index.json" => json(index), "schema.json" => json(schema), "schema.yaml" => YAML.safe_dump(canonical(schema)) }
    manifest = { "manifest" => 1, "lml_checksum" => checksum, "schema_version" => 2,
                 "generator_version" => "ruby-preservation-oracle-v1", "target" => "ruby", "capabilities" => %w[json xml],
                 "corpora" => [{ "generation" => GENERATION, "sha256" => digest(payload.fetch("index.json")) }],
                 "files" => payload.sort.map { |path, bytes| { "path" => path, "sha256" => digest(bytes) } },
                 "dependencies" => [{ "name" => "lutaml-model", "revision" => SOURCE_REVISION,
                                      "sha256" => digest(File.binread(File.expand_path("../../lutaml-model.gemspec", __dir__)).gsub("\r\n", "\n")) }] }
    payload.merge("manifest.json" => json(manifest))
  end

  def xml_tree(bytes)
    raise ArgumentError, "forbidden XML declaration" if bytes.match?(/<!DOCTYPE|<!ENTITY|<\?(?!xml\s)/i)

    element = REXML::Document.new(bytes).root
    xml_element(element)
  end

  def xml_element(element)
    attrs = element.attributes.each_attribute.filter_map do |attribute|
      next if attribute.expanded_name == "xmlns" || attribute.prefix == "xmlns"

      [[attribute.namespace, attribute.name], attribute.value]
    end.sort
    children = element.children.each_with_object([]) do |child, result|
      if child.is_a?(REXML::Element)
        result << xml_element(child)
      elsif child.is_a?(REXML::Text)
        result.last.is_a?(String) ? result[-1] += child.value : result << child.value
      else
        raise ArgumentError, "unsupported XML node"
      end
    end
    [[element.namespace, element.name], attrs, children]
  end

  def compare(entry, result)
    return entry["expected_error"] == result["error"] ? nil : "error mismatch" if entry["expected_error"]
    return "typed data mismatch" unless entry.fetch("expected_data") == result["data"]

    expected = entry.fetch("expected_output")
    actual = result.fetch("output")
    equal = case entry.fetch("comparison")
            when "bytes" then expected.b == actual.b
            when "xml_tree" then xml_tree(expected) == xml_tree(actual)
            when "data" then JSON.parse(expected) == JSON.parse(actual)
            else false
            end
    equal ? nil : "output mismatch"
  end

  def check(directory)
    index = JSON.parse(File.read(File.join(directory, "index.json")))
    raise ArgumentError, "invalid index" unless index.is_a?(Hash) && index["cases"].is_a?(Array)

    expected = cases.to_h { |entry| [entry.fetch("id"), entry] }
    classes = inputs.to_h { |entry| [entry.first, entry[1]] }
    executed = []
    errors = []
    index.fetch("cases").each do |entry|
      unless entry.is_a?(Hash) && entry["id"].is_a?(String)
        errors << { "id" => "package/cases", "error" => "invalid case" }
        next
      end
      id = entry.fetch("id")
      error = if !expected.key?(id)
                "unknown case"
              elsif executed.include?(id)
                "duplicate case"
              else
                executed << id
                entry == expected.fetch(id) ? compare(entry, execute(entry, classes.fetch(id))) : "changed case"
              end
      errors << { "id" => id, "error" => error } if error
    end
    (expected.keys - executed).each { |id| errors << { "id" => id, "error" => "missing case" } }
    files.each do |path, bytes|
      full_path = File.join(directory, path)
      errors << { "id" => "package/#{path}", "error" => "missing or changed file" } unless File.file?(full_path) && File.binread(full_path) == bytes.b
    end
    (Dir.children(directory) - files.keys).each { |path| errors << { "id" => "package/#{path}", "error" => "unknown file" } }
    unless YAML.safe_load_file(File.join(directory, "schema.yaml"), aliases: false) == JSON.parse(File.read(File.join(directory, "schema.json")))
      errors << { "id" => "package/schema.yaml", "error" => "schema equivalence mismatch" }
    end
    { "expected_ids" => expected.keys, "executed_ids" => executed, "expected_count" => expected.size,
      "executed_count" => executed.size, "errors" => errors }
  rescue Errno::ENOENT, JSON::ParserError, Psych::Exception, KeyError, TypeError, ArgumentError => e
    { "expected_ids" => inputs.map(&:first), "executed_ids" => [], "expected_count" => inputs.size,
      "executed_count" => 0, "errors" => [{ "id" => "package", "error" => e.class.name }] +
        inputs.map { |entry| { "id" => entry.first, "error" => "missing case" } } }
  end

  def main
    options = { check: false, package: File.expand_path("../../spec/fixtures/lml_conformance/preservation", __dir__) }
    OptionParser.new do |parser|
      parser.on("--check") { options[:check] = true }
      parser.on("--package DIRECTORY") { |path| options[:package] = path }
    end.parse!
    unless options[:check]
      FileUtils.mkdir_p(options[:package])
      files.each { |path, bytes| File.binwrite(File.join(options[:package], path), bytes) }
    end
    report = check(options[:package])
    puts json(report)
    report.fetch("errors").empty? ? 0 : 1
  end
end

exit LmlPreservation.main if $PROGRAM_NAME == __FILE__
