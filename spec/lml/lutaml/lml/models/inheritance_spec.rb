# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe "LML model subclasses" do
  describe Lutaml::Lml::UmlClass do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end

    it "has parent_class attribute" do
      klass = described_class.new(name: "Child", parent_class: "Parent")
      expect(klass.parent_class).to eq("Parent")
    end

    it "returns :classes as entity_type" do
      expect(described_class.entity_type).to eq(:classes)
    end
  end

  describe Lutaml::Lml::Enum do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end

    it "returns :enums as entity_type" do
      expect(described_class.entity_type).to eq(:enums)
    end
  end

  describe Lutaml::Lml::DataType do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end

    it "returns :data_types as entity_type" do
      expect(described_class.entity_type).to eq(:data_types)
    end
  end

  describe Lutaml::Lml::Package do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end
  end

  describe Lutaml::Lml::Association do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end
  end

  describe Lutaml::Lml::Cardinality do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end
  end

  describe Lutaml::Lml::Value do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end
  end

  describe Lutaml::Lml::Constraint do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end
  end

  describe Lutaml::Lml::Operation do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end
  end
end
