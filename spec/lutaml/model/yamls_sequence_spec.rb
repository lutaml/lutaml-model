require "spec_helper"
require_relative "../../fixtures/geolexica_v2_concept"

RSpec.describe "YAMLS sequence (heterogeneous YAML stream)" do
  let(:v2_yaml) do
    <<~YAMLS
      ---
      data:
        identifier: 3.5.8.8
        localized_concepts:
          eng: fbe1444a-7c11-555e-bb1b-680a4e6f2502
      id: 0171b198-d068-53d9-8741-fb87e6755d62

      ---
      data:
        definition:
        - content: characteristic of a financial model that requires users to enter into an agreement prior to receiving services
        examples: []
        notes:
        - content: The agreement can be associated with fees.
        - content: The agreement can be minimal.
        sources:
        - origin:
            ref: ISO/TS 14812:2022
            locality:
              type: clause
              reference_from: 3.5.8.8
            link: https://www.iso.org/standard/79779.html
          type: authoritative
        terms:
        - type: expression
          normative_status: preferred
          designation: membership-based
        language_code: eng
        entry_status: valid
      id: fbe1444a-7c11-555e-bb1b-680a4e6f2502
    YAMLS
  end

  describe "parsing heterogeneous YAML stream" do
    subject(:managed) { GeolexicaV2::ManagedConcept.from_yamls(v2_yaml) }

    it "parses document 0 as ConceptIndex" do
      expect(managed.index).to be_a(GeolexicaV2::ConceptIndex)
      expect(managed.index.id).to eq("0171b198-d068-53d9-8741-fb87e6755d62")
    end

    it "parses ConceptIndex data fields" do
      expect(managed.index.data.identifier).to eq("3.5.8.8")
      expect(managed.index.data.localized_concepts).to eq(
        "eng" => "fbe1444a-7c11-555e-bb1b-680a4e6f2502",
      )
    end

    it "parses document 1+ as LocalizedConcept collection" do
      expect(managed.localized).to be_an(Array)
      expect(managed.localized.length).to eq(1)
    end

    it "parses LocalizedConcept fields" do
      lc = managed.localized.first
      expect(lc).to be_a(GeolexicaV2::LocalizedConcept)
      expect(lc.id).to eq("fbe1444a-7c11-555e-bb1b-680a4e6f2502")
      expect(lc.data.language_code).to eq("eng")
      expect(lc.data.entry_status).to eq("valid")
    end

    it "parses LocalizedConcept definition sequence" do
      lc = managed.localized.first
      expect(lc.data.definition).to be_an(Array)
      expect(lc.data.definition.first.content).to include("characteristic of a financial model")
    end

    it "parses LocalizedConcept terms sequence" do
      lc = managed.localized.first
      expect(lc.data.terms.first.designation).to eq("membership-based")
      expect(lc.data.terms.first.type).to eq("expression")
    end

    it "parses LocalizedConcept notes sequence" do
      lc = managed.localized.first
      expect(lc.data.notes.length).to eq(2)
      expect(lc.data.notes.first.content).to eq("The agreement can be associated with fees.")
    end

    it "parses LocalizedConcept sources with nested origin" do
      lc = managed.localized.first
      source = lc.data.sources.first
      expect(source.type).to eq("authoritative")
      expect(source.origin.ref).to eq("ISO/TS 14812:2022")
      expect(source.origin.locality.type).to eq("clause")
      expect(source.origin.locality.reference_from).to eq("3.5.8.8")
    end

    it "parses empty examples array" do
      lc = managed.localized.first
      expect(lc.data.examples).to eq([])
    end
  end

  describe "serialization" do
    subject(:managed) { GeolexicaV2::ManagedConcept.from_yamls(v2_yaml) }

    it "serializes back to a YAML stream with 2 documents" do
      output = managed.to_yamls
      docs = output.split(/^---\s*$/).reject do |d|
        d.strip.empty?
      end.map { |d| YAML.safe_load("---\n#{d}") }
      expect(docs.length).to eq(2)
    end

    it "round-trips index data" do
      output = managed.to_yamls
      managed2 = GeolexicaV2::ManagedConcept.from_yamls(output)

      expect(managed2.index.id).to eq(managed.index.id)
      expect(managed2.index.data.identifier).to eq(managed.index.data.identifier)
      expect(managed2.index.data.localized_concepts).to eq(managed.index.data.localized_concepts)
    end

    it "round-trips localized concept data" do
      output = managed.to_yamls
      managed2 = GeolexicaV2::ManagedConcept.from_yamls(output)

      lc = managed2.localized.first
      expect(lc.id).to eq(managed.localized.first.id)
      expect(lc.data.language_code).to eq("eng")
      expect(lc.data.definition.first.content).to include("characteristic of a financial model")
      expect(lc.data.terms.first.designation).to eq("membership-based")
      expect(lc.data.notes.length).to eq(2)
      expect(lc.data.sources.first.origin.ref).to eq("ISO/TS 14812:2022")
    end

    it "round-trips empty arrays" do
      output = managed.to_yamls
      managed2 = GeolexicaV2::ManagedConcept.from_yamls(output)
      expect(managed2.localized.first.data.examples).to eq([])
    end
  end

  describe "parsing actual geolexica v2 file" do
    let(:v2_file) do
      File.read(File.expand_path("../../fixtures/geolexica_v2_sample.yaml",
                                 __dir__))
    end

    it "parses the real geolexica v2 file" do
      managed = GeolexicaV2::ManagedConcept.from_yamls(v2_file)
      expect(managed.index.data.identifier).to eq("3.5.8.8")
      expect(managed.localized.first.data.language_code).to eq("eng")
      expect(managed.localized.first.data.terms.first.designation).to eq("membership-based")
    end
  end

  describe "YAMLS sequence with 3 documents" do
    let(:three_doc_yaml) do
      <<~YAMLS
        ---
        data:
          identifier: 3.7.1.5
          localized_concepts:
            eng: doc1-eng-id
        id: doc0-id

        ---
        data:
          definition:
          - content: First localized concept
          examples: []
          notes: []
          sources: []
          terms:
          - type: expression
            normative_status: preferred
            designation: term one
          language_code: eng
          entry_status: valid
        id: doc1-eng-id

        ---
        data:
          definition:
          - content: Second localized concept (French)
          examples: []
          notes: []
          sources: []
          terms:
          - type: expression
            normative_status: preferred
            designation: terme un
          language_code: fra
          entry_status: valid
        id: doc1-fra-id
      YAMLS
    end

    it "parses 1 index + 2 localized concepts" do
      managed = GeolexicaV2::ManagedConcept.from_yamls(three_doc_yaml)
      expect(managed.index.data.identifier).to eq("3.7.1.5")
      expect(managed.localized.length).to eq(2)
      expect(managed.localized[0].data.language_code).to eq("eng")
      expect(managed.localized[1].data.language_code).to eq("fra")
    end

    it "round-trips 3 documents" do
      managed = GeolexicaV2::ManagedConcept.from_yamls(three_doc_yaml)
      output = managed.to_yamls
      managed2 = GeolexicaV2::ManagedConcept.from_yamls(output)

      expect(managed2.localized.length).to eq(2)
      expect(managed2.localized[0].data.terms.first.designation).to eq("term one")
      expect(managed2.localized[1].data.terms.first.designation).to eq("terme un")
    end
  end

  describe "ManagedConceptCollection (directory of v2 files)" do
    let(:fixture_dir) { File.expand_path("../../fixtures", __dir__) }
    let(:v2_files) do
      %w[geolexica_v2_sample.yaml geolexica_v2_sample2.yaml].map do |f|
        File.join(fixture_dir, f)
      end
    end

    it "loads each v2 file as a separate ManagedConcept" do
      concepts = v2_files.map do |f|
        GeolexicaV2::ManagedConcept.from_yamls(File.read(f))
      end
      expect(concepts.length).to eq(2)
      concepts.each do |concept|
        expect(concept.index).to be_a(GeolexicaV2::ConceptIndex)
        expect(concept.localized).to be_an(Array)
        expect(concept.localized).not_to be_empty
      end
    end

    it "can be assembled into a collection manually" do
      concepts = v2_files.map do |f|
        GeolexicaV2::ManagedConcept.from_yamls(File.read(f))
      end
      collection = GeolexicaV2::ManagedConceptCollection.new(concepts)
      expect(collection.size).to eq(2)
      expect(collection.first.index).to be_a(GeolexicaV2::ConceptIndex)
    end
  end
end
