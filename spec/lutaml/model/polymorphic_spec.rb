require "spec_helper"

module PolymorphicSpec
  module Base
    class Reference < Lutaml::Model::Serializable
      attribute :_class, :string, polymorphic_class: true
      attribute :name, :string

      xml do
        map_attribute "reference-type", to: :_class, polymorphic_map: {
          "document-ref" => "PolymorphicSpec::Base::DocumentReference",
          "anchor-ref" => "PolymorphicSpec::Base::AnchorReference",
        }
        map_element "name", to: :name
      end

      key_value do
        map "_class", to: :_class, polymorphic_map: {
          "Document" => "PolymorphicSpec::Base::DocumentReference",
          "Anchor" => "PolymorphicSpec::Base::AnchorReference",
        }
        map "name", to: :name
      end
    end

    class DocumentReference < Reference
      attribute :document_id, :string

      xml do
        map_element "document_id", to: :document_id
      end

      key_value do
        map "document_id", to: :document_id
      end
    end

    class AnchorReference < Reference
      attribute :anchor_id, :string

      xml do
        map_element "anchor_id", to: :anchor_id
      end

      key_value do
        map "anchor_id", to: :anchor_id
      end
    end

    module InvalidClasses
      class AnchorReference < Lutaml::Model::Serializable
        attribute :anchor_id, :string

        xml do
          map_element "anchor_id", to: :anchor_id
        end

        key_value do
          map "anchor_id", to: :anchor_id
        end
      end

      class DocumentReference < Reference
        attribute :document_id, :string

        xml do
          map_element "document_id", to: :document_id
        end

        key_value do
          map "document_id", to: :document_id
        end
      end
    end

    class ReferenceSet < Lutaml::Model::Serializable
      attribute :references, Reference, collection: true, polymorphic: [
        DocumentReference,
        AnchorReference,
      ]
    end

    class SimpleReferenceSet < Lutaml::Model::Serializable
      attribute :references, Reference, collection: true, polymorphic: true

      xml do
        element "ReferenceSet"
        map_element "references", to: :references, polymorphic: {
          attribute: "reference-type",
          class_map: {
            "document-ref" => "PolymorphicSpec::Base::DocumentReference",
            "anchor-ref" => "PolymorphicSpec::Base::AnchorReference",
          },
        }
      end

      key_value do
        map "references", to: :references, polymorphic: {
          attribute: "_class",
          class_map: {
            "Document" => "PolymorphicSpec::Base::DocumentReference",
            "Anchor" => "PolymorphicSpec::Base::AnchorReference",
          },
        }
      end
    end
  end

  module Child
    # Case: If we have no access to the base class and we need to
    # define polymorphism in the sub-classes.
    class Reference < Lutaml::Model::Serializable
      attribute :name, :string

      xml do
        map_element "name", to: :name
      end

      key_value do
        map "name", to: :name
      end
    end

    class DocumentReference < Reference
      attribute :_class, :string
      attribute :document_id, :string

      xml do
        map_element "document_id", to: :document_id
        map_attribute "_class", to: :_class
      end

      key_value do
        map "document_id", to: :document_id
        map "_class", to: :_class
      end
    end

    class AnchorReference < Reference
      attribute :_class, :string
      attribute :anchor_id, :string

      xml do
        map_element "anchor_id", to: :anchor_id
        map_attribute "_class", to: :_class
      end

      key_value do
        map "anchor_id", to: :anchor_id
        map "_class", to: :_class
      end
    end

    class ReferenceSet < Lutaml::Model::Serializable
      attribute :references, Reference, collection: true, polymorphic: [
        DocumentReference,
        AnchorReference,
      ]

      xml do
        element "ReferenceSet"

        map_element "references", to: :references, polymorphic: {
          # This refers to the attribute in the polymorphic model, you need
          # to specify the attribute name (which is specified in the sub-classed model).
          attribute: "_class",
          class_map: {
            "document-ref" => "PolymorphicSpec::Child::DocumentReference",
            "anchor-ref" => "PolymorphicSpec::Child::AnchorReference",
          },
        }
      end

      key_value do
        map "references", to: :references, polymorphic: {
          attribute: "_class",
          class_map: {
            "Document" => "PolymorphicSpec::Child::DocumentReference",
            "Anchor" => "PolymorphicSpec::Child::AnchorReference",
          },
        }
      end
    end
  end
end

RSpec.describe "Polymorphic" do
  context "when defined in base class" do
    context "when key_value formats" do
      let(:reference_set) do
        PolymorphicSpec::Base::ReferenceSet.new(
          references: [
            PolymorphicSpec::Base::DocumentReference.new(
              _class: "Document",
              document_id: "book:tbtd",
              name: "The Tibetan Book of the Dead",
            ),
            PolymorphicSpec::Base::AnchorReference.new(
              _class: "Anchor",
              anchor_id: "book:tbtd:anchor-1",
              name: "Chapter 1",
            ),
          ],
        )
      end

      let(:yaml) do
        <<~YAML
          ---
          references:
          - _class: Document
            name: The Tibetan Book of the Dead
            document_id: book:tbtd
          - _class: Anchor
            name: Chapter 1
            anchor_id: book:tbtd:anchor-1
        YAML
      end

      let(:parsed_yaml) do
        PolymorphicSpec::Base::ReferenceSet.from_yaml(yaml)
      end

      it "deserializes correctly" do
        expect(parsed_yaml).to eq(reference_set)
      end

      it "serializes correctly" do
        expect(parsed_yaml.to_yaml).to eq(yaml)
      end
    end

    context "when XML format" do
      let(:reference_set) do
        PolymorphicSpec::Base::ReferenceSet.new(
          references: [
            PolymorphicSpec::Base::DocumentReference.new(
              _class: "document-ref",
              document_id: "book:tbtd",
              name: "The Tibetan Book of the Dead",
            ),
            PolymorphicSpec::Base::AnchorReference.new(
              _class: "anchor-ref",
              anchor_id: "book:tbtd:anchor-1",
              name: "Chapter 1",
            ),
          ],
        )
      end

      let(:xml) do
        <<~XML
          <ReferenceSet>
            <references reference-type="document-ref">
              <name>The Tibetan Book of the Dead</name>
              <document_id>book:tbtd</document_id>
            </references>
            <references reference-type="anchor-ref">
              <name>Chapter 1</name>
              <anchor_id>book:tbtd:anchor-1</anchor_id>
            </references>
          </ReferenceSet>
        XML
      end

      let(:parsed_xml) do
        PolymorphicSpec::Base::ReferenceSet.from_xml(xml)
      end

      it "deserializes correctly" do
        expect(parsed_xml).to eq(reference_set)
      end

      it "serializes correctly" do
        expect(parsed_xml.to_xml.strip).to be_xml_equivalent_to(xml.strip)
      end
    end
  end

  context "when using polymorphic: true option" do
    context "when key_value formats" do
      let(:reference_set) do
        PolymorphicSpec::Base::SimpleReferenceSet.new(
          references: [
            PolymorphicSpec::Base::DocumentReference.new(
              _class: "Document",
              document_id: "book:tbtd",
              name: "The Tibetan Book of the Dead",
            ),
            PolymorphicSpec::Base::AnchorReference.new(
              _class: "Anchor",
              anchor_id: "book:tbtd:anchor-1",
              name: "Chapter 1",
            ),
          ],
        )
      end

      let(:invalid_reference_set) do
        PolymorphicSpec::Base::SimpleReferenceSet.new(
          references: [
            PolymorphicSpec::Base::InvalidClasses::DocumentReference.new(
              _class: "Document",
              document_id: "book:tbtd",
              name: "The Tibetan Book of the Dead",
            ),
            PolymorphicSpec::Base::InvalidClasses::AnchorReference.new(
              _class: "Anchor",
              anchor_id: "book:tbtd:anchor-1",
              name: "Chapter 1",
            ),
          ],
        )
      end

      let(:yaml) do
        <<~YAML
          ---
          references:
          - _class: Document
            name: The Tibetan Book of the Dead
            document_id: book:tbtd
          - _class: Anchor
            name: Chapter 1
            anchor_id: book:tbtd:anchor-1
        YAML
      end

      let(:parsed_yaml) do
        PolymorphicSpec::Base::SimpleReferenceSet.from_yaml(yaml)
      end

      let(:error_message) do
        "PolymorphicSpec::Base::InvalidClasses::AnchorReference is not " \
          "valid sub class of PolymorphicSpec::Base::Reference"
      end

      it "deserializes correctly" do
        expect(parsed_yaml).to eq(reference_set)
      end

      it "serializes correctly" do
        expect(parsed_yaml.to_yaml).to eq(yaml)
      end

      it "raises error" do
        expect do
          invalid_reference_set.validate!
        end.to raise_error(Lutaml::Model::ValidationError, error_message)
      end
    end

    context "when XML format" do
      let(:reference_set) do
        PolymorphicSpec::Base::SimpleReferenceSet.new(
          references: [
            PolymorphicSpec::Base::DocumentReference.new(
              _class: "document-ref",
              document_id: "book:tbtd",
              name: "The Tibetan Book of the Dead",
            ),
            PolymorphicSpec::Base::AnchorReference.new(
              _class: "anchor-ref",
              anchor_id: "book:tbtd:anchor-1",
              name: "Chapter 1",
            ),
          ],
        )
      end
      let(:xml) do
        <<~XML
          <ReferenceSet>
            <references reference-type="document-ref">
              <name>The Tibetan Book of the Dead</name>
              <document_id>book:tbtd</document_id>
            </references>
            <references reference-type="anchor-ref">
              <name>Chapter 1</name>
              <anchor_id>book:tbtd:anchor-1</anchor_id>
            </references>
          </ReferenceSet>
        XML
      end

      let(:parsed_xml) do
        PolymorphicSpec::Base::SimpleReferenceSet.from_xml(xml)
      end

      it "deserializes correctly" do
        expect(parsed_xml).to eq(reference_set)
      end

      it "serializes correctly" do
        expect(parsed_xml.to_xml.strip).to be_xml_equivalent_to(xml.strip)
      end

      it "does not raise error if polymorphic is set to true" do
        expect { reference_set.validate! }.not_to raise_error
      end

      it "has empty errors array on validate" do
        expect(reference_set.validate).to eq([])
      end
    end
  end

  context "when defined in child class" do
    context "when key_value formats" do
      let(:reference_set) do
        PolymorphicSpec::Base::ReferenceSet.new(
          references: [
            PolymorphicSpec::Base::DocumentReference.new(
              _class: "Document",
              document_id: "book:tbtd",
              name: "The Tibetan Book of the Dead",
            ),
            PolymorphicSpec::Base::AnchorReference.new(
              _class: "Anchor",
              anchor_id: "book:tbtd:anchor-1",
              name: "Chapter 1",
            ),
          ],
        )
      end

      let(:yaml) do
        <<~YAML
          ---
          references:
          - _class: Document
            name: The Tibetan Book of the Dead
            document_id: book:tbtd
          - _class: Anchor
            name: Chapter 1
            anchor_id: book:tbtd:anchor-1
        YAML
      end

      let(:parsed_yaml) do
        PolymorphicSpec::Base::ReferenceSet.from_yaml(yaml)
      end

      it "deserializes correctly" do
        expect(parsed_yaml).to eq(reference_set)
      end

      it "serializes correctly" do
        expect(parsed_yaml.to_yaml).to eq(yaml)
      end
    end

    context "when XML format" do
      let(:reference_set) do
        PolymorphicSpec::Child::ReferenceSet.new(
          references: [
            PolymorphicSpec::Child::DocumentReference.new(
              _class: "document-ref",
              document_id: "book:tbtd",
              name: "The Tibetan Book of the Dead",
            ),
            PolymorphicSpec::Child::AnchorReference.new(
              _class: "anchor-ref",
              anchor_id: "book:tbtd:anchor-1",
              name: "Chapter 1",
            ),
          ],
        )
      end

      let(:invalid_ref) do
        PolymorphicSpec::Child::ReferenceSet.new(
          references: [
            PolymorphicSpec::Child::DocumentReference.new(
              _class: "document-ref",
              document_id: "book:tbtd",
              name: "The Tibetan Book of the Dead",
            ),
            PolymorphicSpec::Base::AnchorReference.new(
              _class: "anchor-ref",
              anchor_id: "book:tbtd:anchor-1",
              name: "Chapter 1",
            ),
          ],
        )
      end

      let(:xml) do
        <<~XML
          <ReferenceSet>
            <references _class="document-ref">
              <name>The Tibetan Book of the Dead</name>
              <document_id>book:tbtd</document_id>
            </references>
            <references _class="anchor-ref">
              <name>Chapter 1</name>
              <anchor_id>book:tbtd:anchor-1</anchor_id>
            </references>
          </ReferenceSet>
        XML
      end

      let(:parsed_xml) do
        PolymorphicSpec::Child::ReferenceSet.from_xml(xml)
      end

      it "deserializes correctly" do
        expect(parsed_xml).to eq(reference_set)
      end

      it "serializes correctly" do
        expect(parsed_xml.to_xml.strip).to be_xml_equivalent_to(xml.strip)
      end

      it "does not raises error for valid polymorphic class" do
        expect { reference_set.validate! }.not_to raise_error
      end

      it "raises error if polymorphic class is not in list" do
        expect do
          invalid_ref.validate!
        end.to raise_error(Lutaml::Model::ValidationError) do |error|
          expect(error).to include(Lutaml::Model::PolymorphicError)
          expect(error.error_messages).to include("PolymorphicSpec::Base::AnchorReference not in [PolymorphicSpec::Child::DocumentReference, PolymorphicSpec::Child::AnchorReference]")
        end
      end
    end
  end
end
