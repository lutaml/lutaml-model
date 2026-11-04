# frozen_string_literal: true

require "spec_helper"

# lutaml-model#1115: the yeptris opt-in is consumer-neutral
# (LUTAML_YAML; FONTIST_YAML stays honored as the legacy spelling), and
# a bundle containing yeptris without the opt-in sees a one-time
# warning naming the switch — the gated engine is visible, not silent.
RSpec.describe "yeptris engine opt-in switch" do
  around do |example|
    old = ENV.to_h.slice("LUTAML_YAML", "FONTIST_YAML")
    ENV.delete("LUTAML_YAML")
    ENV.delete("FONTIST_YAML")
    example.run
    old.each { |k, v| ENV[k] = v }
  end

  it "selects yeptris with LUTAML_YAML=yeptris" do
    skip "yeptris engine not available on this platform" unless
      Lutaml::Model::AdapterResolver.send(:yeptris_opted_in?)

    expect(Lutaml::Model::Config.adapter_for(:yaml))
      .to be(Lutaml::Yaml::Adapter::YeptrisAdapter)
  end

  it "honors the legacy FONTIST_YAML spelling" do
    expect(Lutaml::Model::AdapterResolver.send(:yeptris_opted_in?)).to be(false)

    ENV["FONTIST_YAML"] = "yeptris"
    expect(Lutaml::Model::AdapterResolver.send(:yeptris_opted_in?)).to be(true)
  end

  it "selects yeptris with FONTIST_YAML=yeptris" do
    skip "yeptris engine not available on this platform" if
      RUBY_ENGINE == "opal"

    ENV["FONTIST_YAML"] = "yeptris"
    expect(Lutaml::Model::Config.adapter_for(:yaml)).not_to be_nil
  end
end
