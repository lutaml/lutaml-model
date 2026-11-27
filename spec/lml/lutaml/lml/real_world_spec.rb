# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"
require "tempfile"

RSpec.describe "Real-world fixture parsing" do
  def wrap_in_diagram(content)
    "diagram Test {\n#{content}\n}"
  end

  def parse_fixture(path)
    content = File.read(path)
    content = wrap_in_diagram(content) unless content.strip.start_with?("diagram")
    file = Tempfile.new(%w[test .lutaml])
    file.write(content)
    file.rewind
    doc = Lutaml::Lml.parse(file)
    file.close!
    doc
  end

  def fixture_path(repo, name)
    File.expand_path("../../fixtures/real_world/#{repo}/#{name}", __dir__)
  end

  describe "basicdoc-models fixtures" do
    it "parses BasicDocument.lutaml" do
      doc = parse_fixture(fixture_path("basicdoc-models", "BasicDocument.lutaml"))
      expect(doc.classes.length).to eq(1)
      c = doc.classes.first
      expect(c.name).to eq("BasicDocument")
      expect(c.attributes.length).to be >= 3
      attr_names = c.attributes.map(&:name)
      expect(attr_names).to include("identifier", "bibdata", "sections")
    end

    it "parses BasicBlock.lutaml" do
      doc = parse_fixture(fixture_path("basicdoc-models", "BasicBlock.lutaml"))
      c = doc.classes.first
      expect(c.name).to eq("BasicBlock")
      expect(c.attributes.map(&:name)).to include("notes")
    end

    it "parses BasicSection.lutaml with cardinality" do
      doc = parse_fixture(fixture_path("basicdoc-models", "BasicSection.lutaml"))
      c = doc.classes.first
      expect(c.name).to eq("BasicSection")
      title_attr = c.attributes.find { |a| a.name == "title" }
      expect(title_attr).not_to be_nil
      expect(title_attr.type).to eq("TextElement")
      expect(title_attr.cardinality.min).to eq("0")
      expect(title_attr.cardinality.max).to eq("*")
    end

    it "parses TableBlock.lutaml with mixed cardinalities" do
      doc = parse_fixture(fixture_path("basicdoc-models", "TableBlock.lutaml"))
      c = doc.classes.first
      expect(c.name).to eq("TableBlock")
      head_attr = c.attributes.find { |a| a.name == "head" }
      body_attr = c.attributes.find { |a| a.name == "body" }
      expect(head_attr.cardinality.max).to eq("1")
      expect(body_attr.cardinality.max).to eq("*")
    end

    it "parses OrderedListType.lutaml as enum" do
      doc = parse_fixture(fixture_path("basicdoc-models", "OrderedListType.lutaml"))
      expect(doc.enums.length).to eq(1)
      expect(doc.enums.first.name).to eq("OrderedListType")
    end

    it "parses Uri.lutaml as data_type" do
      doc = parse_fixture(fixture_path("basicdoc-models", "Uri.lutaml"))
      expect(doc.data_types.length).to eq(1)
      expect(doc.data_types.first.name).to eq("Uri")
    end

    it "parses String.lutaml as primitive" do
      doc = parse_fixture(fixture_path("basicdoc-models", "String.lutaml"))
      expect(doc.classes.length).to eq(0)
      expect(doc.enums.length).to eq(0)
      expect(doc.data_types.length).to eq(0)
    end

    it "parses BibliographicItem.lutaml with stereotype" do
      doc = parse_fixture(fixture_path("basicdoc-models", "BibliographicItem.lutaml"))
      expect(doc.classes.length).to eq(1)
      expect(doc.classes.first.name).to eq("BibliographicItem")
    end

    it "parses AdmonitionType.lutaml as enum with values" do
      doc = parse_fixture(fixture_path("basicdoc-models", "AdmonitionType.lutaml"))
      expect(doc.enums.length).to eq(1)
      e = doc.enums.first
      expect(e.name).to eq("AdmonitionType")
      expect(e.attributes.length).to be >= 3
    end

    it "parses FigureBlock.lutaml" do
      doc = parse_fixture(fixture_path("basicdoc-models", "FigureBlock.lutaml"))
      expect(doc.classes.length).to eq(1)
      expect(doc.classes.first.name).to eq("FigureBlock")
    end
  end

  describe "metanorma-model-iso fixtures" do
    it "parses IsoStandardDocument.lutaml with stereotype attribute types" do
      doc = parse_fixture(fixture_path("metanorma-model-iso", "IsoStandardDocument.lutaml"))
      c = doc.classes.first
      expect(c.name).to eq("IsoStandardDocument")
      term_attr = c.attributes.find { |a| a.name == "termSources" }
      expect(term_attr).not_to be_nil
      expect(term_attr.type).to eq("Citation")
      expect(term_attr.cardinality.max).to eq("*")
    end

    it "parses IsoBibDataExtensionType.lutaml" do
      doc = parse_fixture(fixture_path("metanorma-model-iso", "IsoBibDataExtensionType.lutaml"))
      c = doc.classes.first
      expect(c.name).to eq("IsoBibDataExtensionType")
      expect(c.attributes.length).to be >= 5
      ft_attr = c.attributes.find { |a| a.name == "fast-track" }
      expect(ft_attr).not_to be_nil
    end

    it "parses IsoAdmonitionType.lutaml as enum" do
      doc = parse_fixture(fixture_path("metanorma-model-iso", "IsoAdmonitionType.lutaml"))
      expect(doc.enums.length).to eq(1)
      expect(doc.enums.first.name).to eq("IsoAdmonitionType")
    end

    it "parses IsoSections.lutaml" do
      doc = parse_fixture(fixture_path("metanorma-model-iso", "IsoSections.lutaml"))
      expect(doc.classes.length).to eq(1)
      expect(doc.classes.first.name).to eq("IsoSections")
    end

    it "parses IsoTerm.lutaml" do
      doc = parse_fixture(fixture_path("metanorma-model-iso", "IsoTerm.lutaml"))
      expect(doc.classes.length).to eq(1)
      expect(doc.classes.first.name).to eq("IsoTerm")
    end

    it "parses StandardDocument.lutaml with stereotype" do
      doc = parse_fixture(fixture_path("metanorma-model-iso", "StandardDocument.lutaml"))
      expect(doc.classes.length).to eq(1)
      expect(doc.classes.first.name).to eq("StandardDocument")
    end

    it "parses StandardBibDataExtensionType.lutaml" do
      doc = parse_fixture(fixture_path("metanorma-model-iso", "StandardBibDataExtensionType.lutaml"))
      c = doc.classes.first
      expect(c.name).to eq("StandardBibDataExtensionType")
    end
  end

  describe "batch smoke test" do
    it "parses all basicdoc-models real-world fixtures" do
      dir = File.expand_path("../../fixtures/real_world/basicdoc-models", __dir__)
      Dir.glob("#{dir}/*.lutaml").each do |path|
        expect { parse_fixture(path) }.not_to raise_error,
          "Failed to parse #{File.basename(path)}"
      end
    end

    it "parses all metanorma-model-iso real-world fixtures" do
      dir = File.expand_path("../../fixtures/real_world/metanorma-model-iso", __dir__)
      Dir.glob("#{dir}/*.lutaml").each do |path|
        expect { parse_fixture(path) }.not_to raise_error,
          "Failed to parse #{File.basename(path)}"
      end
    end
  end

  describe "ModelCompiler with real-world fixtures" do
    it "compiles BasicDocument into instantiable classes" do
      nil
      file = Tempfile.new(%w[test .lutaml])
      content = File.read(fixture_path("basicdoc-models", "BasicSection.lutaml"))
      file.write(wrap_in_diagram(content))
      file.rewind
      result = Lutaml::Lml.compile(file)

      expect(result).to have_key("BasicSection")
      section = result["BasicSection"]
      obj = section.new("title" => "Test Section", "id" => "sec-1")
      expect(obj.id).to eq("sec-1")
      file.close!
    end
  end
end
