require "spec_helper"
require "lutaml/model"

module GroupSpec
  class Ceramic < Lutaml::Model::Serializable
    attribute :type, :string, default: "Data"
    attribute :name, :string, default: "Starc"

    xml do
      no_root
      map_element :type, to: :type
      map_element :name, to: :name
    end

    key_value do
      map :type, to: :type
      map :name, to: :name
    end
  end

  class CeramicCollection < Lutaml::Model::Serializable
    attribute :ceramic, Ceramic, collection: 1..2

    xml do
      root "collection"
      map_element "ceramic", to: :ceramic
    end
  end

  class AttributeValueType < Lutaml::Model::Type::Decimal
  end

  class GroupOfItems < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :type, :string
    attribute :description, :string
    attribute :code, :string

    xml do
      no_root
      sequence do
        map_element "name", to: :name
        map_element "type", to: :type
        map_element "description", to: :description,
                                   namespace: "http://www.sparxsystems.com/profiles/GML/1.0",
                                   prefix: "GML"
      end
      map_attribute "code", to: :code, namespace: "http://www.example.com", prefix: "ex1"
    end
  end

  class ComplexType < Lutaml::Model::Serializable
    attribute :tag, AttributeValueType
    attribute :content, :string
    attribute :group, :string
    import_model_attributes GroupOfItems

    xml do
      root "GroupOfItems"
      map_attribute "tag", to: :tag
      map_content to: :content
      map_element :group, to: :group
      import_model_mappings GroupOfItems
    end
  end

  class SimpleType < Lutaml::Model::Serializable
    import_model GroupOfItems
  end

  class GenericType < Lutaml::Model::Serializable
    import_model_mappings GroupOfItems
  end

  class GroupWithRoot < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      root "group"
      map_element :name, to: :name
    end
  end

  class CommonAttributes < Lutaml::Model::Serializable
    attribute :mstyle, :string

    xml do
      no_root
      map_element :mstyle, to: :mstyle
    end
  end

  class Mrow < Lutaml::Model::Serializable
    attribute :mi, :string
    import_model CommonAttributes

    xml do
      root "mrow"
      map_element :mi, to: :mi
    end

    import_model GroupOfItems

    key_value do
      map :mcol, to: :mcol
    end

    import_model Ceramic
  end

  class ContributionInfo < Lutaml::Model::Serializable
    attribute :person, :string
    attribute :organization, :string

    xml do
      no_root
      map_element "person", to: :person
      map_element "organization", to: :organization
    end
  end

  class Contributor < Lutaml::Model::Serializable
    attribute :role, :string
    import_model_attributes ContributionInfo

    xml do
      root "contributor"
      map_element "role", to: :role
      map_element "person", to: :person
      map_element "organization", to: :organization
    end
  end
end

RSpec.describe "Group" do
  context "when serializing and deserializing import model having no_root" do
    let(:xml) do
      <<~XML
        <mrow xmlns:ex1="http://www.example.com" xmlns:GML="http://www.sparxsystems.com/profiles/GML/1.0">
          <mstyle>italic</mstyle>
          <mi>x</mi>
          <name>Smith</name>
          <type>product</type>
          <GML:description>Item</GML:description>
        </mrow>
      XML
    end

    let(:input_xml) do
      <<~XML
        <contributor>
          <role>author</role>
          <person>John Doe</person>
          <organization>ACME</organization>
        </contributor>
      XML
    end

    it "parse the imported model correctly" do
      parsed = GroupSpec::Mrow.from_xml(xml)
      expect(parsed.mi).to eq("x")
      expect(parsed.mstyle).to eq("italic")
      expect(parsed.name).to eq("Smith")
      expect(parsed.type).to eq("product")
      expect(parsed.description).to eq("Item")
    end

    it "parse the imported model attributes correctly" do
      parsed = GroupSpec::Contributor.from_xml(input_xml)
      expect(parsed.person).to eq("John Doe")
      expect(parsed.role).to eq("author")
      expect(parsed.organization).to eq("ACME")
    end

    it "serialize the imported model correctly" do
      instance = GroupSpec::Mrow.new(mi: "x", mstyle: "italic", name: "Smith", type: "product", description: "Item")
      expect(instance.to_xml).to be_equivalent_to(xml)
    end
  end

  context "with no_root" do
    let(:mapper) { GroupSpec::CeramicCollection }

    it "raises error if root-less class used directly for parsing" do
      xml = <<~XML
        <type>Data</type>
        <name>Smith</name>
      XML

      expect { GroupSpec::Ceramic.from_xml(xml) }.to raise_error(
        Lutaml::Model::NoRootMappingError,
        "GroupSpec::Ceramic has `no_root`, it allowed only for reusable models",
      )
    end

    it "raises error if root_less class used for deserializing" do
      ceramic = GroupSpec::Ceramic.new(type: "Data", name: "Starc")

      expect { ceramic.to_xml }.to raise_error(
        Lutaml::Model::NoRootMappingError,
        "GroupSpec::Ceramic has `no_root`, it allowed only for reusable models",
      )
    end

    it "correctly get the element of root-less class" do
      xml = <<~XML
        <collection>
          <ceramic>
            <type>Data</type>
          </ceramic>
        </collection>
      XML

      expect { mapper.from_xml(xml) }.not_to raise_error
    end
  end

  context "with model" do
    shared_examples "imports attributes from" do |source_class, target_class|
      it "imports attributes from #{source_class.name}" do
        expect(target_class.attributes).to include(source_class.attributes)
      end
    end

    shared_examples "imports mappings from" do |source_class, target_class|
      it "imports mappings from #{source_class.name}" do
        expect(target_class.mappings_for(:xml).elements).to include(*source_class.mappings_for(:xml).elements)
      end
    end

    describe GroupSpec::ComplexType do
      it_behaves_like "imports attributes from", GroupSpec::GroupOfItems, described_class
      it_behaves_like "imports mappings from", GroupSpec::GroupOfItems, described_class
    end

    describe GroupSpec::GenericType do
      it_behaves_like "imports mappings from", GroupSpec::GroupOfItems, described_class
    end

    describe GroupSpec::SimpleType do
      it_behaves_like "imports attributes from", GroupSpec::GroupOfItems, described_class
      it_behaves_like "imports mappings from", GroupSpec::GroupOfItems, described_class
    end

    describe GroupSpec::Mrow do
      it_behaves_like "imports attributes from", GroupSpec::CommonAttributes, described_class
      it_behaves_like "imports attributes from", GroupSpec::Ceramic, described_class
      it_behaves_like "imports mappings from", GroupSpec::CommonAttributes, described_class
      it_behaves_like "imports mappings from", GroupSpec::Ceramic, described_class
    end

    describe GroupSpec::Contributor do
      it_behaves_like "imports attributes from", GroupSpec::ContributionInfo, described_class
    end

    it "raises error if root is defined on imported class" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          import_model GroupSpec::GroupWithRoot
        end
      end.to raise_error(Lutaml::Model::ImportModelWithRootError, "Cannot import a model `GroupSpec::GroupWithRoot` with a root element")
    end

    it "raises error if namespace is defined with no_root" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          xml do
            no_root
            namespace "http://www.omg.org/spec/XMI/20131001", "xmi"
          end
        end
      end.to raise_error(Lutaml::Model::NoRootNamespaceError, "Cannot assign namespace to `no_root`")
    end
  end
end
