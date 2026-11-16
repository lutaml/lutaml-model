# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../../support/lml_import_fixtures"
require_relative "../../support/lml_materialization_fixtures"

# lutaml-model#1033 card 03c: additive export_bundle / import_bundle /
# verify_materialization, and a true round trip in a fresh process that
# has none of the source constants.
RSpec.describe "LML bundle import/export" do
  let(:lml) { Lutaml::Model::Lml }
  let(:fx) { LmlImportFixtures }
  let(:rejected) { lml::RejectedError }
  let(:roots) { fx::GRAPH_ROOTS }
  let(:bundle) { lml.export_bundle(roots) }
  let(:repo_root) { File.expand_path("../../..", __dir__) }

  def doc_sample
    item = LmlMappingFixtures::Item.new(id: "i1", label: "<one>")
    LmlMappingFixtures::Doc.new(
      title: "T", count: 2, items: [item],
      entries: [LmlMappingFixtures::Entry.new(name: "n", value: "v")]
    )
  end

  def kennel_json
    '{"animals":[{"kind":"dog","name":"Rex"},{"kind":"animal","name":"Tom"}],"owner":"Ann"}'
  end

  def refusal
    yield
    nil
  rescue rejected => e
    e
  end

  describe ".export_bundle" do
    it "exports the closed graph reachable from the roots, keyed by Model@register" do
      expect(bundle).to be_a(lml::Bundle)
      expect(bundle.models.keys).to include("LmlMappingFixtures::Item@default", "LmlImportFixtures::Dog@default",
                                            "LmlOrderFixtures::Emphasis@default")
      expect(bundle.roots).to eq(roots.map { |k| "#{k.name}@default" }.sort)
    end

    it "resolves a nil register the same as the default and as an explicit default" do
      by_default = lml.export_bundle(fx::Animal)
      expect(lml.export_bundle(fx::Animal, register: nil).checksum).to eq(by_default.checksum)
      expect(lml.export_bundle([[fx::Animal, "default"]]).checksum).to eq(by_default.checksum)
      expect(lml.export_bundle([fx::Animal], register: "default").checksum).to eq(by_default.checksum)
    end

    context "with a non-default named register" do
      let(:child) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :label, :string
          xml do
            element "child"
            map_element "label", to: :label
          end
        end
      end

      before do
        stub_const("LmlNamedRegisterChild", child)
        stub_const("LmlNamedRegisterParent", Class.new(Lutaml::Model::Serializable) do
          attribute :child, :lml_named_child
          xml do
            element "parent"
            map_element "child", to: :child
          end
        end)
        registry = Lutaml::Model::TypeRegistry.new
        Lutaml::Model::Type.register_builtin_types_in(registry)
        registry.register(:lml_named_child, child)
        Lutaml::Model::GlobalContext.create_context(id: :lml_named_register, registry: registry)
      end

      after { Lutaml::Model::GlobalContext.unregister_context(:lml_named_register) }

      it "resolves that register's context (a String register must not fall back to default)" do
        [:lml_named_register, "lml_named_register"].each do |name|
          exported = lml.export_bundle(LmlNamedRegisterParent, register: name)
          expect(exported.models.keys).to contain_exactly("LmlNamedRegisterChild@lml_named_register",
                                                          "LmlNamedRegisterParent@lml_named_register")
          attribute = exported.models.fetch("LmlNamedRegisterParent@lml_named_register").fetch("attributes").first
          expect(attribute.fetch("type")).to eq("kind" => "model", "id" => "LmlNamedRegisterChild@lml_named_register")
        end
      end
    end

    it "exports the same documents as the per-class projection" do
      doc = lml::Exporter.project(LmlMappingFixtures::Item)
      expect(bundle.models["LmlMappingFixtures::Item@default"]).to eq(doc)
    end

    it "excludes provenance from the checksum" do
      tagged = lml.export_bundle(fx::Animal, provenance: { "tool" => "spec" })
      expect(tagged.provenance).to eq("tool" => "spec")
      expect(tagged.checksum).to eq(lml.export_bundle(fx::Animal).checksum)
    end
  end

  describe "existing entry points" do
    it "keeps export and verify returning the v1 Document" do
      document = lml.export(LmlMappingFixtures::Item)
      expect(document).to be_a(lml::Document)
      expect(lml.verify(document)).to be_a(lml::Document)
      expect(lml.verify(document).checksum).to eq(document.checksum)
    end

    it "keeps the named mismatch error of verify for an unloadable model" do
      document = lml::Document.new(model_name: "Nope::Gone", attributes: [], mappings: {})
      expect(refusal { lml.verify(document) }.reason).to eq(:unknown_type)
    end
  end

  describe ".import_bundle" do
    let(:holder) { stub_const("LmlImported", Module.new) }

    it "builds working classes whose output equals the source classes in xml, json and yaml" do
      classes = lml.import_bundle(bundle, namespace: holder)
      generated = classes["LmlMappingFixtures::Doc@default"]
      source = doc_sample

      expect(generated).not_to equal(LmlMappingFixtures::Doc)
      %i[xml json yaml].each do |format|
        text = source.public_send(:"to_#{format}")
        oracle = LmlMappingFixtures::Doc.public_send(:"from_#{format}", text).public_send(:"to_#{format}")
        expect(generated.public_send(:"from_#{format}", text).public_send(:"to_#{format}")).to eq(oracle)
      end
    end

    it "accepts a Bundle, its Hash form and its JSON text alike" do
      plain = lml.export_bundle(LmlMappingFixtures::Doc)
      forms = [plain, plain.to_h, JSON.generate(plain.to_h)]
      ids = forms.map { |form| lml.import_bundle(form).keys }
      expect(ids.uniq.length).to eq(1)
      expect(ids.first).to eq(plain.models.keys.sort)
    end

    it "names an invalid bundle instead of importing part of it" do
      broken = JSON.parse(JSON.generate(bundle.to_h))
      broken["roots"] = ["Missing@default"]
      expect(refusal { lml.import_bundle(broken) }.reason).to eq(:dangling_reference)
      expect(refusal { lml.import_bundle("{not json") }.reason).to eq(:invalid_document)
    end

    it "needs an installed namespace for polymorphic discriminator targets" do
      error = refusal { lml.import_bundle(lml.export_bundle(fx::Kennel)) }
      expect(error.reason).to eq(:unsupported_mapping)
      expect(error.message).to include("installed constant")

      classes = lml.import_bundle(lml.export_bundle(fx::Kennel), namespace: holder)
      kennel = classes["LmlImportFixtures::Kennel@default"].from_json(kennel_json)
      expect(kennel.animals.map(&:class)).to eq(
        [classes["LmlImportFixtures::Dog@default"], classes["LmlImportFixtures::Animal@default"]],
      )
      expect(kennel.to_json).to eq(JSON.generate(JSON.parse(kennel_json)))
    end
  end

  describe ".verify_materialization" do
    it "returns the re-exported bundle, equal to the input" do
      verified = lml.verify_materialization(bundle, namespace: stub_const("LmlVerified", Module.new))
      expect(verified).to eq(bundle)
      expect(verified.checksum).to eq(bundle.checksum)
      expect(verified.models).to eq(bundle.models)
    end

    it "works without a namespace, including polymorphism, and leaves no constant behind" do
      before = Object.constants.grep(/\ALmlVerify/)
      expect(lml.verify_materialization(bundle).checksum).to eq(bundle.checksum)
      expect(Object.constants.grep(/\ALmlVerify/)).to eq(before)
    end

    it "removes the transient namespace when verification fails" do
      before = Object.constants.grep(/\ALmlVerify/)
      sparse = LmlMaterializationFixtures.cyclic
      expect(refusal { lml.verify_materialization(sparse) }.reason).to eq(:round_trip_mismatch)
      expect(Object.constants.grep(/\ALmlVerify/)).to eq(before)
    end

    it "keeps non-default registers in the identifiers" do
      Lutaml::Model::GlobalRegister.register(Lutaml::Model::Register.new(:lml_alt))
      alt = lml.export_bundle(fx::Animal, register: "lml_alt")
      expect(alt.roots).to eq(["LmlImportFixtures::Animal@lml_alt"])
      expect(lml.verify_materialization(alt).checksum).to eq(alt.checksum)
    ensure
      Lutaml::Model::GlobalRegister.remove(:lml_alt)
    end

    it "names a bundle that is valid but not in exporter form as a round_trip_mismatch" do
      sparse = LmlMaterializationFixtures.cyclic
      holder = stub_const("LmlSparse", Module.new)

      expect(lml.import_bundle(sparse, namespace: holder).keys).to eq(sparse["models"].keys.sort)
      error = refusal { lml.verify_materialization(sparse) }
      expect(error.reason).to eq(:round_trip_mismatch)
      expect(error.message).to match(/sha256:\h{13}.* vs sha256:\h{13}/)
    end
  end

  describe "true reconstruction in a fresh process" do
    # Pin one real adapter for both sides: other specs may leave the global
    # XML slot holding a pre-resolved class (FIXED_ADAPTER_TYPE), which a
    # fresh process cannot reproduce by name.
    around { |example| Lutaml::Model::Config.with_adapter(xml: :nokogiri) { example.run } }

    let(:child_script) do
      <<~'RUBY'
        require "json"
        require "lutaml/model"
        payload = JSON.parse(File.read(ARGV.fetch(0)))
        Lutaml::Model::Config.xml_adapter_type = payload.fetch("xml_adapter").to_sym
        lml = Lutaml::Model::Lml
        result = { "source_constants" => %w[LmlMappingFixtures LmlOrderFixtures LmlImportFixtures]
                     .select { |name| Object.const_defined?(name) } }
        module Imported; end

        bundle = lml::Importer.bundle(payload.fetch("bundle"))
        classes = lml.import_bundle(bundle, namespace: Imported)
        verified = lml.verify_materialization(bundle, namespace: Module.new.tap { |m| Object.const_set(:Second, m) })
        reexported = lml.export_bundle(classes.values_at(*bundle.roots))

        result["verified_checksum"] = verified.checksum
        result["verified_canonical"] = verified.canonical_json
        result["generated_model_names"] = reexported.models.values.map { |d| d["model"] }.sort
        result["generated_documents_renamed_equal"] =
          reexported.models.transform_keys { |k| k.delete_prefix("Imported::") }
            .transform_values { |d| JSON.parse(JSON.generate(d).gsub("Imported::", "")) } ==
          bundle.models.transform_values { |d| JSON.parse(JSON.generate(d)) }

        doc = classes.fetch("LmlMappingFixtures::Doc@default")
        result["doc"] = %w[xml json yaml].to_h do |format|
          [format, doc.public_send(:"from_#{format}", payload.dig("doc", format)).public_send(:"to_#{format}")]
        end
        para = classes.fetch("LmlOrderFixtures::Para@default")
        result["para"] = para.from_xml(payload.fetch("para")).to_xml
        kennel = classes.fetch("LmlImportFixtures::Kennel@default").from_json(payload.fetch("kennel"))
        result["kennel"] = kennel.to_json
        result["kennel_classes"] = kennel.animals.map(&:class).map(&:name)
        puts JSON.generate(result)
      RUBY
    end

    let(:para_xml) { "<p>one <em>two</em> three<b>x</b> <em>four</em><note>n</note> end</p>" }

    def run_child(payload)
      Dir.mktmpdir("lml-child") do |dir|
        path = File.join(dir, "payload.json")
        File.write(path, JSON.generate(payload))
        out, err, status = Open3.capture3(RbConfig.ruby, "-I#{File.join(repo_root, 'lib')}", "-e", child_script, path,
                                          chdir: repo_root)
        raise "child failed (#{status.exitstatus}): #{err}" unless status.success?

        JSON.parse(out.lines.last)
      end
    end

    it "imports, re-exports and verifies equal declarations and checksum, with equal behaviour" do
      source = doc_sample
      payload = {
        "bundle" => bundle.to_h,
        "xml_adapter" => "nokogiri",
        "doc" => { "xml" => source.to_xml, "json" => source.to_json, "yaml" => source.to_yaml },
        "oracle" => %w[xml json yaml].to_h do |format|
          text = source.public_send(:"to_#{format}")
          [format, LmlMappingFixtures::Doc.public_send(:"from_#{format}", text).public_send(:"to_#{format}")]
        end,
        "para" => para_xml,
        "kennel" => kennel_json,
      }
      result = run_child(payload)

      expect(result["source_constants"]).to eq([])
      expect(result["verified_checksum"]).to eq(bundle.checksum)
      expect(result["verified_canonical"]).to eq(bundle.canonical_json)
      expect(result["generated_documents_renamed_equal"]).to be(true)
      expect(result["generated_model_names"]).to all(start_with("Imported::"))
      expect(result["doc"]).to eq(payload["oracle"])
      expect(result["para"]).to eq(LmlOrderFixtures::Para.from_xml(para_xml).to_xml)
      expect(result["kennel"]).to eq(JSON.generate(JSON.parse(kennel_json)))
      expect(result["kennel_classes"]).to eq(%w[Imported::LmlImportFixtures::Dog Imported::LmlImportFixtures::Animal])
    end
  end
end
