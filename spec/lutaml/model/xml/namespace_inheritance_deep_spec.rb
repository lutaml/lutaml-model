require "spec_helper"
require "lutaml/model"

RSpec.describe "Deep namespace inheritance through collections" do
  # This test ensures Bug #3 fix: namespace configuration must be inherited
  # even when child plans are nil (e.g., for collections or circular type refs)
  
  context "when parent has no namespace and child has prefixed namespace" do
    let(:child_ns) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/child"
        prefix_default "child"
      end
    end
    
    let(:child_model) do
      ns = child_ns
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        
        xml do
          root "child"
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
          root "parent"
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
      
      # Child namespace declaration should be present with prefix format
      # (prefix is used because parent has no namespace)
      expect(xml).to include('xmlns:child="http://example.com/child"')
      
      # Child elements should use the child prefix consistently
      expect(xml).to include('<child:child')
      expect(xml).to include('<child:name>First</child:name>')
      expect(xml).to include('<child:name>Second</child:name>')
      expect(xml).to include('</child:child>')
    end
    
    it "handles round-trip serialization correctly" do
      child1 = child_model.new(name: "First")
      parent = parent_model.new(children: [child1])
      
      xml = parent.to_xml
      parsed = parent_model.from_xml(xml)
      xml2 = parsed.to_xml
      
      # Second serialization should match first namespace with prefix format
      expect(xml2).to include('xmlns:child="http://example.com/child"')
      expect(xml2).to include('<child:child')
      expect(xml2).to include('<child:name>First</child:name>')
    end
  end
  
  context "when deeply nested structures have prefixed namespaces" do
    let(:ns) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/deep"
        prefix_default "deep"
      end
    end
    
    let(:leaf_model) do
      namespace = ns
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string
        
        xml do
          root "leaf"
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
          root "branch"
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
          root "tree"
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
      
      # Namespace should be declared with prefix format
      # (prefix is used because root has no namespace)
      expect(xml).to include('xmlns:deep="http://example.com/deep"')
      
      # All levels should be namespaced with deep prefix
      expect(xml).to include('<deep:branch')
      expect(xml).to include('<deep:leaf')
      expect(xml).to include('<deep:value>A</deep:value>')
      expect(xml).to include('<deep:value>B</deep:value>')
      expect(xml).to include('</deep:leaf>')
      expect(xml).to include('</deep:branch>')
    end
  end
end