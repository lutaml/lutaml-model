require "spec_helper"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::XmlCompiler do
  describe "required_files list" do
    describe ".resolve_required_files" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
        end

        let(:content) do
          {
            attribute_groups: {},
            complex_content: {},
            simple_content: {},
            attributes: {},
            sequence: {},
            choice: {},
            group: {}
          }
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:resolve_required_files, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq([])
        end
      end
    end

    describe ".required_files_simple_content" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
        end

        let(:content) do
          {
            extension_base: {},
            attributes: {},
            extension: {},
            restriction: {}
          }
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_simple_content, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq([])
        end
      end
    end

    describe ".required_files_complex_content" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
        end

        let(:content) do
          {
            extension: {},
            restriction: {}
          }
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_complex_content, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq([])
        end
      end
    end

    describe ".required_files_extension" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
        end

        let(:content) do
          {
            attribute_group: {},
            extension_base: {},
            attributes: {},
            attribute: {},
            sequence: {},
            choice: {}
          }
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_extension, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq([])
        end
      end
    end

    describe ".required_files_restriction" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
        end

        let(:content) do
          { base: "testId" }
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_restriction, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq(["test_id"])
        end
      end
    end

    describe ".required_files_attribute_groups" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
          described_class.instance_variable_set(:@attribute_groups, attribute_groups)
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
          described_class.instance_variable_set(:@attribute_groups, nil)
        end

        let(:attribute_groups) { { "testId" => {} } }

        let(:content) do
          {
            ref_class: "testId",
            attributes: {},
            attribute: {}
          }
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_attribute_groups, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq([])
        end
      end
    end

    describe ".required_files_attribute" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
          described_class.instance_variable_set(:@attributes, attributes)
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
          described_class.instance_variable_set(:@attributes, nil)
        end

        let(:attributes) do
          {
            "testRef" => to_mapping_hash({base_class: "ST_Attr1"})
          }
        end

        let(:content) do
          [
            to_mapping_hash({ ref_class: "testRef" }),
            to_mapping_hash({ base_class: "ST_Attr2" })
          ]
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_attribute, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq(["st_attr1", "st_attr2"])
        end
      end
    end

    describe ".required_files_choice" do
      context "when elements are given" do
        before { described_class.instance_variable_set(:@required_files, []) }
        after { described_class.instance_variable_set(:@required_files, nil) }

        let(:content) do
          {
            "testRef" => to_mapping_hash({type_name: "ST_Attr1"}),
            sequence: {},
            element: {},
            choice: {},
            group: {}
          }
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_choice, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq(["st_attr1"])
        end
      end
    end

    describe ".required_files_group" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
          described_class.instance_variable_set(:@group_types, group_types)
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
          described_class.instance_variable_set(:@group_types, nil)
        end

        let(:group_types) { { "testRef" => {} } }
        let(:content) do
          {
            ref_class: "testRef",
            sequence: {},
            choice: {}
          }
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_group, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq([])
        end
      end
    end

    describe ".required_files_sequence" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
        end

        let(:content) do
          {
            elements: {},
            sequence: {},
            groups: {},
            choice: {}
          }
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_sequence, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq([])
        end
      end
    end

    describe ".required_files_elements" do
      context "when elements are given" do
        before do
          described_class.instance_variable_set(:@required_files, [])
          described_class.instance_variable_set(:@elements, elements)
        end

        after do
          described_class.instance_variable_set(:@required_files, nil)
          described_class.instance_variable_set(:@elements, nil)
        end

        let(:elements) do
          {
            "CT_Element1" => to_mapping_hash({type_name: "w:CT_Element1"})
          }
        end

        let(:content) do
          [
            to_mapping_hash({ ref_class: "CT_Element1" }),
            to_mapping_hash({ type_name: "CT_Element2" })
          ]
        end

        it "populates @required_files variable with the names of the required files" do
          described_class.send(:required_files_elements, content)
          expect(described_class.instance_variable_get(:@required_files)).to eq(["ct_element1", "ct_element2"])
        end
      end
    end
  end
end


def to_mapping_hash(content)
  Lutaml::Model::MappingHash.new.merge(content)
end
