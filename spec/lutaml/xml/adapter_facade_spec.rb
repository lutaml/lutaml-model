# frozen_string_literal: true

require "spec_helper"

# The moxml facade lane (#1224): moxml is the only XML selection lane;
# the engine is a deployment decision owned by Moxml::Config. Engine
# names remain accepted on the deprecated selection surface and resolve
# to their adapter classes; a process pin made by another gem can be
# undone through the unset API.
RSpec.describe "moxml facade lane" do
  let(:probe_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      xml do
        root "probe"
        map_element "name", to: :name
      end
    end
  end

  let(:instance_xml) { "<probe><name>facade</name></probe>" }

  around do |example|
    Lutaml::Model::AdapterResolver.reset!
    example.run
  ensure
    Lutaml::Model::AdapterResolver.reset!
  end

  it "is the resolved adapter by default" do
    expect(Lutaml::Model::Config.xml_adapter.name)
      .to eq("Lutaml::Xml::Adapter::MoxmlAdapter")
  end

  it "parses and serializes through the engine Moxml resolves" do
    parsed = probe_class.from_xml(instance_xml)
    expect(parsed.name).to eq("facade")
    expect(probe_class.new(name: "facade").to_xml).to include("<name>facade</name>")
  end

  it "is selectable explicitly as :moxml" do
    Lutaml::Model::Config.xml_adapter_type = :moxml

    expect(Lutaml::Model::Config.xml_adapter_type).to eq(:moxml)
    expect(Lutaml::Model::Config.xml_adapter.name)
      .to eq("Lutaml::Xml::Adapter::MoxmlAdapter")
    expect(probe_class.from_xml(instance_xml).name).to eq("facade")
  end

  it "accepts engine names on the deprecated surface and resolves their adapter classes" do
    expect do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end.to output(/DEPRECATED/).to_stderr

    expect(Lutaml::Model::Config.xml_adapter.name)
      .to eq("Lutaml::Xml::Adapter::NokogiriAdapter")
    expect(probe_class.from_xml(instance_xml).name).to eq("facade")
  end

  it "scopes engine names to the block and restores the facade after" do
    scoped = nil

    expect do
      Lutaml::Model::Config.with_adapter(xml: :leptris) do
        scoped = Lutaml::Model::Config.xml_adapter.name
        expect(probe_class.from_xml(instance_xml).name).to eq("facade")
      end
    end.to output(/DEPRECATED/).to_stderr

    expect(scoped).to eq("Lutaml::Xml::Adapter::LeptrisAdapter")
    expect(Lutaml::Model::Config.xml_adapter.name)
      .to eq("Lutaml::Xml::Adapter::MoxmlAdapter")
  end

  describe "the unset-pin API" do
    it "restores auto-detection after another gem's process pin" do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
      expect(Lutaml::Model::Config.xml_adapter.name)
        .to eq("Lutaml::Xml::Adapter::NokogiriAdapter")

      Lutaml::Model::Config.unset_xml_adapter_type

      expect(Lutaml::Model::Config.xml_adapter_type).to be_nil
      expect(Lutaml::Model::Config.xml_adapter.name)
        .to eq("Lutaml::Xml::Adapter::MoxmlAdapter")
    end

    it "is a no-op when nothing is pinned" do
      Lutaml::Model::Config.unset_xml_adapter_type

      expect(Lutaml::Model::Config.xml_adapter_type).to be_nil
      expect(Lutaml::Model::Config.xml_adapter.name)
        .to eq("Lutaml::Xml::Adapter::MoxmlAdapter")
    end
  end

  describe "rejects unknown types" do
    it "still rejects a type outside the lane and its engine aliases" do
      expect do
        Lutaml::Model::Config.xml_adapter_type = :sax
      end.to raise_error(ArgumentError, /Unknown adapter/)
    end
  end
end
