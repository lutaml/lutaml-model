# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::GlobalRegister do
  describe "#initialize" do
    it "initializes with a default register" do
      expect(described_class.instance.instance_variable_get(:@registers)).to include(default: described_class.lookup(:default))
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
      register = Lutaml::Model::Register.new(:temp_register)
      expect { described_class.register(register) }.to(
        change do
          described_class.instance.instance_variable_get(:@registers).count
        end.by(1),
      )
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
      allow(described_class.instance).to receive(:lookup).with(:v1).and_return(register_v_one)

      expect(described_class.lookup(:v1)).to eq(register_v_one)
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

  describe "#remove" do
    let(:register_v_one) { Lutaml::Model::Register.new(:v1) }
    let(:register_v_two) { Lutaml::Model::Register.new(:v2) }

    before do
      described_class.register(register_v_one)
      described_class.register(register_v_two)
    end

    it "removes the specified register" do
      register = described_class.instance
      expect(register.instance_variable_get(:@registers).values).to include(register_v_one)
      expect { described_class.remove(:v1) }.to(
        change do
          register.instance_variable_get(:@registers).values.count
        end.by(-1),
      )
      expect(register.instance_variable_get(:@registers).values).not_to include(register_v_one)
    end

    it "does not remove other registers" do
      described_class.remove(:v1)
      registers = described_class.instance.instance_variable_get(:@registers)
      expect(registers.values).to include(register_v_two)
    end

    it "does nothing when the specified register does not exist" do
      registers = described_class.instance.instance_variable_get(:@registers)
      expect { described_class.remove(:non_existent) }.not_to(change do
        registers.values.count
      end)
    end
  end
end
