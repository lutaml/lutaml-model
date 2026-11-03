# frozen_string_literal: true

require_relative "../../../../spec_helper"
require "tmpdir"
require "lutaml/xml/schema/xsd"

# lutaml-model#1087: schemaLocation on xs:include / xs:import /
# xs:redefine is a hint (XSD 1.0 §4.2.3). An unresolvable hint warns
# and the assembly continues without the referenced components — the
# W3C suite's expected reading (msData anyURI_a001 et al.) — instead
# of raising Schema file not found.
RSpec.describe "Xsd unresolvable schemaLocation hints" do
  let(:xsd) do
    <<~XSD
      <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <xsd:include schemaLocation="0"/>
        <xsd:import schemaLocation="123" namespace="2"/>
        <xsd:redefine schemaLocation="123"/>
      </xsd:schema>
    XSD
  end

  it "warns for each unresolvable hint and still parses" do
    doc = nil
    Dir.mktmpdir do |dir|
      expect do
        doc = Lutaml::Xml::Schema::Xsd.parse(xsd, location: dir)
      end.to output(/Schema file not found/).to_stderr
    end

    expect(doc.includes.first.schema_path).to eq("0")
    expect(doc.imports.first.schema_path).to eq("123")
    expect(doc.redefine.first.schema_path).to eq("123")
  end

  it "warns for the unresolvable include" do
    expect do
      parse_with_warnings
    end.to output(%r{original location: 0\)}).to_stderr
  end

  it "warns for the unresolvable import" do
    # xs:redefine's schemaLocation resolves through the composition
    # route (schema_path_without_base), not at parse time — the
    # parse-time fetches are the include and the import.
    expect do
      parse_with_warnings
    end.to output(%r{original location: 123\)}).to_stderr
  end

  private

  def parse_with_warnings
    Dir.mktmpdir do |dir|
      Lutaml::Xml::Schema::Xsd.parse(xsd, location: dir)
    end
  end
end
