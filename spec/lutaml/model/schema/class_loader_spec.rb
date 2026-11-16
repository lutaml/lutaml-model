# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::ClassLoader do
  let(:definition) do
    Lutaml::Model::Schema::Definitions::Model.new(
      class_name: "Entry",
      xml_root: Lutaml::Model::Schema::Definitions::XmlRoot.new(
        kind: :element, name: "entry",
      ),
    )
  end

  let(:entry) do
    Lutaml::Model::Schema::CompiledOutput::Entry.new(
      "Entry", definition, :model
    )
  end

  it "loads generated classes from a nested namespace directory" do
    stub_const("ClassLoaderRegression", Module.new)

    output = Lutaml::Model::Schema::CompiledOutput.new(
      entries: [entry],
      module_namespace: "ClassLoaderRegression::Nested",
    )

    expect { described_class.load(output) }.not_to raise_error

    expect(ClassLoaderRegression::Nested::Entry.ancestors)
      .to include(Lutaml::Model::Serialize::ClassMethods)
  end

  it "keeps single-level namespace autoloads working" do
    registry = Lutaml::Model::Schema::RegistryGenerator.generate(
      [entry], module_namespace: "SingleLevel"
    )

    expect(registry).to include('File.join(__dir__, "singlelevel", "entry")')
  end

  it "keeps flat class output free of a registry namespace" do
    registry = Lutaml::Model::Schema::RegistryGenerator.generate(
      [entry], module_namespace: nil
    )

    expect(registry).to be_nil
  end
end
