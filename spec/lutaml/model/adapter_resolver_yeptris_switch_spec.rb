# frozen_string_literal: true

require "spec_helper"

# The yeptris YAML engine is preferred whenever it answers a probe,
# matching the XML lane's prefer-if-available contract: the platform
# parity fixes for plain-scalar materialization landed in yeptris
# 0.6.57+ (leptris/yeptris#863). LUTAML_YAML=standard opts a host out;
# FONTIST_YAML=yeptris stays honored as the legacy opt-in spelling
# fontist and lutaml-store already ship (#1115).
RSpec.describe "yeptris engine preference switch" do
  around do |example|
    old = ENV.to_h.slice("LUTAML_YAML", "FONTIST_YAML")
    ENV.delete("LUTAML_YAML")
    ENV.delete("FONTIST_YAML")
    Lutaml::Model::AdapterResolver.reset!
    example.run
    Lutaml::Model::AdapterResolver.reset!
    old.each { |k, v| ENV[k] = v }
  end

  def yeptris_engine_available?
    return false if RUBY_ENGINE == "opal"

    Lutaml::Model::Utils.safe_load("yeptris", :Yeptris)
  end

  it "prefers yeptris by default when the engine is available" do
    skip "yeptris engine not available on this platform" unless
      yeptris_engine_available?

    expect(Lutaml::Model::Config.adapter_for(:yaml))
      .to be(Lutaml::Yaml::Adapter::YeptrisAdapter)
  end

  it "serves the standard adapter with LUTAML_YAML=standard" do
    ENV["LUTAML_YAML"] = "standard"

    expect(Lutaml::Model::Config.adapter_for(:yaml))
      .not_to be(Lutaml::Yaml::Adapter::YeptrisAdapter)
  end

  it "honors the legacy FONTIST_YAML spelling" do
    ENV["FONTIST_YAML"] = "yeptris"

    if yeptris_engine_available?
      expect(Lutaml::Model::Config.adapter_for(:yaml))
        .to be(Lutaml::Yaml::Adapter::YeptrisAdapter)
    else
      expect(Lutaml::Model::Config.adapter_for(:yaml))
        .not_to be(Lutaml::Yaml::Adapter::YeptrisAdapter)
    end
  end

  # leptris/yeptris#863: plain string scalars must materialize as
  # strings on every platform build; the 0.6.53 linux build turned
  # them into single-element Arrays, corrupting checksum consumers.
  it "parses plain string scalars as strings through the engine" do
    skip "yeptris engine not available on this platform" unless
      yeptris_engine_available?

    parsed = Lutaml::Yaml::Adapter::YeptrisAdapter.parse(<<~YAML)
      resources:
        andale32.exe:
          sha256: 0524fe42951adc3a7eb870e32f0920313c71f170c859b5f770d82b4ee111e970
    YAML

    expect(
      parsed["resources"]["andale32.exe"]["sha256"],
    ).to be_a(String)
  end
end
