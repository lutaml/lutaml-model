# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/global_register"
require "lutaml/model/register"

RSpec.describe Lutaml::Model::GlobalRegister do
  before do
    described_class.instance.instance_variable_set(:@registers, {})
  end

  describe "#initialize" do
    it "initializes with empty registers hash" do
      expect(described_class.instance.instance_variable_get(:@registers)).to eq({})
    end
  end

  describe "#register" do
    it "adds register to the internal hash" do
      register = Lutaml::Model::Register.new(:test_register)
      described_class.register(register)

      registers = described_class.instance.instance_variable_get(:@registers)
      expect(registers[:test_register]).to eq(register)
    end
  end

  describe ".register" do
    it "calls instance method to register" do
      register = Lutaml::Model::Register.new(:test_register)
      described_class.register(register)
      allow(described_class.instance).to receive(:register).with(register).and_return(register)
      expect(described_class.lookup(:test_register)).to eq(register)
    end
  end

  describe "#lookup" do
    let(:register_v_one) { Lutaml::Model::Register.new(:v1) }
    let(:register_v_two) { Lutaml::Model::Register.new(:v2) }

    before do
      described_class.instance.register(register_v_one)
      described_class.instance.register(register_v_two)
    end

    it "returns the correct register for a given id" do
      expect(described_class.instance.lookup(:v1)).to eq(register_v_one)
      expect(described_class.instance.lookup(:v2)).to eq(register_v_two)
    end

    it "returns nil for non-existent id" do
      expect(described_class.instance.lookup(:non_existent)).to be_nil
    end

    it "converts string id to symbol" do
      expect(described_class.instance.lookup("v1")).to eq(register_v_one)
    end
  end

  describe ".lookup" do
    let(:register_v_one) { Lutaml::Model::Register.new(:v1) }

    it "calls instance method to lookup" do
      allow(described_class.instance).to receive(:lookup).with(:test_id).and_return(register_v_one)

      expect(described_class.lookup(:test_id)).to eq(register_v_one)
    end
  end

  describe "#registered_objects" do
    let(:register_v_one) { Lutaml::Model::Register.new(:v1) }
    let(:register_v_two) { Lutaml::Model::Register.new(:v2) }

    before do
      described_class.instance.register(register_v_one)
      described_class.instance.register(register_v_two)
    end

    it "returns all register objects" do
      registers = described_class.instance.registered_objects

      expect(registers.size).to eq(2)
      expect(registers).to include(register_v_one)
      expect(registers).to include(register_v_two)
    end

    it "returns empty array when no registers" do
      described_class.instance.instance_variable_set(:@registers, {})

      expect(described_class.instance.registered_objects).to be_empty
    end
  end

  describe "singleton behavior" do
    it "returns the same instance on multiple calls" do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end

    it "shares state between method calls" do
      register = Lutaml::Model::Register.new(:shared_test)
      described_class.register(register)
      expect(described_class.lookup(:shared_test)).to eq(register)
    end
  end
end
