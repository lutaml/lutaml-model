# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Xml::AdapterLoader do
  it "chains the LoadError cause instead of masking it" do
    expect do
      described_class.load_adapter_file("xml", "bogus_adapter")
    end.to raise_error(Lutaml::Model::UnknownAdapterTypeError) do |error|
      expect(error.cause).to be_a(LoadError)
      expect(error.cause.message).to include("bogus_adapter")
    end
  end
end
