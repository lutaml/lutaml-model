# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Lutaml::Model::Validation with UninitializedClass" do
  before do
    stub_const("ValidateWithUninitializedModel", Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :role, :string, values: %w[admin guest], default: -> { "guest" }
    end)
  end

  it "does not crash when validating with uninitialized attributes" do
    model = ValidateWithUninitializedModel.new
    # name is uninitialized, but validate should not crash
    expect { model.validate }.not_to raise_error
  end

  it "still catches value constraint violations" do
    model = ValidateWithUninitializedModel.new(role: "hacker")
    errors = model.validate
    expect(errors).not_to be_empty
  end

  it "returns empty errors for valid instance" do
    model = ValidateWithUninitializedModel.new(name: "ok", role: "admin")
    expect(model.validate).to be_empty
  end
end
