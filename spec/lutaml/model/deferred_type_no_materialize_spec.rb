# frozen_string_literal: true

require "spec_helper"

# Definition-time attribute-type validation (lutaml-model#296) must
# resolve types WITHOUT materializing deferred model classes. Eager
# resolution const_get-fires pending autoloads, which re-enters the
# model file being defined, re-opens its classes, and re-evaluates an
# xml mapping block against the already-populated mapping — rejected
# for map_all_content ("map_all is not allowed ... with map_all").
RSpec.describe "Definition-time type validation" do
  it "leaves a pending autoload unfired while validating a mapping" do
    probe = Module.new
    Object.const_set(:DeferHostProbe, probe)
    probe.autoload(:NeverLoadedModel,
                   File.expand_path("../../fixtures/autoload_probe/never_loaded_model", __dir__))

    expect do
      Class.new(Lutaml::Model::Serializable) do
        attribute :ref, "DeferHostProbe::NeverLoadedModel"

        xml do
          element "doc"
          map_element "ref", to: :ref
        end
      end
    end.not_to raise_error

    expect(probe.autoload?(:NeverLoadedModel)).to be_truthy,
      "mapping validation materialized the deferred type — it must " \
      "stay pending for deferred-import resolution"
  ensure
    Object.send(:remove_const, :DeferHostProbe) if Object.const_defined?(:DeferHostProbe)
  end
end
