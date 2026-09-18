# frozen_string_literal: true

require "spec_helper"

# lutaml-model#800: `liquid do ... end` blocks survive a boot order in
# which Liquid is required after lutaml-model; the drop class
# materializes on first use instead of requiring Liquid at definition.
RSpec.describe "Liquefiable lazy registration" do
  it "materializes the drop class on first to_liquid" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      liquid do
        map "full_name", to: :name
      end
    end

    # Mapping stored at definition; drop registration is lazy
    expect(klass.liquid_mappings.mappings).not_to be_empty

    drop = klass.new(name: "Apollo").to_liquid
    expect(drop).to be_a(Liquid::Drop)
    expect(drop.full_name).to eq("Apollo")
  end

  it "keeps ensure_liquid_registered! idempotent" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
    end

    klass.ensure_liquid_registered!
    first = klass.base_drop_class
    klass.ensure_liquid_registered!
    expect(klass.base_drop_class).to equal(first)
  end
end
