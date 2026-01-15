require "spec_helper"
require "lutaml/model"

RSpec.describe "Deep namespace inheritance through collections" do
  # This test ensures Bug #3 fix: namespace configuration must be inherited
  # even when child plans are nil (e.g., for collections or circular type refs)

  context "when parent has no namespace and child has prefixed namespace" do
    let(:child_ns) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/child"
        prefix_default "child"
      end
    end

    let(:child_model) do
      ns = child_ns
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "child"
          namespace ns
          map_element "name", to: :name
        end
      end
    end

    let(:parent_model) do
      child_class = child_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :children, child_class, collection: true

        xml do
          element "parent"
          # No namespace - parent has no namespace
          map_element "child", to: :children
        end
      end
    end

    it "preserves child's namespace through inheritance" do
      child1 = child_model.new(name: "First")
      child2 = child_model.new(name: "Second")
      parent = parent_model.new(children: [child1, child2])

      xml = parent.to_xml

      # W3C Rule: When parent uses default namespace (xmlns="..."),
      # children in blank namespace MUST have xmlns="" to opt out
      expected_xml = <<~XML
        <parent>
          <child xmlns="http://example.com/child">
            <name xmlns="">First</name>
          </child>
          <child xmlns="http://example.com/child">
            <name xmlns="">Second</name>
          </child>
        </parent>
      XML

      # Child elements should have their namespace declared individually
      expect(xml).to be_xml_equivalent_to(expected_xml)
    end

    it "handles round-trip serialization correctly" do
      child1 = child_model.new(name: "First")
      parent = parent_model.new(children: [child1])

      xml = parent.to_xml
      parsed = parent_model.from_xml(xml)
      xml2 = parsed.to_xml

      # W3C Rule: <name> element needs xmlns="" to opt out of parent's default namespace
      expected_xml = <<~XML
        <parent>
          <child xmlns="http://example.com/child">
            <name xmlns="">First</name>
          </child>
        </parent>
      XML

      expect(xml2).to be_xml_equivalent_to(expected_xml)
    end
  end

  context "when deeply nested structures have prefixed namespaces" do
    let(:ns) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://example.com/deep"
        prefix_default "deep"
      end
    end

    let(:leaf_model) do
      namespace = ns
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          element "leaf"
          namespace namespace
          map_element "value", to: :value
        end
      end
    end

    let(:branch_model) do
      namespace = ns
      leaf_class = leaf_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :leaves, leaf_class, collection: true

        xml do
          element "branch"
          namespace namespace
          map_element "leaf", to: :leaves
        end
      end
    end

    let(:tree_model) do
      branch_class = branch_model
      Class.new(Lutaml::Model::Serializable) do
        attribute :branches, branch_class, collection: true

        xml do
          element "tree"
          # No namespace at root
          map_element "branch", to: :branches
        end
      end
    end

    it "preserves namespace through all levels" do
      leaf1 = leaf_model.new(value: "A")
      leaf2 = leaf_model.new(value: "B")
      branch1 = branch_model.new(leaves: [leaf1, leaf2])
      tree = tree_model.new(branches: [branch1])

      xml = tree.to_xml

      # W3C Rule: <value> elements are in blank namespace and need xmlns=""
      # when parent <branch> uses default namespace
      expected_xml = <<~XML
        <tree>
          <branch xmlns="http://example.com/deep">
            <leaf>
              <value xmlns="">A</value>
            </leaf>
            <leaf>
              <value xmlns="">B</value>
            </leaf>
          </branch>
        </tree>
      XML

      # Leaf elements inherit the default namespace set at branch level
      expect(xml).to be_xml_equivalent_to(expected_xml)
    end
  end
end