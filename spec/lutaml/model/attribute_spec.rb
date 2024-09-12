require "spec_helper"
require "lutaml/model"
require "pathname"

RSpec.describe Lutaml::Model::Attribute do
  subject(:name_attr) do
    described_class.new("name", :string)
  end

  let(:test_record_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :age, :integer
      attribute :image, :string
    end
  end

  before do
    stub_const("TestRecord", test_record_class)
  end

  it "cast to integer when assigning age" do
    obj = TestRecord.new

    expect { obj.age = "20" }.to change { obj.age }.from(nil).to(20)
  end

  it "cast to string when assigning image file" do
    obj = TestRecord.new

    expect { obj.image = Pathname.new("avatar.png") }
      .to change { obj.image }
      .from(nil)
      .to("avatar.png")
  end

  describe "#cast_type" do
    it "cast :string to Lutaml::Model::Type::String" do
      expect(name_attr.cast_type(:string)).to eq(Lutaml::Model::Type::String)
    end

    it "cast :integer to Lutaml::Model::Type::Integer" do
      expect(name_attr.cast_type(:integer)).to eq(Lutaml::Model::Type::Integer)
    end

    it "raises ArgumentError on unknown type" do
      expect { name_attr.cast_type(:foobar) }
        .to raise_error(ArgumentError, "Unknown Lutaml::Model::Type: foobar")
    end
  end

  describe "#default?" do
    context "when default is not set" do
      let(:attribute) { described_class.new("name", :string) }

      it { expect(attribute.default).to be_nil }
    end

    context "when default is set as a proc" do
      it "returns the value" do
        attribute = described_class.new("name", :string, default: -> { "John" })
        expect(attribute.default).to eq("John")
      end

      it "returns the value casted to correct type" do
        file = Pathname.new("avatar.png")
        attribute = described_class.new("image", :string, default: -> { file })

        expect(attribute.default).to eq("avatar.png")
      end
    end

    context "when default is set as value" do
      it "returns the value" do
        attribute = described_class.new("name", :string, default: "John Doe")
        expect(attribute.default).to eq("John Doe")
      end

      it "returns the value casted to correct type" do
        attribute = described_class.new("age", :integer, default: "24")
        expect(attribute.default).to eq(24)
      end
    end
  end
end
