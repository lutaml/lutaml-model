# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe "Lutaml::Lml::Format autoload" do
  it "registers :lml with FormatRegistry when the Format constant is accessed" do
    Lutaml::Lml::Format
    expect(Lutaml::Model::FormatRegistry.registered?(:lml)).to be true
  end

  it "autoloads StandardAdapter" do
    expect(Lutaml::Lml::Format::Adapter::StandardAdapter)
      .to be_a(Class)
  end

  it "autoloads Mapping" do
    expect(Lutaml::Lml::Format::Adapter::Mapping)
      .to be_a(Class)
  end

  it "autoloads Transform" do
    expect(Lutaml::Lml::Format::Adapter::Transform)
      .to be_a(Class)
  end

  it "autoloads Document" do
    expect(Lutaml::Lml::Format::Adapter::Document)
      .to be_a(Class)
  end
end
