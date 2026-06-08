# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema/definitions"
require "lutaml/model/schema/renderers/namespace"

RSpec.describe Lutaml::Model::Schema::Renderers::Namespace do
  let(:defs) { Lutaml::Model::Schema::Definitions }

  it "renders a namespace class with uri and prefix_default" do
    spec = defs::Namespace.new(
      class_name: "ExampleNs",
      uri: "http://example.com/ns",
      prefix_default: "ex",
    )

    output = described_class.render(spec)

    expect(output).to include("class ExampleNs < Lutaml::Xml::W3c::XmlNamespace")
    expect(output).to include(%(uri "http://example.com/ns"))
    expect(output).to include(%(prefix_default "ex"))
  end

  it "wraps in module when module_namespace is supplied" do
    spec = defs::Namespace.new(
      class_name: "Inner",
      uri: "http://example.com/inner",
      prefix_default: nil,
    )

    output = described_class.render(spec, module_namespace: "Mod::Sub")

    expect(output).to include("module Mod")
    expect(output).to include("module Sub")
  end
end
