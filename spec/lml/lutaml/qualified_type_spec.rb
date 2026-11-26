# frozen_string_literal: true

require "spec_helper"
require_relative "../lml_spec_setup"

RSpec.describe "namespace-qualified attribute types" do
  it "parses XSD-qualified types such as xsd:date" do
    src = <<~LML
      diagram Test {
        class Session {
          +number: String[0..1]
          +session-date: xsd:date[0..1]
          +adopted: xsd:gYear[0..1]
        }
      }
    LML

    require "tempfile"
    file = Tempfile.new(["qualified", ".lutaml"])
    file.write(src)
    file.rewind
    doc = Lutaml::Lml.parse(file)
    file.close
    file.unlink

    session = doc.classes.find { |c| c.name == "Session" }
    expect(session).not_to be_nil
    attrs = session.attributes
    expect(attrs.map(&:name)).to contain_exactly("number", "session-date", "adopted")
    expect(attrs.find { |a| a.name == "session-date" }.type).to eq("xsd:date")
    expect(attrs.find { |a| a.name == "adopted" }.type).to eq("xsd:gYear")
  end
end
