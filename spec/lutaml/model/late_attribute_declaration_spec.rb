# frozen_string_literal: true

require "spec_helper"

# Attributes can be declared after the model has been instantiated
# (forward references, post-hoc declarations). The interned writer
# table built during the first instantiation must not outlive the
# attribute set it was built from.
RSpec.describe "attributes declared after first instantiation" do
  it "initializes attributes added after an earlier instantiation" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
    end

    klass.new(name: "first")

    klass.attribute :size, :string
    instance = klass.new(name: "second", size: "L")

    expect(instance.name).to eq("second")
    expect(instance.size).to eq("L")
  end

  it "keeps earlier instances unaffected" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
    end

    first = klass.new(name: "first")
    klass.attribute :size, :string

    expect(first.name).to eq("first")
    expect(first.respond_to?(:size)).to be(true)
  end
end
