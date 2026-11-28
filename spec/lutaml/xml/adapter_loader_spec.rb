# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Xml::AdapterLoader do
  # Every adapter type loads the one shared adapter file; the
  # chained-cause contract lives at the ENGINE preload — a missing
  # engine gem must name the real gap, not present as a bare
  # unknown-type error.
  it "chains the engine LoadError cause instead of masking it" do
    allow(Moxml::Adapter).to receive(:load)
      .and_raise(LoadError, "cannot load such file -- nokogiri")
    expect do
      described_class.load_moxml_adapter(:nokogiri, :xml)
    end.to raise_error(Lutaml::Model::UnknownAdapterTypeError) do |error|
      expect(error.cause).to be_a(LoadError)
      expect(error.cause.message).to include("nokogiri")
    end
  end

  it "raises for an unknown engine at the adapter factory" do
    expect do
      Lutaml::Xml::Adapter::MoxmlAdapter.for_engine(:bogus)
    end.to raise_error(ArgumentError, /unknown XML engine/)
  end
end
