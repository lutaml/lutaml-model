# frozen_string_literal: true

require "spec_helper"
require "tempfile"

# RS 3001 conformance corpus: the normative examples of
# lutaml-lang.adoc (RS 3001), vendored verbatim. Every example must
# parse and build a document. Constructs from the extension track
# (serialization mapping blocks) are intentionally absent here.
RS3001_CORPUS = Dir.glob(File.expand_path("../../fixtures/rs3001/*.lml", __dir__)).freeze

RSpec.describe "RS 3001 conformance corpus" do
  # Vacuity guard: this glob once resolved to a nonexistent directory and
  # the suite silently ran zero corpus examples. Every vendored fixture
  # must be covered.
  it "covers the full vendored corpus" do
    expect(RS3001_CORPUS.size).to be > 20
  end

  RS3001_CORPUS.each do |path|
    name = File.basename(path)

    it "parses and builds #{name}" do
      doc = Lutaml::Lml.parse_document(StringIO.new(File.read(path)))
      expect(doc).to be_a(Lutaml::Lml::Document)
    end
  end

  describe "semantic spot checks" do
    it "bakes the package enum values shorthand into members" do
      doc = Lutaml::Lml.parse_document(
        StringIO.new(File.read("spec/lml/fixtures/rs3001/03_package_ceramics.lml")),
      )
      profile = doc.packages.first.enums.first
      expect(profile.attributes.map(&:name)).to eq(%w[low medium high])
      tile = doc.packages.first.classes.first
      expect(tile.attributes.map(&:name)).to eq(%w[dimensions firing_profile])
    end

    it "captures the pattern constraint" do
      doc = Lutaml::Lml.parse_document(
        StringIO.new(File.read("spec/lml/fixtures/rs3001/07_attribute_pattern.lml")),
      )
      color = doc.classes.first.attributes.first
      expect(color.pattern).to eq('\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z')
    end

    it "compiles colon-form defaults" do
      file = Tempfile.new(%w[g .lml])
      begin
        file.write(File.read("spec/lml/fixtures/rs3001/08_attribute_default_colon.lml"))
        file.rewind
        compiler = Lutaml::Lml::ModelCompiler.new
        compiler.compile(file)
        glaze = compiler.compiled_classes["Glaze"]
        inst = glaze.new
        expect(inst.color).to eq("Clear")
        expect(inst.temperature).to eq(1050)
      ensure
        file.close!
      end
    end

    it "resolves collection-qualified references and names the collection" do
      doc = Lutaml::Lml.parse_document(
        StringIO.new(File.read("spec/lml/fixtures/rs3001/13_instances_collection_refs.lml")),
      )
      expect(doc.instances.name).to eq("Glazes")
      tile = doc.instances.instances.find { |i| i.name == "tile_002" }
      expect(tile).not_to be_nil
      violations = Lutaml::Lml::Validator.violations(doc)
      expect(violations).to be_empty
    end

    it "keeps values-as-instances data on members" do
      doc = Lutaml::Lml.parse_document(
        StringIO.new(File.read("spec/lml/fixtures/rs3001/11_enum_values_as_instances.lml")),
      )
      matte = doc.enums.first.attributes.find { |a| a.name == "matte" }
      expect(matte).not_to be_nil
    end
  end
end
