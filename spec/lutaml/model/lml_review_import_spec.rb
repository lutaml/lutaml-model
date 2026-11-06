# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "rbconfig"

# lutaml-model#1033 final review (Ruby, #1116 @ 7e23cd7), import side:
# M1 parents before children, M2 transactional install, M5 attribute
# names, L1 mapping scalars, L2 no descent into existing constants,
# L7 duplicate JSON keys on any json gem, L8 bounded nesting.
RSpec.describe "LML import hardening (review of #1116)" do
  let(:lml) { Lutaml::Model::Lml }
  let(:rejected) { lml::RejectedError }

  def string_attr(name)
    { "name" => name, "type" => { "kind" => "builtin", "name" => "string" } }
  end

  def model_doc(name, attributes = [], mappings: nil)
    doc = { "lml" => 2, "model" => name, "register" => "default", "attributes" => attributes }
    doc["mappings"] = mappings if mappings
    doc
  end

  def bundle_of(*docs, value_types: {}, roots: nil)
    models = docs.to_h { |doc| ["#{doc['model']}@#{doc['register']}", doc] }
    formats = docs.flat_map { |doc| (doc["mappings"] || {}).keys }.uniq.sort
    { "lml_bundle" => 1, "roots" => roots || [models.keys.min], "capabilities" => formats,
      "value_types" => value_types, "models" => models }
  end

  def refusal_of
    yield
    nil
  rescue rejected => e
    e
  end

  describe "M1: a parent installs before its nested children" do
    let(:bundle) do
      bundle_of(model_doc("Para", [string_attr("t")]),
                model_doc("Para::Inner", [string_attr("u")]))
    end

    before { stub_const("ImportHolder", Module.new) }

    it "imports a model and a model nested under it into a namespace" do
      classes = lml.import_bundle(bundle, namespace: ImportHolder)

      expect(ImportHolder::Para).to be(classes["Para@default"])
      expect(ImportHolder::Para::Inner).to be(classes["Para::Inner@default"])
      expect(classes["Para::Inner@default"].name).to eq("ImportHolder::Para::Inner")
    end

    it "verifies the materialization of an exported parent and nested child" do
      stub_const("VerifySrc", Module.new)
      parent = Class.new(Lutaml::Model::Serializable) do
        attribute :t, :string
        xml { root "para" }
      end
      VerifySrc.const_set(:Para, parent)
      child = Class.new(Lutaml::Model::Serializable) do
        attribute :u, :string
        xml { root "inner" }
      end
      parent.const_set(:Inner, child)

      exported = lml.export_bundle([parent, child])
      expect(exported.models.keys.first).to include("Inner")
      expect { lml.verify_materialization(exported) }.not_to raise_error
    end

    it "gives the same result whichever way the ids sort" do
      reversed = bundle_of(model_doc("Aa::Bb::Cc"), model_doc("Aa::Bb"), model_doc("Aa"))
      classes = lml.import_bundle(reversed, namespace: ImportHolder)

      expect(ImportHolder::Aa::Bb::Cc).to be(classes["Aa::Bb::Cc@default"])
    end

    it "builds a module holder for a path no model declares" do
      classes = lml.import_bundle(bundle_of(model_doc("Pkg::Deep::Leaf")), namespace: ImportHolder)

      expect(ImportHolder::Pkg).to be_a(Module).and(satisfy { |m| !m.is_a?(Class) })
      expect(ImportHolder::Pkg::Deep::Leaf).to be(classes["Pkg::Deep::Leaf@default"])
    end

    it "refuses two registers that claim one constant" do
      twin = bundle_of(model_doc("Twin"), model_doc("Twin").merge("register" => "other"))
      error = refusal_of { lml.import_bundle(twin, namespace: ImportHolder) }

      expect(error.reason).to eq(:duplicate_id)
      expect(ImportHolder.constants).to be_empty
    end
  end

  describe "M2: import is all or nothing" do
    let(:bundle) do
      bundle_of(model_doc("Fine", [string_attr("x")]),
                model_doc("Needy", [{ "name" => "y", "type" => { "kind" => "value", "id" => "V" } }]),
                value_types: { "V" => { "base" => "string", "facets" => {} } })
    end

    before { stub_const("ImportHolder", Module.new) }

    it "leaves no constant behind when linking fails, and a retry succeeds" do
      error = refusal_of { lml.import_bundle(bundle, namespace: ImportHolder) }

      expect(error.reason).to eq(:missing_type_binding)
      expect(ImportHolder.constants).to be_empty

      classes = lml.import_bundle(bundle, namespace: ImportHolder,
                                          type_bindings: { "V" => Lutaml::Model::Type::String })
      expect(classes.keys).to eq(%w[Fine@default Needy@default])
    end

    it "removes the installed constants when the mapping compile refuses" do
      rule = { "kind" => "element", "name" => ["n"], "to" => "nope" }
      mapped = bundle_of(model_doc("Ok1", [string_attr("a")]),
                         model_doc("Mapped", [string_attr("a")],
                                   mappings: { "xml" => { "rules" => [rule] } }))
      error = refusal_of { lml.import_bundle(mapped, namespace: ImportHolder) }

      expect(error.reason).to eq(:dangling_reference)
      expect(ImportHolder.constants).to be_empty

      rule["to"] = "a"
      expect(lml.import_bundle(mapped, namespace: ImportHolder).keys).to eq(%w[Mapped@default Ok1@default])
    end
  end

  describe "M5: attribute names" do
    def import_attribute(name)
      lml.import_bundle(bundle_of(model_doc("A", [string_attr(name)])))["A@default"]
    end

    ["@x", "a b", "foo=", "1", "x-y", "Name", "ok?", "go!", ""].each do |name|
      it "refuses the non-identifier #{name.inspect}" do
        error = refusal_of { import_attribute(name) }

        expect(error).to be_a(rejected)
        expect(error.reason).to eq(:invalid_document)
        expect(error.location).to eq("/models/A@default/attributes/0/name")
      end
    end

    %w[initialize class element_order attribute_order to_json to_xml
       lutaml_register public_send encoding].each do |name|
      it "refuses #{name}, which breaks construction or serialization" do
        error = refusal_of { import_attribute(name) }

        expect(error&.reason).to eq(:reserved_member)
        expect(error.attribute).to eq(name)
      end
    end

    %w[display hash schema_location send freeze to_s object_id title
       _private snake_case_2 value].each do |name|
      it "accepts #{name} and builds a class that round-trips it" do
        klass = import_attribute(name)
        instance = klass.new(name => "v")

        expect(instance.public_send(name)).to eq("v")
        expect(klass.from_json(instance.to_json).public_send(name)).to eq("v")
      end
    end

    it "re-derives the reserved attribute names by measurement (every broken name is denied)" do
      skip "needs fork to isolate each probe" unless Process.respond_to?(:fork)

      serializable = Lutaml::Model::Serializable
      candidates = (Object.public_instance_methods + Object.protected_instance_methods +
        serializable.public_instance_methods + serializable.protected_instance_methods).map(&:to_s) +
        %w[initialize initialize_copy initialize_dup initialize_clone method_missing]
      candidates = candidates.uniq.grep(lml::DocumentValidator::ATTRIBUTE_NAME).sort

      broken = candidates.reject { |name| isolated_attribute_works?(name) }

      expect(candidates.size).to be > 50
      reserved = lml::DocumentValidator::RESERVED_ATTRIBUTE_NAMES
      expect(broken - reserved).to be_empty
      expect(reserved - candidates).to be_empty
    end

    # One forked process per probe: a broken name must not poison the
    # next measurement.
    def isolated_attribute_works?(name)
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        $stderr.reopen(File::NULL)
        writer.write(attribute_works?(name) ? "ok" : "broken")
        writer.close
        exit!(0)
      end
      writer.close
      result = reader.read
      Process.wait(pid)
      result == "ok"
    end

    def attribute_works?(name)
      sym = name.to_sym
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute sym, :string
        xml do
          root "r"
          map_element "e", to: sym
        end
        key_value { map "e", to: sym }
      end
      Object.const_set(:MeasuredProbe, klass)
      klass.new
      instance = klass.new(name => "v")
      instance.public_send(name) == "v" &&
        klass.from_json(instance.to_json).public_send(name) == "v" &&
        klass.from_xml(instance.to_xml).public_send(name) == "v" &&
        klass.from_yaml(instance.to_yaml).public_send(name) == "v"
    rescue StandardError, SystemStackError
      false
    end
  end

  describe "L1: mapping scalars" do
    def xml_bundle(mapping)
      bundle_of(model_doc("A", [string_attr("x")], mappings: { "xml" => mapping }))
    end

    def namespace_mapping(prefix)
      { "namespace" => { "mode" => "uri", "uri" => "http://x", "prefix" => prefix }, "rules" => [] }
    end

    ["str", 5, [1], true].each do |root|
      it "refuses root #{root.inspect} with a named code" do
        error = refusal_of { lml.import_bundle(xml_bundle("root" => root, "rules" => [])) }

        expect(error&.reason).to eq(:invalid_document)
      end
    end

    [5, ["a"], ""].each do |element|
      it "refuses root.element #{element.inspect}" do
        error = refusal_of { lml.import_bundle(xml_bundle("root" => { "element" => element }, "rules" => [])) }

        expect(error&.reason).to eq(:invalid_document)
      end
    end

    [5, { "a" => 1 }, [], "", "a b"].each do |prefix|
      it "refuses namespace prefix #{prefix.inspect}" do
        error = refusal_of { lml.import_bundle(xml_bundle(namespace_mapping(prefix))) }

        expect(error&.reason).to eq(:invalid_document)
      end
    end

    it "refuses a rule child_mappings that is not an object" do
      rule = { "key" => ["k"], "to" => "x", "child_mappings" => "oops" }
      bundle = bundle_of(model_doc("A", [string_attr("x")], mappings: { "json" => { "rules" => [rule] } }))

      expect(refusal_of { lml.import_bundle(bundle) }&.reason).to eq(:invalid_document)
    end

    it "still imports a well-formed root, prefix and rule" do
      mapping = namespace_mapping("p").merge("root" => { "element" => "a" })
      classes = lml.import_bundle(xml_bundle(mapping))

      expect(classes["A@default"].new(x: "1").to_xml).to include("http://x")
    end
  end

  describe "L2: existing constants are never descended into" do
    before { stub_const("ImportHolder", Module.new) }

    it "refuses a name whose first segment is a non-module value" do
      ImportHolder.const_set(:Foo, 5)
      error = refusal_of { lml.import_bundle(bundle_of(model_doc("Foo::Bar")), namespace: ImportHolder) }

      expect(error&.reason).to eq(:duplicate_id)
      expect(ImportHolder::Foo).to eq(5)
    end

    it "refuses a pre-existing class as an intermediate and injects nothing into it" do
      config = Class.new
      ImportHolder.const_set(:Config, config)
      error = refusal_of { lml.import_bundle(bundle_of(model_doc("Config::Evil")), namespace: ImportHolder) }

      expect(error&.reason).to eq(:duplicate_id)
      expect(config.constants).to be_empty
    end

    it "refuses a pre-existing module as an intermediate and leaves it untouched" do
      existing = Module.new
      ImportHolder.const_set(:Shared, existing)
      error = refusal_of { lml.import_bundle(bundle_of(model_doc("Shared::Evil")), namespace: ImportHolder) }

      expect(error&.reason).to eq(:duplicate_id)
      expect(existing.constants).to be_empty
    end
  end

  describe "L7: duplicate JSON keys" do
    let(:text) do
      a1 = '{"name":"x","type":{"kind":"builtin","name":"string"}}'
      a2 = '{"name":"x","type":{"kind":"builtin","name":"integer"}}'
      %({"lml_bundle":1,"roots":["A@default"],"capabilities":[],"value_types":{},) +
        %("models":{"A@default":{"lml":2,"model":"A","register":"default",) +
        %("attributes":[#{a1}],"attributes":[#{a2}]}}})
    end

    it "is refused" do
      error = refusal_of { lml::Importer.bundle(text) }

      expect(error&.reason).to eq(:invalid_document)
      expect(error.message).to include("duplicate key")
    end

    it "is refused on a json gem that keeps the last value (json < 3.1)" do
      older = Gem::Specification.find_all_by_name("json", "< 3.1").max_by(&:version)
      skip "no json < 3.1 installed" unless older

      script = <<~RUBY
        gem "json", "= #{older.version}"
        $LOAD_PATH.unshift(File.expand_path("lib", #{Dir.pwd.inspect}))
        require "lutaml/model"
        require "lutaml/model/lml"
        text = #{text.inspect}
        begin
          Lutaml::Model::Lml::Importer.bundle(text)
          puts "ACCEPTED"
        rescue Lutaml::Model::Lml::RejectedError => e
          puts "REFUSED \#{e.reason}"
        end
      RUBY
      out, status = Open3.capture2e(RbConfig.ruby, "-e", script)

      expect(status).to be_success
      expect(out.lines.last.to_s.strip).to eq("REFUSED invalid_document")
    end

    it "refuses a repeated key spelled with an escape, in a nested object" do
      nested = '{"lml_bundle":1,"provenance":{"a":{"k":1,"\\u006b":2}}}'

      expect(refusal_of { lml::Importer.bundle(nested) }&.reason).to eq(:invalid_document)
    end

    it "allows one key in sibling objects and a value equal to a key" do
      sibling = '{"lml_bundle":1,"roots":[],"capabilities":[],"value_types":{},"models":{},' \
                '"provenance":{"a":{"k":"k"},"b":{"k":"k"},"c":["k","k"]}}'

      expect(lml::Importer.bundle(sibling).provenance.keys).to eq(%w[a b c])
    end

    it "still accepts a document with distinct keys" do
      distinct = text.sub('"attributes":[{"name":"x","type":{"kind":"builtin","name":"integer"}}]', '"mappings":{}')

      expect(lml::Importer.bundle(distinct).models.keys).to eq(["A@default"])
    end
  end

  describe "L8: bounded nesting" do
    def deep(levels)
      root = {}
      cursor = root
      levels.times do
        node = {}
        cursor["k"] = node
        cursor = node
      end
      root
    end

    def bundle_with_provenance(tree)
      { "lml_bundle" => 1, "roots" => [], "models" => {}, "value_types" => {},
        "capabilities" => [], "provenance" => tree }
    end

    it "refuses a 12,000-deep Hash with a named code, not SystemStackError" do
      error = refusal_of { lml::Importer.bundle(bundle_with_provenance(deep(12_000))) }

      expect(error&.reason).to eq(:invalid_document)
      expect(error.message).to include("nesting deeper than")
    end

    it "accepts nesting up to the limit" do
      limit = lml::DocumentValidator::MAX_DEPTH
      expect { lml::Importer.bundle(bundle_with_provenance(deep(limit - 2))) }.not_to raise_error
    end
  end
end
