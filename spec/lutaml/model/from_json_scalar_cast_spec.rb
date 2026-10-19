# frozen_string_literal: true

require "spec_helper"

# #978: a JSON scalar handed to a mapped-model attribute crashed with
# an internal NoMethodError (key? on String) wrapped as
# InvalidFormatError. A type that declares its own .cast owns scalar
# construction from that scalar; a cast-less type falls through to the
# legacy conversion chain, whose parse error surfaces the offending
# token — the remedy there is declaring .cast on the type.
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

  it "falls through to the format parse error for a cast-less mapped type" do
    expect { ScalarHolder.from_json('{"plain_desc": "text"}') }
      .to raise_error(
        Lutaml::Model::InvalidFormatError,
        /unexpected token 'text'/,
      )
  end
end
