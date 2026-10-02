# frozen_string_literal

require "spec_helper"

RSpec.describe "XML adapter metadata default (#908)" do
  it "resolves to leptris when moxml reports no preference" do
    Lutaml::Model::AdapterResolver.reset!

    allow(Moxml::Config).to receive(:runtime_default_adapter).and_return(nil)

    adapter = Lutaml::Model::Config.adapter_for(:xml)
    expect(adapter.name).to eq("Lutaml::Xml::Adapter::LeptrisAdapter")
  ensure
    Lutaml::Model::AdapterResolver.reset!
  end
end
