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
    choice do
      attribute :mstyle, :string
      attribute :mcol, :string
      attribute :mr, :string
    end

    xml do
      no_root
      sequence do
        map_element :mstyle, to: :mstyle
        map_element :mr, to: :mr
      end
      map_attribute :mcol, to: :mcol
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

  class Mfrac < Lutaml::Model::Serializable
    attribute :num, :string
    import_model CommonAttributes

    xml do
      root "mfrac"
      map_element :num, to: :num
    end
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

  class Identifier < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :remarks, :string, collection: true
    attribute :remark_items, :string, collection: true

    key_value do
      map "id", to: :id
      map "remarks", to: :remarks
      map "remark_items", to: :remark_items
    end
  end

  class ModelElement < Lutaml::Model::Serializable
    import_model Identifier
  end
end

RSpec.describe "Group" do
  context "when serializing and deserializing import model having no_root" do
    let(:xml) do
      <<~XML
        <mrow xmlns:ex1="http://www.example.com" xmlns:GML="http://www.sparxsystems.com/profiles/GML/1.0">
          <mstyle>italic</mstyle>
          <mr>y</mr>
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
      instance = GroupSpec::Mrow.new(mi: "x", mstyle: "italic", mr: "y", name: "Smith", type: "product", description: "Item")
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

    context "deserializing XML" do
      let(:ceramic) { GroupSpec::Ceramic.new(type: "Data", name: "Starc") }

      it "raises error for root_less class" do
        expect { ceramic.to_xml }.to raise_error(
          Lutaml::Model::NoRootMappingError,
          "GroupSpec::Ceramic has `no_root`, it allowed only for reusable models",
        )
      end
    end

    context "deserializing key-value formats" do
      let(:ceramic) { GroupSpec::Ceramic.new(type: "Data", name: "Starc") }

      it "does not raises error for root_less class" do
        expect { ceramic.to_yaml }
          .not_to raise_error(Lutaml::Model::NoRootMappingError)
      end
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
      it "#{source_class.name} correctly" do
        source_attributes = source_class.attributes
        target_attributes = target_class.attributes

        source_attributes.each do |name, attr|
          expect(target_attributes[name].name).to eq(attr.name)
          expect(target_attributes[name].type).to eq(attr.type)
          expect(target_attributes[name].options).to eq(attr.options)
        end
      end
    end

    shared_examples "imports mappings from" do |source_class, target_class|
      it "#{source_class.name} correctly" do
        source_elements = source_class.mappings_for(:xml).elements
        target_elements = target_class.mappings_for(:xml).elements

        source_elements.each do |element|
          matching_element = target_elements.find { |e| e.name == element.name }
          expect(matching_element).not_to be_nil
          expect(matching_element.to).to eq(element.to)
        end
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

    describe GroupSpec::ModelElement do
      it_behaves_like "imports attributes from", GroupSpec::Identifier, described_class
      it_behaves_like "imports mappings from", GroupSpec::Identifier, described_class
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

    context "when importing multiple models with overlapping attributes" do
      let(:mrow_instance) do
        GroupSpec::Mrow.new
      end

      it "uses Ceramic's default values for overlapping attributes" do
        expect(mrow_instance.type).to eq("Data")
        expect(mrow_instance.name).to eq("Starc")
      end

      it "maintains the correct XML serialization order from last import" do
        xml = mrow_instance.to_xml
        expected_xml = "<mrow xmlns:ex1='http://www.example.com' xmlns:GML='http://www.sparxsystems.com/profiles/GML/1.0'/>"

        expect(xml).to be_equivalent_to(expected_xml)
      end
    end

    context "when update the imported attribute" do
      it "updates the attribute `mstyle` only in `Mrow`" do
        GroupSpec::Mrow.attributes[:mstyle].instance_variable_set(:@type, :integer)
        expect(GroupSpec::Mrow.attributes[:mstyle].type).to eq(:integer)
      end

      it "maintains original type for the attribute `mstyle` in `Mfrac`" do
        expect(GroupSpec::Mfrac.attributes[:mstyle].type).to eq(Lutaml::Model::Type::String)
      end

      it "maintains original type for the attribute `mstyle` in importable class `CommonAttributes`" do
        expect(GroupSpec::CommonAttributes.attributes[:mstyle].type).to eq(Lutaml::Model::Type::String)
      end
    end

    context "when updating imported choice" do
      it "updates choice min/max only in Mrow" do
        choice = GroupSpec::Mrow.choice_attributes.first
        choice.instance_variable_set(:@min, 2)
        choice.instance_variable_set(:@max, 3)

        expect(choice.min).to eq(2)
        expect(choice.max).to eq(3)
      end

      it "maintains original choice min/max in Mfrac" do
        choice = GroupSpec::Mfrac.choice_attributes.first
        expect(choice.min).to eq(1)
        expect(choice.max).to eq(1)
      end

      it "maintains original choice min/max in CommonAttributes" do
        choice = GroupSpec::CommonAttributes.choice_attributes.first
        expect(choice.min).to eq(1)
        expect(choice.max).to eq(1)
      end
    end

    context "when updating imported mappings" do
      let(:new_namespace) { "http://www.example.com/new" }
      let(:new_prefix) { "test" }

      context "with element mappings" do
        it "updates the mapping namespace only in `Mrow`" do
          mapping = GroupSpec::Mrow.mappings_for(:xml).elements.find { |e| e.name == :mstyle }
          mapping.instance_variable_set(:@namespace, new_namespace)
          mapping.instance_variable_set(:@prefix, new_prefix)

          expect(mapping.namespace).to eq(new_namespace)
          expect(mapping.prefix).to eq(new_prefix)
        end

        it "maintains original namespace for `mstyle` mapping in `Mfrac`" do
          mapping = GroupSpec::Mfrac.mappings_for(:xml).elements.find { |e| e.name == :mstyle }
          expect(mapping.namespace).to be_nil
          expect(mapping.prefix).to be_nil
        end

        it "maintains original namespace for `mstyle` mapping in `CommonAttributes`" do
          mapping = GroupSpec::CommonAttributes.mappings_for(:xml).elements.find { |e| e.name == :mstyle }
          expect(mapping.namespace).to be_nil
          expect(mapping.prefix).to be_nil
        end
      end

      context "with attribute mappings" do
        it "updates attribute mapping only in `Mrow`" do
          mapping = GroupSpec::Mrow.mappings_for(:xml).attributes.find { |a| a.name == :mcol }
          mapping.instance_variable_set(:@namespace, new_namespace)

          expect(mapping.namespace).to eq(new_namespace)
        end

        it "maintains original attribute mapping in `Mfrac`" do
          mapping = GroupSpec::Mfrac.mappings_for(:xml).attributes.find { |a| a.name == :mcol }
          expect(mapping.namespace).to be_nil
        end

        it "maintains original attribute mapping in `CommonAttributes`" do
          mapping = GroupSpec::CommonAttributes.mappings_for(:xml).attributes.find { |a| a.name == :mcol }
          expect(mapping.namespace).to be_nil
        end
      end

      context "with sequence elements" do
        it "updates sequence elements only in `Mrow`" do
          sequence = GroupSpec::Mrow.mappings_for(:xml).element_sequence.first
          sequence.attributes << Lutaml::Model::Xml::MappingRule.new(
            "new_element",
            to: :new_element,
            namespace: "http://example.com",
            prefix: "test",
          )

          expect(sequence.attributes.map(&:name)).to include("new_element")
        end

        it "maintains original sequence elements in `Mfrac`" do
          original_sequence = GroupSpec::Mfrac.mappings_for(:xml).element_sequence.first
          expect(original_sequence.attributes.map(&:name)).not_to include("new_element")
        end

        it "maintains original sequence elements in `CommonAttributes`" do
          original_sequence = GroupSpec::CommonAttributes.mappings_for(:xml).element_sequence.first
          expect(original_sequence.attributes.map(&:name)).not_to include("new_element")
        end

        it "creates new sequence object with the new mapping object as model of sequence in `Mrow`" do
          mrow_sequence_model = GroupSpec::Mrow.mappings_for(:xml).element_sequence[0].model
          common_attributes_sequence_model = GroupSpec::CommonAttributes.mappings_for(:xml).element_sequence[0].model
          expect(mrow_sequence_model).not_to be(common_attributes_sequence_model)
        end
      end
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
