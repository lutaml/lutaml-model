# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

RSpec.describe "Mapping finalization cache guard specs" do
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :age, :integer

      xml do
        root "person"
        map_element "name", to: :name
        map_attribute "age", to: :age
      end

      def self.name
        "FinalizationTestModel"
      end
    end
  end

  describe "post-finalization caching" do
    let(:mapping) { model_class.mappings_for(:xml) }

    it "returns frozen arrays after finalization" do
      expect(mapping.elements).to be_frozen
      expect(mapping.attributes).to be_frozen
      expect(mapping.mappings).to be_frozen
    end

    it "returns same object on repeated calls" do
      elements1 = mapping.elements
      elements2 = mapping.elements
      expect(elements1).to equal(elements2)
    end

    it "caches per register independently" do
      default_elements = mapping.elements(:default)
      other_elements = mapping.elements(:nonexistent)
      expect(default_elements).not_to equal(other_elements)
    end
  end

  describe "finalize! clears stale caches" do
    it "provides fresh caches after re-finalization" do
      elements_before = model_class.mappings_for(:xml).elements

      # Create a child class that inherits and adds a mapping
      child_class = Class.new(model_class) do
        attribute :email, :string

        xml do
          root "person"
          map_element "email", to: :email
        end

        def self.name
          "ChildFinalizationTestModel"
        end
      end

      child_elements = child_class.mappings_for(:xml).elements
      # Child should have both name and email elements
      element_names = child_elements.map(&:name)
      expect(element_names).to include("name", "email")
    end
  end

  describe "before finalization" do
    it "does not cache results" do
      unfinalized = Lutaml::Xml::Mapping.new
      unfinalized.instance_eval do
        @elements["name"] = Lutaml::Xml::MappingRule.new("name", to: :name)
      end
      result1 = unfinalized.elements
      result2 = unfinalized.elements
      # Not finalized, so each call recomputes (different objects)
      expect(result1).not_to equal(result2)
    end
  end
end
