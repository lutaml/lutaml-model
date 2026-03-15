# frozen_string_literal: true

require_relative "spec_helper"

LOCATIONS = {
  omml_schema: "https://raw.githubusercontent.com/t-yuki/ooxml-xsd/refs/heads/master",
  "metaschema-meta-constraints": "spec/lutaml/fixtures",
  "metaschema-markup-multiline": "spec/lutaml/fixtures",
  "metaschema-prose-module": "spec/lutaml/fixtures",
  "metaschema-markup-line": "spec/lutaml/fixtures",
  metaschema: "spec/lutaml/fixtures",
  "unitsml-v1.0-csd03": nil,
}.freeze

RSpec.describe Lutaml::Xml::Schema::Xsd do
  subject(:parsed_schema) { described_class.parse(schema, location: location) }

  Dir.glob(File.expand_path("fixtures/*.xsd", __dir__)).each do |input_file|
    rel_path = Pathname.new(input_file).relative_path_from(Pathname.new(__dir__)).to_s

    context "when parsing #{rel_path}" do
      let(:schema) { File.read(input_file) }
      let(:location) { LOCATIONS[File.basename(input_file, ".xsd").to_sym] }

      it "matches a Lutaml::Model::Schema object" do
        expect(parsed_schema).to be_a(Lutaml::Xml::Schema::Xsd::Schema)
      end

      it "matches count of direct child elements of the root" do
        expected_counts = {
          imports: /<\w+:import /,
          includes: /<\w+:include /,
          group: /<\w+:group name=/,
          simple_type: /<\w+:simpleType /,
          element: /^\s{0,2}<\w+:element /,
          complex_type: /<\w+:complexType /,
        }
        expected_counts.each_pair do |key, regex|
          value = parsed_schema.send(key)
          count = value.nil? ? 0 : value.count
          expect(count).to eql(schema.scan(regex).count)
        end
      end

      it "matches parsed schema to xml with the input" do
        processed_xml = parsed_schema.to_xml
        expect(processed_xml).to be_xml_equivalent_to(schema)
      end
    end
  end
end
