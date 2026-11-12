# frozen_string_literal: true

require_relative "export_preservation"

# Real source-model oracles; the original MML classes are loaded only on request.
module LmlMml
  SOURCE_REVISION = "d826d80f6b1477569c8320ccd945268a6ce1062f"
  SOURCE_VERSION = "2.4.7"
  SOURCE_SPECS = {
    "ordered_content_spec.rb" => "sha256:b776a2a40a2ad8fcfdeb0363571b8638437868cdcb169492d9a61d3e036235ab",
    "v3_spec.rb" => "sha256:0221940af4e7aae3226885bd789ae66a632b500ae77fef77c289ecfff4ab9ac9",
    "v4_spec.rb" => "sha256:4fa8b613b26c7d1d435309df5d1b76fae727aad232f859d38a974e69bdfbe201",
  }.freeze
  SOURCE_DIGEST = "sha256:271bd0ed0256a02784b35aaa99e7f0aaf0ba11abc64ed974d24025375b4f9829"
  FRAMEWORK_REVISION = "4e75c92b7d9ab3e3aa5f4f90af4a9ce860c76f72"
  PRESERVATION_REVISION = "9716740b6b7feb755b8557a2bfab89d066e855bd"
  NAMESPACE = "http://www.w3.org/1998/Math/MathML"
  PACKAGE = File.expand_path("../../spec/fixtures/lml_mml", __dir__)

  module_function

  def source_root
    ENV["LML_MML_ROOT"] || Gem.path.map { |path| File.join(path, "gems", "mml-#{SOURCE_VERSION}") }
      .find { |path| File.directory?(path) } || raise(ArgumentError, "set LML_MML_ROOT to the pinned mml source")
  end

  def source_digest(root)
    digest = Digest::SHA256.new
    Dir.glob(File.join(root, "lib/**/*.rb"), sort: false).sort.each do |path|
      digest.update("#{path.delete_prefix("#{root}/")}\0#{File.binread(path)}\0")
    end
    "sha256:#{digest.hexdigest}"
  end

  def load_source(root = source_root)
    root = File.expand_path(root)
    unless source_digest(root) == SOURCE_DIGEST
      raise ArgumentError, "mml source digest differs from #{SOURCE_REVISION} (#{SOURCE_VERSION})"
    end

    $LOAD_PATH.unshift(File.join(root, "lib"))
    require "mml"
    require "mml/version"
    raise ArgumentError, "expected mml #{SOURCE_VERSION}" unless Mml::VERSION == SOURCE_VERSION

    [Mml::V2, Mml::V3, Mml::V4].each do |version|
      configuration = version::Configuration
      configuration.populate_context! unless configuration.context
    end
    loaded = $LOADED_FEATURES.find { |path| path.end_with?("/mml.rb") }
    unless loaded == File.join(root, "lib/mml.rb")
      raise ArgumentError, "mml was already loaded from a different source"
    end

    root
  end

  def cases
    mixed = %(<mi xmlns="#{NAMESPACE}" mathvariant="bold">x<malignmark/>y<mglyph src="g.png" alt="g"/>z</mi>)
    nested = %(<math xmlns="#{NAMESPACE}" display="block"><mrow><mi>a</mi><mo>+</mo><mfrac><mi>x<malignmark/>y</mi><mrow><mn>1</mn><mo>+</mo><mn>2</mn></mrow></mfrac><mi>b</mi></mrow><mi>c</mi></math>)
    [3, 4].flat_map do |version|
      [["v#{version}-mi-mixed", "Mi", mixed], ["v#{version}-math-nested", "Math", nested]].map do |id, name, input|
        { "id" => id, "model_id" => "Mml::V#{version}::#{name}@mml_v#{version}",
          "register" => "mml_v#{version}", "input" => input }
      end
    end
  end

  def normalize(value, register, identities = {})
    case value
    when Lutaml::Model::UninitializedClass then { "state" => "absent" }
    when Array then value.map { |item| normalize(item, register, identities) }
    when Lutaml::Model::Serialize
      klass = value.class
      model_id = identities.fetch(klass) { "#{klass.name}@#{register}" }
      attributes = klass.attributes(register).to_h do |name, _attribute|
        [name.to_s, normalize(value.public_send(name), register, identities)]
      end
      descriptor = Lutaml::Model::Lml::OrderedContent.descriptor_for(
        klass, mapping: klass.mappings_for(:xml, register), register: register
      )
      attributes["__lml_content"] = Lutaml::Model::Lml::OrderedContent.capture(descriptor, value) if descriptor
      attributes.merge("__lml_model" => model_id)
    when Integer then value.to_s
    else value
    end
  end

  def replay(entry, klass, identities = {})
    register = entry.fetch("register").to_sym
    Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      record = klass.from_xml(entry.fetch("input"), register: register)
      output = record.to_xml(register: register)
      { "data" => normalize(record, register, identities), "output" => output,
        "tree" => LmlPreservation.xml_tree(output) }
    end
  end

  def refusal(error)
    { "reason" => error.reason.to_s, "model" => error.klass.to_s,
      "detail" => error.detail, "location" => error.location }.compact
  end

  def inventory
    [Mml::V2, Mml::V3, Mml::V4].map do |version|
      register = version::Configuration.context_id
      registry = version::Configuration.context.registry
      classes = registry.names.map { |name| registry.lookup(name) }.uniq.sort_by(&:name)
      declarations = classes.map do |klass|
        mapping = klass.mappings_for(:xml, register)
        source = { "model" => klass.name, "source_ordered" => mapping.ordered?,
                   "source_mixed_content" => mapping.mixed_content?,
                   "source_ordered_content" => !!(mapping.ordered? || mapping.mixed_content?),
                   "float_attributes" => klass.attributes(register).values.select { |attribute| attribute.unresolved_type == :float }.map { |attribute| attribute.name.to_s } }
        begin
          document = Lutaml::Model::Lml::Exporter.project(klass, register: register)
          source.merge("ordered_content" => !!document["ordered_content"])
        rescue Lutaml::Model::Lml::RejectedError => e
          source.merge(refusal(e))
        end
      end
      { "version" => version.name, "register" => register.to_s,
        "registered_count" => classes.size, "exported_count" => declarations.count { |entry| !entry.key?("reason") },
        "source_ordered_count" => declarations.count { |entry| entry["source_ordered_content"] },
        "exported_ordered_count" => declarations.count { |entry| entry["ordered_content"] },
        "float_ordered_count" => declarations.count do |entry|
          entry["ordered_content"] && entry["float_attributes"].any?
        end,
        "declarations" => declarations }
    end
  end

  def source_oracles
    cases.map do |entry|
      klass = Object.const_get(entry.fetch("model_id").split("@").first)
      entry.merge("expected" => replay(entry, klass))
    end
  end

  def source_graph(root, register)
    seen = {}
    queue = [root]
    until queue.empty?
      klass = queue.shift
      next if seen.key?(klass)

      children = klass.attributes(register).values.filter_map do |attribute|
        type = attribute.type(register)
        type if type.is_a?(Class) && type.include?(Lutaml::Model::Serialize)
      end.uniq
      seen[klass] = children
      queue.concat(children)
    end
    seen.to_h do |klass, children|
      ["#{klass.name}@#{register}", children.map { |child| "#{child.name}@#{register}" }.sort]
    end.sort.to_h
  end

  def graph_exports
    cases.to_h do |entry|
      klass = Object.const_get(entry.fetch("model_id").split("@").first)
      register = entry.fetch("register").to_sym
      references = source_graph(klass, register)
      bundle = Lutaml::Model::Lml.export_bundle([klass], register: register)
      [entry.fetch("id"), { "bundle" => bundle.to_h, "checksum" => bundle.checksum,
                            "model_count" => bundle.models.size, "source_references" => references }]
    rescue Lutaml::Model::Lml::RejectedError => e
      [entry.fetch("id"), { "refusal" => refusal(e), "source_references" => references }]
    end
  end

  def existing_exclusions(root, versions)
    { "reported_historical_ordered_refusals" => 191, "historical_ordered_model_count_matched" => versions.sum { |version| version.fetch("source_ordered_count") } == 191,
      "source_specs" => SOURCE_SPECS.map do |name, digest|
        path = File.join(root, "spec/mml", name)
        if File.file?(path) && LmlPreservation.digest(File.binread(path)) != digest
          raise ArgumentError, "mml source expectation differs: #{name}"
        end

        { "path" => "spec/mml/#{name}", "sha256" => digest }
      end,
      "v3" => { "existing_filters" => ["share requires XInclude", "HTML span", "mathml entity", "foreign background/color attributes", "XML comments", "ErrorHandling"],
                "negative_tests_pending" => "Parser does not validate MathML schema compliance",
                "available_fixture_count" => Dir.glob(File.join(root, "spec/fixtures/mml3-testsuite/Math/testsuite/build/main/**/*.mml")).size },
      "v4" => { "existing_filters" => ["HTML elements", "unknown namespace elements", "nonempty none/mprescripts/mspace", "mtd outside table", "br inside mtext"],
                "available_fixture_count" => Dir.glob(File.join(root, "spec/fixtures/mmlcore-testsuite/mathml/**/*.mml")).size } }
  end

  def files(root = source_root)
    root = load_source(root)
    exports = graph_exports
    versions = inventory
    payloads = {
      "oracle.json" => LmlPreservation.json("cases" => source_oracles),
      "inventory.json" => LmlPreservation.json("versions" => versions, "existing_exclusions" => existing_exclusions(root, versions)),
    }
    exports.each do |id, result|
      next unless result.key?("bundle")

      payloads["#{id}.json"] = LmlPreservation.json(result.fetch("bundle"))
      payloads["#{id}.yaml"] = YAML.safe_dump(LmlPreservation.canonical(result.fetch("bundle")))
    end
    manifest = {
      "generation" => "mml-pilot-v1", "source_revision" => SOURCE_REVISION, "source_version" => SOURCE_VERSION,
      "source_digest" => SOURCE_DIGEST, "framework_revision" => FRAMEWORK_REVISION,
      "preservation_revision" => PRESERVATION_REVISION, "case_count" => cases.size,
      "graphs" => exports.transform_values { |result| result.except("bundle") },
      "files" => payloads.sort.map { |path, bytes| { "path" => path, "sha256" => LmlPreservation.digest(bytes) } }
    }
    payloads.merge("manifest.json" => LmlPreservation.json(manifest))
  end

  # Package drift is always an error. A refused closed graph is reported as
  # "refused" and becomes an error only with require_complete.
  def check(directory, payloads, require_complete: false)
    errors = payloads.filter_map do |path, bytes|
      full_path = File.join(directory, path)
      { "id" => path, "error" => "missing or changed file" } unless File.file?(full_path) && File.binread(full_path) == bytes.b
    end
    (Dir.children(directory) - payloads.keys).each { |path| errors << { "id" => path, "error" => "unknown file" } }
    manifest = JSON.parse(payloads.fetch("manifest.json"))
    refused = manifest.fetch("graphs").select { |_id, graph| graph.key?("refusal") }
    refused.each do |id, graph|
      errors << { "id" => id, "error" => "closed graph refused", "refusal" => graph.fetch("refusal") } if require_complete
    end
    { "expected_count" => cases.size, "exported_count" => manifest.fetch("graphs").count { |_id, graph| graph.key?("checksum") },
      "refused" => refused.transform_values { |graph| graph.fetch("refusal") }, "errors" => errors }
  end

  def main(arguments = ARGV)
    options = { check: false, complete: false, package: PACKAGE, root: nil }
    OptionParser.new do |parser|
      parser.on("--check") { options[:check] = true }
      parser.on("--require-complete") { options[:complete] = true }
      parser.on("--package DIRECTORY") { |path| options[:package] = path }
      parser.on("--mml-root DIRECTORY") { |path| options[:root] = path }
    end.parse!(arguments)
    payloads = files(options[:root] || source_root)
    unless options[:check]
      FileUtils.mkdir_p(options[:package])
      payloads.each { |path, bytes| File.binwrite(File.join(options[:package], path), bytes) }
    end
    report = check(options[:package], payloads, require_complete: options[:complete])
    puts LmlPreservation.json(report)
    report.fetch("errors").empty? ? 0 : 1
  end
end

exit LmlMml.main if $PROGRAM_NAME == __FILE__
