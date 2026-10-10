# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Documentation metadata (desc)" do
  let(:widget_class) do
    Class.new(Lutaml::Model::Serializable) do
      desc "A widget."

      attribute :name, :string, desc: "The widget name."
      attribute :size, :integer
    end
  end

  it "stores and reads the class-level description" do
    expect(widget_class.desc).to eq("A widget.")
  end

  it "returns nil when no description is set" do
    plain = Class.new(Lutaml::Model::Serializable)
    expect(plain.desc).to be_nil
  end

  it "inherits the description on subclasses" do
    child = Class.new(widget_class)
    expect(child.desc).to eq("A widget.")
  end

  it "lets a subclass override the description" do
    child = Class.new(widget_class) do
      desc "A special widget."
    end
    expect(child.desc).to eq("A special widget.")
  end

  it "does not leak an override back to the superclass" do
    Class.new(widget_class) { desc "Child only." }
    expect(widget_class.desc).to eq("A widget.")
  end

  it "stores the attribute-level description" do
    expect(widget_class.attributes[:name].desc).to eq("The widget name.")
    expect(widget_class.attributes[:size].desc).to be_nil
  end

  it "keeps serialization untouched" do
    widget = widget_class.new(name: "w", size: 3)
    expect(widget.to_hash).to eq("name" => "w", "size" => 3)
  end
end
