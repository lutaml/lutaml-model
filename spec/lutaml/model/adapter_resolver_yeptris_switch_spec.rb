# frozen_string_literal: true

require "spec_helper"

# The yeptris YAML engine is preferred whenever it answers a probe,
# matching the XML lane's prefer-if-available contract: the platform
# parity fixes for plain-scalar materialization landed in yeptris
# 0.6.57+ (leptris/yeptris#863). Adapter choice is centralized in
# Config (yaml_adapter_type= / json_adapter_type=) — a host that wants
# a different engine pins it there, and the detection path consults no
# environment variables.
RSpec.describe "yeptris engine preference" do
  # Reset only the key-value resolution entries: the explicit pins, the
  # lazy detection cache, and the resolved-class cache. The resolver-wide
  # reset! would also wipe the adapters other specs configured (the XML
  # lane in particular), silently re-detecting a different runtime for
  # the rest of the process.
  def with_fresh_kv_resolution
    resolver = Lutaml::Model::AdapterResolver
    types = resolver.__send__(:configured_types)
    detected = resolver.__send__(:detected_types)
    detected_flags = resolver.__send__(:detected_formats)
    resolved = resolver.__send__(:resolved)
    saved = types.slice(:yaml, :json)
    saved_detected = detected.slice(:yaml, :json)
    saved_resolved = resolved.slice(:yaml, :json)
    %i[yaml json].each do |format|
      types.delete(format)
      detected.delete(format)
      detected_flags.delete(format)
      resolved.delete(format)
    end
    yield
  ensure
    %i[yaml json].each do |format|
      types.delete(format)
      detected.delete(format)
      detected_flags.delete(format)
      resolved.delete(format)
    end
    saved.each { |format, type| types[format] = type }
    saved_detected.each { |format, type| detected[format] = type }
    saved_resolved.each { |format, klass| resolved[format] = klass }
    %i[yaml json].each { |format| detected_flags.delete(format) }
  end

  around do |example|
    with_fresh_kv_resolution do
      example.run
    end
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

  it "keeps a centrally configured adapter ahead of detection" do
    skip "yeptris engine not available on this platform" unless
      yeptris_engine_available?

    Lutaml::Model::AdapterResolver.set_adapter_type(:yaml, :standard)

    expect(Lutaml::Model::Config.adapter_for(:yaml))
      .not_to be(Lutaml::Yaml::Adapter::YeptrisAdapter)
  end

  it "does not consult environment variables for engine choice" do
    ENV["LUTAML_YAML"] = "standard"
    ENV["FONTIST_YAML"] = "standard"

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
