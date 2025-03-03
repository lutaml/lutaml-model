require "spec_helper"

# Simple model with basic attributes
class ComparableGlaze < Lutaml::Model::Serializable
  attribute :color, :string
  attribute :temperature, :integer
  attribute :food_safe, :boolean
end

# Model with a nested Serializable object
class ComparableCeramic < Lutaml::Model::Serializable
  attribute :type, :string
  attribute :glaze, ComparableGlaze
end

# Model with a deeply nested Serializable object
class ComparableCeramicCollection < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :featured_piece, ComparableCeramic # This creates a two-level nesting
end

class RecursiveNode < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :next_node, RecursiveNode
end

RSpec.describe Lutaml::Model::ComparableModel do
  describe "comparisons" do
    context "with simple types (Glaze)" do
      it "compares equal objects with basic attributes" do
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        expect(glaze1).to eq(glaze2)
        expect(glaze1.hash).to eq(glaze2.hash)
      end

      it "compares unequal objects with basic attributes" do
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Red", temperature: 1000,
                                     food_safe: false)
        expect(glaze1).not_to eq(glaze2)
        expect(glaze1.hash).not_to eq(glaze2.hash)
      end
    end

    context "with nested Serializable objects (Ceramic)" do
      it "compares equal objects with one level of nesting" do
        # Here, we're comparing Ceramic objects that contain Glaze objects
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        ceramic1 = ComparableCeramic.new(type: "Bowl", glaze: glaze1)
        ceramic2 = ComparableCeramic.new(type: "Bowl", glaze: glaze2)
        expect(ceramic1).to eq(ceramic2)
        expect(ceramic1.hash).to eq(ceramic2.hash)
      end

      it "compares unequal objects with one level of nesting" do
        # Here, we're comparing Ceramic objects with different Glaze objects
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Red", temperature: 1000,
                                     food_safe: false)
        ceramic1 = ComparableCeramic.new(type: "Bowl", glaze: glaze1)
        ceramic2 = ComparableCeramic.new(type: "Plate", glaze: glaze2)
        expect(ceramic1).not_to eq(ceramic2)
        expect(ceramic1.hash).not_to eq(ceramic2.hash)
      end
    end

    context "with deeply nested Serializable objects (CeramicCollection)" do
      it "compares equal objects with two levels of nesting" do
        # This test compares CeramicCollection objects that contain Ceramic objects,
        # which in turn contain Glaze objects - a two-level deep nesting
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        ceramic1 = ComparableCeramic.new(type: "Bowl", glaze: glaze1)
        ceramic2 = ComparableCeramic.new(type: "Bowl", glaze: glaze2)
        collection1 = ComparableCeramicCollection.new(name: "Blue Collection",
                                                      featured_piece: ceramic1)
        collection2 = ComparableCeramicCollection.new(name: "Blue Collection",
                                                      featured_piece: ceramic2)
        expect(collection1).to eq(collection2)
        expect(collection1.hash).to eq(collection2.hash)
      end

      it "compares unequal objects with two levels of nesting" do
        # This test compares CeramicCollection objects that are different at every level:
        # the collection name, the ceramic type, and the glaze properties
        glaze1 = ComparableGlaze.new(color: "Blue", temperature: 1200,
                                     food_safe: true)
        glaze2 = ComparableGlaze.new(color: "Red", temperature: 1000,
                                     food_safe: false)
        ceramic1 = ComparableCeramic.new(type: "Bowl", glaze: glaze1)
        ceramic2 = ComparableCeramic.new(type: "Plate", glaze: glaze2)
        collection1 = ComparableCeramicCollection.new(name: "Blue Collection",
                                                      featured_piece: ceramic1)
        collection2 = ComparableCeramicCollection.new(name: "Red Collection",
                                                      featured_piece: ceramic2)
        expect(collection1).not_to eq(collection2)
        expect(collection1.hash).not_to eq(collection2.hash)
      end
    end

    context "with recursive relationships" do
      it "handles circular references" do
        node1 = RecursiveNode.new(name: "A")
        node2 = RecursiveNode.new(name: "B")
        node1.next_node = node2
        node2.next_node = node1

        node3 = RecursiveNode.new(name: "A")
        node4 = RecursiveNode.new(name: "B")
        node3.next_node = node4
        node4.next_node = node3

        expect(node1).to eq(node3)
        expect(node1.hash).to eq(node3.hash)
      end

      it "detects differences in recursive structures" do
        node1 = RecursiveNode.new(name: "A")
        node2 = RecursiveNode.new(name: "B")
        node1.next_node = node2
        node2.next_node = node1

        node3 = RecursiveNode.new(name: "A")
        node4 = RecursiveNode.new(name: "Different")
        node3.next_node = node4
        node4.next_node = node3

        expect(node1).not_to eq(node3)
        expect(node1.hash).not_to eq(node3.hash)
      end

      it "keeps the same hash value repeatedly" do
        node = RecursiveNode.new(name: "A")
        hash1 = node.hash
        hash2 = node.hash
        expect(hash1).to eq(hash2)
      end

      it "changes result upon value change" do
        node1 = RecursiveNode.new(name: "A")
        node2 = RecursiveNode.new(name: "B")
        node1.next_node = node2
        node2.next_node = node1

        node3 = RecursiveNode.new(name: "A")
        node4 = RecursiveNode.new(name: "B")
        node3.next_node = node4
        node4.next_node = node3
        expect(node1).to eq(node3)

        node4.name = "Different"
        expect(node1).not_to eq(node3)
      end
    end
  end
end
