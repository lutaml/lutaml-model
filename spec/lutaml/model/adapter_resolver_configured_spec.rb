# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::AdapterResolver, ".adapter_for with a configured type" do
  after do
    Lutaml::Model::Config.configure do |config|
      config.xml_adapter_type = :nokogiri
      config.yaml_adapter_type = :standard
      config.json_adapter_type = :standard
    end
  end

  it "resolves the configured adapter without running auto-detection" do
    Lutaml::Model::Config.configure do |config|
      config.json_adapter_type = :standard
    end

    adapter = described_class.adapter_for(:json)

    expect(described_class.configured_type(:json)).to eq(:standard)
    expect(adapter.name).to include("Json::Standard")
  end

  it "does not load the optional yeptris engine when a standard adapter is configured" do
    skip "yeptris already loaded by an earlier spec" if Object.const_defined?(:Yeptris)

    Lutaml::Model::Config.configure do |config|
      config.yaml_adapter_type = :standard
      config.json_adapter_type = :standard
    end

    described_class.adapter_for(:yaml)
    described_class.adapter_for(:json)

    expect(Object.const_defined?(:Yeptris)).to be(false)
  end
end
