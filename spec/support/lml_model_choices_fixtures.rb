# frozen_string_literal: true

require "lutaml/model"
require "lutaml/model/lml"

module LmlModelChoicesFixtures
  class Plain < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      attribute :a, :string
      attribute :b, :string
    end
    json do 
      map "a", to: :a
      map "b", to: :b
    end
    xml do 
      root "choice"
      map_element "a", to: :a
      map_element "b", to: :b
    end
  end

  class Nested < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      choice(min: 1, max: 1) do
        attribute :a, :string
        attribute :b, :string
      end
      attribute :c, :string
    end
    json do 
      map "a", to: :a
      map "b", to: :b
      map "c", to: :c
    end
    xml do 
      root "choice"
      map_element "a", to: :a
      map_element "b", to: :b
      map_element "c", to: :c
    end
  end

  class OptionalCollection < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      attribute :a, :string, collection: 0..2
      attribute :b, :string
    end
    json do 
      map "a", to: :a
      map "b", to: :b
    end
    xml do 
      root "choice"
      map_element "a", to: :a
      map_element "b", to: :b
    end
  end

  class BooleanMember < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      attribute :a, :boolean
      attribute :b, :string
    end
    json do 
      map "a", to: :a
      map "b", to: :b
    end
    xml do 
      root "choice"
      map_element "a", to: :a
      map_element "b", to: :b
    end
  end
end

module LmlModelChoicesFixtures
  class Renderable < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      attribute :a, :string
      attribute :b, :string
    end
    json do 
      map "a", to: :a
      map "b", to: :b
    end
    xml do
      root "choice"
      map_element "a", to: :a, render_empty: true
      map_element "b", to: :b, render_empty: true
    end
  end

  class Unbounded < Lutaml::Model::Serializable
    choice(min: 1, max: Float::INFINITY) do
      attribute :a, :string, collection: 1..2
      attribute :b, :string
    end
    json do 
      map "a", to: :a
      map "b", to: :b
    end
    xml do 
      root "choice"
      map_element "a", to: :a
      map_element "b", to: :b
    end
  end

  class NestedOptional < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      choice(min: 0, max: 1) do
        attribute :a, :string
        attribute :b, :string
      end
      attribute :c, :string
    end
    json do 
      map "a", to: :a
      map "b", to: :b
      map "c", to: :c
    end
    xml do 
      root "choice"
      map_element "a", to: :a
      map_element "b", to: :b
      map_element "c", to: :c
    end
  end

  class Parent < Lutaml::Model::Serializable
    attribute :child, Plain
    json { map "child", to: :child }
    xml do 
      root "parent"
      map_element "child", to: :child
    end
  end
  CASES = {
    "Plain" => [{}, { a: nil }, { a: "" }, { a: " " }, { a: "x" }, { b: "y" }, { a: "x", b: "y" }],
    "Nested" => [{}, { a: "x" }, { b: "y" }, { c: "z" }, { a: "x", b: "y" }, { a: "x", c: "z" }],
    "OptionalCollection" => [{}, { a: [] }, { a: ["x"] }, { a: ["x", "y"] }, { a: ["x", "y", "z"] }, { b: "y" }, { a: ["x"], b: "y" }],
    "BooleanMember" => [{}, { a: false }, { a: true }, { a: false, b: "y" }],
  }.merge(
    "Renderable" => [{}, { a: "" }, { a: "", b: "" }],
    "Unbounded" => [{}, { a: [] }, { a: ["x"] }, { a: ["x", "y", "z"] }, { a: ["x"], b: "y" }],
    "NestedOptional" => [{}, { a: "x" }, { c: "z" }, { a: "x", b: "y" }, { a: "x", c: "z" }],
    "Parent" => [{}, { child: {} }, { child: { a: "x" } }, { child: { a: "x", b: "y" } }],
  ).freeze
end
