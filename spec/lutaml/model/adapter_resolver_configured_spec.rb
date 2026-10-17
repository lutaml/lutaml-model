# frozen_string_literal: true

require "spec_helper"
require "open3"

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

  # Runs in a subprocess: whether the engine is already loaded is a
  # process-global fact, so any in-process assertion would depend on
  # spec file order (the yeptris adapter faces load it).
  it "does not load the optional yeptris engine when a standard adapter is configured" do
    probe = <<~RUBY
      require "lutaml/model"

      Lutaml::Model::Config.configure do |config|
        config.yaml_adapter_type = :standard
        config.json_adapter_type = :standard
      end

      adapter_yaml = Lutaml::Model::AdapterResolver.adapter_for(:yaml)
      adapter_json = Lutaml::Model::AdapterResolver.adapter_for(:json)

      # Parsing through the configured adapters must likewise stay on
      # the standard engines.
      adapter_yaml.parse("a: 1")
      adapter_json.parse('{"a":1}')

      exit(Object.const_defined?(:Yeptris) ? 1 : 0)
    RUBY

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", "lib", "-e", probe)
    expect(status).to be_success, stderr
  end

  describe "plan lane defaults" do
    it "ships the ordered plan lane on, floored to the memo-capable engine" do
      # leptris#1743 (exponential flatten on diamond-shared plan
      # graphs) shipped its identity-memo flatten_plan in 1.9.366.2;
      # the MIN_LEPTRIS_VERSION floor keeps memo-less engines on the
      # interpretive path, so the default-on lane is safe.
      expect(Lutaml::Model::Config.instance.xml_plan_ordered_path).to be(true)
    end
  end
end
