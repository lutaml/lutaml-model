require "spec_helper"
require_relative "../../fixtures/address"

class LiquefiableClass
  include Lutaml::Model::Liquefiable

  attr_accessor :name, :value

  def initialize(name, value)
    @name = name
    @value = value
  end

  def display_name
    "#{name} (#{value})"
  end
end

RSpec.describe Lutaml::Model::Liquefiable do
  before do
    stub_const("DummyModel", Class.new(LiquefiableClass))
  end

  let(:dummy) { DummyModel.new("TestName", 42) }

  describe ".register_liquid_drop_class" do
    context "when drop class does not exist" do
      it "creates a new drop class" do
        expect { dummy.class.register_liquid_drop_class }.to change { dummy.class.const_defined?(:DummyModelDrop) }
          .from(false)
          .to(true)
      end
    end

    context "when drop class already exists" do
      it "raises an error" do
        dummy.class.register_liquid_drop_class
        expect { dummy.class.register_liquid_drop_class }.to raise_error(RuntimeError, "DummyModelDrop Already exists!")
      end
    end
  end

  describe ".drop_class_name" do
    it "returns the correct drop class name" do
      expect(dummy.class.drop_class_name).to eq("DummyModelDrop")
    end
  end

  describe ".drop_class" do
    context "when drop class exists" do
      it "returns the drop class" do
        dummy.class.register_liquid_drop_class
        expect(dummy.class.drop_class).to eq(DummyModel::DummyModelDrop)
      end
    end

    context "when drop class does not exist" do
      it "returns nil" do
        expect(dummy.class.drop_class).to be_nil
      end
    end
  end

  describe ".register_drop_method" do
    before do
      dummy.class.register_liquid_drop_class
    end

    it "defines a method on the drop class" do
      expect { dummy.class.register_drop_method(:display_name) }.to change { dummy.to_liquid.respond_to?(:display_name) }
        .from(false)
        .to(true)
    end
  end

  describe ".to_liquid" do
    before do
      dummy.class.register_liquid_drop_class
      dummy.class.register_drop_method(:display_name)
    end

    it "returns an instance of the drop class" do
      expect(dummy.to_liquid).to be_a(dummy.class.drop_class)
    end

    it "allows access to registered methods via the drop class" do
      expect(dummy.to_liquid.display_name).to eq("TestName (42)")
    end
  end

  context "with serializeable classes" do
    let(:address) do
      Address.new(
        {
          country: "US",
          post_code: "12345",
          person: [Person.new, Person.new],
        },
      )
    end

    describe ".to_liquid" do
      it "returns correct drop object" do
        expect(address.to_liquid).to be_a(Address::AddressDrop)
      end

      it "returns array of drops for collection objects" do
        person_classes = address.to_liquid.person.map(&:class)
        expect(person_classes).to eq([Person::PersonDrop, Person::PersonDrop])
      end

      it "returns `US` for country" do
        expect(address.to_liquid.country).to eq("US")
      end
    end
  end
end
