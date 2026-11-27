# frozen_string_literal: true

require "spec_helper"

# The documented save/restore contract for the process-global adapter
# setting writes the saved reader value back through the writer
# (uniword's with_boot_adapter shape, #1234). The saved value is nil
# when no pin was set — the unset delegate form — and the writer must
# accept it as "return to auto-detection" instead of raising.
RSpec.describe "adapter type unset/restore (nil delegate form, #1234)" do
  # Save/restore the pins themselves: a blanket AdapterResolver.reset!
  # here wipes the resolution caches mid-suite and flips downstream
  # lanes' engines (rdf/turtle suites run after this file).
  around do |example|
    saved_xml = Lutaml::Model::Config.xml_adapter_type
    saved_json = Lutaml::Model::Config.json_adapter_type
    saved_yaml = Lutaml::Model::Config.yaml_adapter_type
    Lutaml::Model::Config.unset_xml_adapter_type
    Lutaml::Model::Config.unset_json_adapter_type
    Lutaml::Model::Config.unset_yaml_adapter_type
    example.run
  ensure
    Lutaml::Model::Config.xml_adapter_type = saved_xml
    Lutaml::Model::Config.json_adapter_type = saved_json
    Lutaml::Model::Config.yaml_adapter_type = saved_yaml
  end

  it "accepts nil from the reader as a restore to the unset form" do
    saved = Lutaml::Model::Config.xml_adapter_type
    expect(saved).to be_nil

    Lutaml::Model::Config.xml_adapter_type = :nokogiri
    expect(Lutaml::Model::Config.xml_adapter_type).to eq(:nokogiri)

    Lutaml::Model::Config.xml_adapter_type = saved

    expect(Lutaml::Model::Config.xml_adapter_type).to be_nil
    expect(Lutaml::Model::Config.xml_adapter).not_to be_nil
  end

  it "exposes the unset operation and restores auto-detection" do
    Lutaml::Model::Config.xml_adapter_type = :leptris

    Lutaml::Model::Config.unset_xml_adapter_type

    expect(Lutaml::Model::Config.xml_adapter_type).to be_nil
    expect(Lutaml::Model::Config.xml_adapter).not_to be_nil
  end

  it "clears only the pinned format" do
    Lutaml::Model::Config.configure do |config|
      config.xml_adapter_type = :nokogiri
      config.json_adapter_type = :standard
    end

    Lutaml::Model::Config.unset_xml_adapter_type

    expect(Lutaml::Model::Config.xml_adapter_type).to be_nil
    expect(Lutaml::Model::Config.json_adapter_type).to eq(:standard)
  end
end
