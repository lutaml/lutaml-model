# frozen_string_literal: true

require "spec_helper"

# lutaml-model#1252: direct construction must keep an assigned String
# verbatim, even when the declared type is a Serializable whose
# (derived or explicit) mapping exposes a scalar `content` rule. The
# scalar-coercion contract (#1228, #978) belongs to the format
# boundary (from_json/from_yaml/from_hash) only.
RSpec.describe "direct construction keeps assigned scalars verbatim" do
  let(:text_element_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :content, Lutaml::Model::Serializable, default: -> { "" },
                                                       polymorphic: [Lutaml::Model::Type::String, :array]
    end
  end

  let(:title_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :content, "VerbatimTextElement"
    end
  end

  before do
    stub_const("VerbatimTextElement", text_element_class)
    stub_const("VerbatimTitle", title_class)
  end

  # The ceradoc shape: derived mapping, polymorphic inner content.
  it "keeps the String with a derived content mapping (#1252)" do
    title = VerbatimTitle.new(content: "Test Document")

    expect(title.content).to be_a(String)
    expect(title.content).to eq("Test Document")
  end

  it "keeps the String with an explicit keyed content mapping" do
    element_class = Class.new(Lutaml::Model::Serializable) do
      attribute :content, :string

      key_value do
        map "content", to: :content
      end
    end
    stub_const("VerbatimMappedElement", element_class)

    holder = Class.new(Lutaml::Model::Serializable) do
      attribute :body, "VerbatimMappedElement"
    end
    stub_const("VerbatimMappedHolder", holder)

    model = VerbatimMappedHolder.new(body: "plain text")

    expect(model.body).to be_a(String)
    expect(model.body).to eq("plain text")
  end

  it "still coerces at the deserialization boundary (#1228 contract)" do
    element_class = Class.new(Lutaml::Model::Serializable) do
      attribute :content, :string

      key_value do
        map "content", to: :content
      end
    end
    stub_const("BoundaryMappedElement", element_class)

    holder = Class.new(Lutaml::Model::Serializable) do
      attribute :body, "BoundaryMappedElement"

      key_value do
        map "body", to: :body
      end
    end
    stub_const("BoundaryHolder", holder)

    model = BoundaryHolder.from_json('{"body": "wire text"}')

    expect(model.body).to be_a(BoundaryMappedElement)
    expect(model.body.content).to eq("wire text")
  end
end
