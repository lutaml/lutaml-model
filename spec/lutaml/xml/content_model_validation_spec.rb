# spec/lutaml/xml/content_model_validation_spec.rb

require "spec_helper"
require_relative "../../../lib/lutaml/model"

RSpec.describe "Content model validation" do
  describe "OrderedContentMappingError" do
    it "raises when ordered + map_content" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string

          xml do
            element "test"
            ordered
            map_content to: :content
          end

          def self.name
            "OrderedWithContentTest"
          end
        end
      end.to raise_error(
        Lutaml::Model::OrderedContentMappingError,
        /Element-only content model.*does not support `map_content`/,
      )
    end

    it "raises when root with ordered: true and map_content" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string

          xml do
            root "test", ordered: true
            map_content to: :content
          end

          def self.name
            "RootOrderedWithContentTest"
          end
        end
      end.to raise_error(Lutaml::Model::OrderedContentMappingError)
    end

    it "does not raise when ordered without map_content" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :child, :string

          xml do
            element "test"
            ordered
            map_element "child", to: :child
          end

          def self.name
            "OrderedWithoutContentTest"
          end
        end
      end.not_to raise_error
    end

    it "does not raise when mixed_content with map_content (collection)" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string, collection: true

          xml do
            element "test"
            mixed_content
            map_content to: :content
          end

          def self.name
            "MixedWithContentTest"
          end
        end
      end.not_to raise_error
    end

    it "does not raise when root with mixed: true and map_content (collection)" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string, collection: true

          xml do
            root "test", mixed: true
            map_content to: :content
          end

          def self.name
            "RootMixedWithContentTest"
          end
        end
      end.not_to raise_error
    end

    it "does not raise when default (no ordered/mixed) with map_content" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string

          xml do
            element "test"
            map_content to: :content
          end

          def self.name
            "DefaultWithContentTest"
          end
        end
      end.not_to raise_error
    end
  end

  describe "MixedContentCollectionError" do
    it "raises when mixed_content + map_content to non-collection attribute" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string

          xml do
            element "test"
            mixed_content
            map_content to: :content
          end

          def self.name
            "MixedContentNonCollectionTest"
          end
        end
      end.to raise_error(
        Lutaml::Model::MixedContentCollectionError,
        /Mixed content requires.*to be a string collection/,
      )
    end

    it "does not raise when mixed_content + map_content to collection attribute" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string, collection: true

          xml do
            element "test"
            mixed_content
            map_content to: :content
          end

          def self.name
            "MixedContentCollectionTest"
          end
        end
      end.not_to raise_error
    end
  end
end
