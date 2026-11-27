# frozen_string_literal: true

require "lutaml/model"
require "lutaml/model/lml/document_validator"
require_relative "../../support/lml_export_fixtures"
require_relative "../../support/lml_order_fixtures"
require_relative "../../support/lml_graph_fixtures"

# Drift guard: whatever the portable exporter emits, the v2
# DocumentValidator (and so every reader mirroring it) must accept, and
# whatever the exporter cannot express it must refuse by name.
RSpec.describe "LML exporter output vs DocumentValidator" do
  let(:validator) { Lutaml::Model::Lml::DocumentValidator }

  it "covers a non-trivial set of fixture models" do
    expect(LmlExportFixtures.exportable_models.size).to be >= 15
  end

  LmlExportFixtures.exportable_models.each do |klass|
    if LmlExportFixtures::REFUSED.key?(klass.name)
      it "#{klass.name}: refused by name, never emitted" do
        expect { Lutaml::Model::Lml::Exporter.project(klass) }
          .to raise_error(Lutaml::Model::Lml::RejectedError) { |e|
            expect(e.reason).to eq(LmlExportFixtures::REFUSED.fetch(klass.name))
          }
      end
    else
      it "#{klass.name}: projected document validates as v2" do
        document = Lutaml::Model::Lml::Exporter.project(klass)
        expect { validator.validate!(document, kind: :document) }.not_to raise_error
      end
    end
  end

  describe "graph fixtures" do
    it "every projected graph document validates as v2" do
      projector = LmlGraphFixtures.projector
      [LmlGraphFixtures::Node, LmlGraphFixtures::Left, LmlGraphFixtures::Right,
       LmlGraphFixtures::Leaf, LmlGraphFixtures::Shape, LmlGraphFixtures::Circle,
       LmlGraphFixtures::Square].each do |klass|
        document = projector.call(klass, "default")
        expect { validator.validate!(document, kind: :document) }.not_to raise_error
      end
    end
  end

  describe "contract decisions" do
    def project(klass) = Lutaml::Model::Lml::Exporter.project(klass)

    it "carries format-level ordered, mixed_content and sequence" do
      expect(project(LmlOrderFixtures::Transport).dig("mappings", "xml", "ordered")).to be(true)
      expect(project(LmlOrderFixtures::Para).dig("mappings", "xml", "mixed_content")).to be(true)
      sequence = project(LmlExportFixtures::SequencedShape).dig("mappings", "xml", "sequence")
      expect(sequence.map { |g| [g["kind"], g["members"].map { |m| m["name"] }] })
        .to eq([["sequence", [["a"], ["b"]]]])
    end

    it "projects a choice nested in a sequence with its bounds" do
      sequence = project(LmlExportFixtures::ChoiceSequence).dig("mappings", "xml", "sequence")
      kinds = sequence.first["members"].map { |m| m["kind"] }
      choice = sequence.first["members"].find { |m| m["kind"] == "choice" }
      expect(kinds).to eq(%w[element choice])
      expect([choice["min"], choice["max"], choice["members"].map { |m| m["to"] }])
        .to eq([1, 1, %w[b c]])
    end

    it "keeps child_mappings, root_mappings and polymorphic data (not dropped)" do
      expect(project(LmlExportFixtures::ChildMapped).dig("mappings", "json", "rules", 0, "child_mappings"))
        .to eq("id" => "key", "path" => %w[path link])
      expect(project(LmlExportFixtures::RootMapped).dig("mappings", "json", "rules", 0, "root_mappings"))
        .to eq("name" => "key", "styles" => "value")
      expect(project(LmlExportFixtures::PolyBase).dig("mappings", "xml", "rules", 0, "polymorphic_map"))
        .to eq("basic" => "LmlExportFixtures::PolyBase")
      expect(project(LmlExportFixtures::PolyHolder).dig("mappings", "xml", "rules", 0, "discriminator"))
        .to eq("attribute" => "type", "cases" => { "base" => "LmlExportFixtures::PolyBase@default" })
    end

    it "does not emit the in-memory hash format for key_value models" do
      mappings = project(LmlExportFixtures::KeyValueOnly)["mappings"]
      expect(mappings.keys).to include("json", "yaml")
      expect(mappings.keys).not_to include("hash")
    end

    it "rejects a non-boolean ordered flag and a malformed sequence" do
      doc = project(LmlOrderFixtures::Transport)
      bad = Marshal.load(Marshal.dump(doc))
      bad["mappings"]["xml"]["ordered"] = "yes"
      expect { validator.validate!(bad, kind: :document) }
        .to raise_error(Lutaml::Model::Lml::RejectedError)
      bad = Marshal.load(Marshal.dump(doc))
      bad["mappings"]["xml"]["sequence"] = [1]
      expect { validator.validate!(bad, kind: :document) }
        .to raise_error(Lutaml::Model::Lml::RejectedError)
    end
  end
end
