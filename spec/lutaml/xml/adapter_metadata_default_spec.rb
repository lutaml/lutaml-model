# frozen_string_literal

require "spec_helper"

RSpec.describe "XML adapter metadata default (#908, #1224)" do
  # The metadata default is the DEFERRED lane (#1224): when moxml
  # reports no preference, resolution lands on the :moxml adapter,
  # whose engine resolves at parse time - a preference-less moxml
  # then detects leptris (its own runtime preference), so the
  # observable lane is unchanged from the #908 answer.
  it "resolves to the deferred lane when moxml reports no preference" do
    Lutaml::Model::AdapterResolver.reset!

    allow(Moxml::Config).to receive(:runtime_default_adapter).and_return(nil)

    adapter = Lutaml::Model::Config.adapter_for(:xml)
    expect(adapter.name).to eq("Lutaml::Xml::Adapter::MoxmlAdapter")
  ensure
    Lutaml::Model::AdapterResolver.reset!
  end

  # when moxml DOES answer, detection binds the engine directly -
  # the #908 outcome, unchanged by the deferred lane
  it "detects the engine directly when moxml answers" do
    Lutaml::Model::AdapterResolver.reset!

    allow(Moxml::Config).to receive(:runtime_default_adapter)
      .and_return(:leptris)

    adapter = Lutaml::Model::Config.adapter_for(:xml)
    expect(adapter.name).to eq("Lutaml::Xml::Adapter::LeptrisAdapter")
  ensure
    Lutaml::Model::AdapterResolver.reset!
  end
end
