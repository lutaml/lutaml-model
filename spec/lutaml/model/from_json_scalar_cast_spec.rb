# frozen_string_literal: true

require "spec_helper"

# lutaml-model#978 + #1228: a JSON scalar handed to a mapped-model
# attribute crashed with an internal NoMethodError (key? on String)
# wrapped as InvalidFormatError. A type that declares its own .cast
# owns scalar construction from that scalar; a cast-less type with a
# scalar `content` rule coerces onto it (#1228); a type without one
# keeps the format parse error — or declares .cast to own it.
RSpec.describe "from_json scalar into a mapped-model attribute" do
  let(:marked_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :content, :string

      key_value do
        map "content", to: :content
      end

      def self.cast(value)
        return value if value.is_a?(self)

        new(content: value.to_s)
      end
    end
  end

  let(:plain_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :content, :string

      key_value do
        map "content", to: :content
      end
    end
  end

  let(:holder_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :description, "ScalarMarked"
      attribute :plain_desc, "ScalarPlain"

      key_value do
        map "description", to: :description
        map "plain_desc", to: :plain_desc
      end
    end
  end

  before do
    stub_const("ScalarMarked", marked_class)
    stub_const("ScalarPlain", plain_class)
    stub_const("ScalarHolder", holder_class)
  end

  it "constructs the mapped value through the type's .cast" do
    model = ScalarHolder.from_json('{"description": "text"}')

    expect(model.description).to be_a(ScalarMarked)
    expect(model.description.content).to eq("text")
  end

  # #1228 reconciled with #978: a cast-LESS type whose key_value
  # mapping carries a scalar `content` rule coerces the scalar onto
  # that rule (title: "text" builds the model with content "text") —
  # the 0.8.x contract Relaton's localized titles ride. The .cast
  # ownership contract above still takes precedence for types that
  # declare their own scalar construction.
  it "coerces the scalar onto the content mapping for a cast-less mapped type" do
    model = ScalarHolder.from_json('{"plain_desc": "text"}')

    expect(model.plain_desc).to be_a(ScalarPlain)
    expect(model.plain_desc.content).to eq("text")
  end

  it "raises the format error for a scalar on a mapped type without a content rule" do
    shape_class = Class.new(Lutaml::Model::Serializable) do
      attribute :label, :string

      key_value do
        map "label", to: :label
      end
    end
    stub_const("ScalarShapeless", shape_class)

    holder = Class.new(Lutaml::Model::Serializable) do
      attribute :shape, "ScalarShapeless"

      key_value do
        map "shape", to: :shape
      end
    end
    stub_const("ScalarShapelessHolder", holder)

    expect { ScalarShapelessHolder.from_json('{"shape": "text"}') }
      .to raise_error(Lutaml::Model::InvalidFormatError, /maps no `content`/)
  end
end
