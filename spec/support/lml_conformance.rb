# frozen_string_literal: true

require "lutaml/model"
require "json"
require "yaml"
require "digest"
require "rexml/document"

# Independent Ruby oracle and versioned replay protocol for the core package.
module LmlConformance
  GENERATION = "core-v2"
  SOURCE_REVISION = "8a8ef040963b7965388b01b58af33af2b0995f91"
  XML_PROFILE = "expanded-names-text-v1"
  NATIVE_PROFILE = "ruby-native-v1"
  PORTABLE_PROFILE = "portable-exact-json-v1"
  MODEL_ID = "LmlConformance::Record@default"

  class Record < Lutaml::Model::Serializable
    attribute :label, :string
    attribute :count, :integer
    attribute :enabled, :boolean

    xml do
      root "record"
      map_attribute "enabled", to: :enabled
      map_element "label", to: :label
      map_element "count", to: :count
    end

    json do
      map "label", to: :label
      map "count", to: :count
      map "enabled", to: :enabled
    end
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

  # Contract-authored v2 schema; does not depend on the parallel exporter work.
  def schema
    fields = { "label" => "string", "count" => "integer", "enabled" => "boolean" }
    {
      "lml_bundle" => 1, "roots" => [MODEL_ID], "value_types" => {},
      "capabilities" => %w[json xml],
      "provenance" => { "source_revision" => SOURCE_REVISION },
      "models" => { MODEL_ID => {
        "lml" => 2, "model" => "LmlConformance::Record", "register" => "default",
        "attributes" => fields.map do |name, type|
          { "name" => name, "type" => { "kind" => "builtin", "name" => type },
            "required" => false, "collection" => false,
            "default" => { "present" => false }, "initialize_empty" => false }
        end,
        "mappings" => {
          "json" => { "rules" => fields.keys.map { |name| { "key" => [name], "to" => name } } },
          "xml" => { "root" => { "element" => "record" },
                     "namespace" => { "mode" => "inherit" },
                     "rules" => %w[enabled label count].map do |name|
                       { "kind" => name == "enabled" ? "attribute" : "element",
                         "name" => [name], "to" => name,
                         "namespace" => { "mode" => "inherit" } }
                     end },
        }
      } }
    }
  end

  def schema_checksum
    digest(json(schema.except("provenance")))
  end

  def normalized(record)
    { "label" => record.label, "count" => record.count.to_s, "enabled" => record.enabled }
  end

  def case_inputs
    [
      ["core-json", "json", "data", '{"label":"café & tea","count":42,"enabled":false}'],
      ["core-xml-tree", "xml", "xml_tree", '<record enabled="false"><label>café &amp; tea</label><count>42</count></record>'],
      ["core-xml-bytes", "xml", "bytes", '<record enabled="true"><label>plain</label><count>7</count></record>'],
      ["core-json-invalid", "json", "data", "{"],
      ["core-json-portable-exact", "json", "data", '{"label":"beyond binary64","count":"9007199254740993","enabled":false}', PORTABLE_PROFILE],
    ]
  end

  def execute(entry)
    format = entry.fetch("format")
    raise ArgumentError, "unsupported_format" unless %w[json xml].include?(format)

    profile = entry.fetch("wire_profile")
    raise ArgumentError, "unknown wire profile" unless [NATIVE_PROFILE, PORTABLE_PROFILE].include?(profile)
    raise ArgumentError, "portable profile requires JSON" if profile == PORTABLE_PROFILE && format != "json"

    input = entry.fetch("input")
    if profile == PORTABLE_PROFILE
      # This opt-in boundary is for the three-field Record oracle only. Native
      # Ruby mappings stay unchanged; exact JSON integers never pass via Float.
      parsed = JSON.parse(input)
      count = parsed.fetch("count")
      unless count.is_a?(String) && count.match?(/\A-?(?:0|[1-9][0-9]*)\z/)
        raise ArgumentError, "portable integer requires decimal string"
      end

      # The native String cast accepts floating/exponential forms via Float.
      # Supply an already exact Ruby Integer at this opt-in wire boundary.
      parsed["count"] = Integer(count, 10)
      input = JSON.generate(parsed)
    end

    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      record = Record.public_send("from_#{format}", input)
      data = normalized(record)
      output = profile == PORTABLE_PROFILE ? JSON.generate(data) : record.public_send("to_#{format}")
      { "data" => data, "output" => output }
    end
  rescue JSON::ParserError, Lutaml::Model::InvalidFormatError
    { "error" => { "reason" => "invalid_document", "model_id" => MODEL_ID,
                   "format" => format, "location" => "/input" } }
  end

  def oracle_cases
    case_inputs.map do |id, format, comparison, input, profile|
      entry = { "id" => id, "model_id" => MODEL_ID, "lml_checksum" => schema_checksum,
                "format" => format, "input" => input, "comparison" => comparison,
                "wire_profile" => profile || NATIVE_PROFILE, "data_profile" => "exact-values-decimal-v1" }
      result = execute(entry)
      entry.merge("expected_data" => result["data"], "expected_output" => result["output"],
                  "expected_error" => result["error"])
    end
  end

  def profiles
    [NATIVE_PROFILE, PORTABLE_PROFILE].to_h do |profile|
      ids = case_inputs.filter_map { |entry| entry.first if (entry[4] || NATIVE_PROFILE) == profile }
      [profile, { "required_case_ids" => ids }]
    end
  end

  def target_profiles
    { "ruby" => [NATIVE_PROFILE, PORTABLE_PROFILE], "ts" => [PORTABLE_PROFILE], "rust" => [PORTABLE_PROFILE] }
  end

  # Consumers report all required profile/case coverage, including omissions.
  # Selecting another profile never silently certifies a target's required set.
  def coverage(index, target:, executed_ids:)
    required_profiles = index.fetch("target_profiles").fetch(target)
    required_ids = required_profiles.flat_map { |profile| index.fetch("profiles").fetch(profile).fetch("required_case_ids") }
    errors = (required_ids - executed_ids).map { |id| { "id" => id, "error" => "required case not executed" } }
    { "required_profiles" => required_profiles, "required_ids" => required_ids, "errors" => errors }
  end

  def files
    index = { "corpus" => 1, "generation" => GENERATION, "source_revision" => SOURCE_REVISION,
              "xml_canon_profile" => XML_PROFILE, "profiles" => profiles,
              "target_profiles" => target_profiles, "cases" => oracle_cases }
    payload = { "index.json" => json(index), "schema.json" => json(schema),
                "schema.yaml" => YAML.safe_dump(canonical(schema)) }
    manifest = {
      "manifest" => 1, "lml_checksum" => schema_checksum, "schema_version" => 2,
      "generator_version" => "ruby-core-oracle-v2", "target" => "ruby",
      "capabilities" => %w[json xml],
      "corpora" => [{ "generation" => GENERATION, "sha256" => digest(payload.fetch("index.json")) }],
      "files" => payload.sort.map { |path, bytes| { "path" => path, "sha256" => digest(bytes) } },
      "dependencies" => [{ "name" => "lutaml-model", "revision" => SOURCE_REVISION,
                           # Pin repository source text independent of Windows CRLF checkout conversion.
                           "sha256" => digest(File.binread(File.expand_path("../../lutaml-model.gemspec", __dir__)).gsub("\r\n", "\n")) }]
    }
    payload.merge("manifest.json" => json(manifest))
  end

  # Expanded element/attribute names, sorted attributes, significant text and
  # child order; namespace declarations and prefix spelling are not tree data.
  # CDATA and text have the same tree meaning; bytes preserve lexical differences.
  def xml_tree(bytes)
    raise ArgumentError, "DTD and processing instructions are forbidden" if bytes.match?(/<!DOCTYPE|<!ENTITY|<\?(?!xml\s)/i)

    root = REXML::Document.new(bytes).root
    raise ArgumentError, "missing XML root" unless root

    xml_element(root)
  end

  def xml_element(element)
    attributes = element.attributes.each_attribute.filter_map do |attribute|
      next if attribute.expanded_name == "xmlns" || attribute.prefix == "xmlns"

      [[attribute.namespace, attribute.name], attribute.value]
    end.sort
    children = element.children.each_with_object([]) do |child, result|
      if child.is_a?(REXML::Element)
        result << xml_element(child)
      elsif child.is_a?(REXML::Text)
        if result.last.is_a?(String)
          result[-1] += child.value
        else
          result << child.value
        end
      else
        raise ArgumentError, "unsupported XML node"
      end
    end
    [[element.namespace, element.name], attributes, children]
  end

  def compare(entry, actual)
    return actual["error"] == entry["expected_error"] ? nil : "error mismatch" if entry["expected_error"]
    return "unexpected error" if actual["error"]
    return "typed data mismatch" unless actual["data"] == entry.fetch("expected_data")

    expected = entry.fetch("expected_output")
    output = actual.fetch("output")
    equal = case entry.fetch("comparison")
            when "data" then JSON.parse(output) == JSON.parse(expected)
            when "xml_tree" then xml_tree(output) == xml_tree(expected)
            when "bytes" then output.b == expected.b
            else return "unknown comparison"
            end
    equal ? nil : "output mismatch"
  end

  def replay(index)
    raise ArgumentError, "invalid index" unless index.is_a?(Hash)

    expected = oracle_cases.to_h { |entry| [entry.fetch("id"), entry] }
    entries = index.fetch("cases")
    raise ArgumentError, "invalid cases" unless entries.is_a?(Array)

    executed = []
    errors = []
    entries.each do |entry|
      unless entry.is_a?(Hash) && entry["id"].is_a?(String)
        errors << { "id" => "package/cases", "error" => "invalid case" }
        next
      end
      id = entry.fetch("id")
      if !expected.key?(id)
        errors << { "id" => id, "error" => "unknown case" }
      elsif executed.include?(id)
        errors << { "id" => id, "error" => "duplicate case" }
      else
        executed << id
        error = entry == expected.fetch(id) ? compare(entry, execute(entry)) : "changed case"
        errors << { "id" => id, "error" => error } if error
      end
    end
    (expected.keys - executed).each { |id| errors << { "id" => id, "error" => "missing case" } }
    profile_coverage = coverage(index, target: "ruby", executed_ids: executed)
    { "expected_ids" => expected.keys, "executed_ids" => executed,
      "expected_count" => expected.size, "executed_count" => executed.size,
      "required_profiles" => profile_coverage.fetch("required_profiles"),
      "errors" => errors + profile_coverage.fetch("errors") }
  end

  def check(directory)
    report = replay(JSON.parse(File.read(File.join(directory, "index.json"))))
    files.each do |path, bytes|
      full_path = File.join(directory, path)
      next if File.file?(full_path) && File.binread(full_path) == bytes.b

      report["errors"] << { "id" => "package/#{path}", "error" => "missing or changed file" }
    end
    (Dir.children(directory) - files.keys).sort.each do |path|
      report["errors"] << { "id" => "package/#{path}", "error" => "unknown file" }
    end
    json_schema = JSON.parse(File.read(File.join(directory, "schema.json")))
    yaml_schema = YAML.safe_load_file(File.join(directory, "schema.yaml"), aliases: false)
    unless json_schema == yaml_schema
      report["errors"] << { "id" => "package/schema.yaml", "error" => "schema equivalence mismatch" }
    end
    report
  rescue Errno::ENOENT, JSON::ParserError, Psych::Exception, KeyError, TypeError, ArgumentError => e
    { "expected_ids" => case_inputs.map(&:first), "executed_ids" => [],
      "expected_count" => case_inputs.size, "executed_count" => 0,
      "errors" => [{ "id" => "package", "error" => e.class.name }] +
        case_inputs.map { |entry| { "id" => entry.first, "error" => "missing case" } } }
  end
end
