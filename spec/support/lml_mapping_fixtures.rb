# frozen_string_literal: true

require "lutaml/model"
require "lutaml/model/lml/exporter"
require "lutaml/model/lml/document_validator"
require_relative "lml_order_fixtures"

# Named source models and a fresh-graph helper for the LML
# MappingCompiler specs (lutaml-model#1033 card 03b). The helper
# declares attributes the way Materialization (03a) does, so these
# specs do not depend on 03a being merged.
module LmlMappingFixtures
  class Ns < Lutaml::Xml::Namespace
    uri "urn:lml-map:a"
    prefix_default "m"
  end

  class Entry < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :value, :string

    xml do
      element "entry"
      map_attribute "name", to: :name
      map_content to: :value
    end
    json do
      map "name", to: :name
      map "value", to: :value
    end
  end

  class Item < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :label, :string

    xml do
      element "item"
      namespace Ns
      map_attribute "id", to: :id
      map_content to: :label, cdata: true
    end
    json do
      map "id", to: :id
      map "label", to: :label
    end
  end

  class Doc < Lutaml::Model::Serializable
    attribute :kind, :string, values: %w[a b], default: "a"
    attribute :title, :string
    attribute :note, :string
    attribute :count, :integer, required: true
    attribute :items, Item, collection: true
    attribute :entries, Entry, collection: 0..5

    xml do
      element "doc"
      namespace Ns
      map_attribute "kind", to: :kind, render_nil: true
      map_element "title", to: :title, render_nil: :as_blank
      map_element "note", to: :note, render_empty: :as_blank, render_default: true,
                          namespace: nil
      map_element "count", to: :count
      map_element "item", to: :items
      map_element "entry", to: :entries
    end
    json do
      map "kind", to: :kind
      map "title", to: :title, render_nil: :as_empty
      map "count", to: :count, render_default: true
      map "items", to: :items
      map "entries", to: :entries
    end
    yaml do
      map "title", to: :title
      map "items", to: :items
    end
  end

  class Circle < Lutaml::Model::Serializable
    attribute :kind, :string
    attribute :radius, :integer
    xml do
      element "circle"
      map_attribute "kind", to: :kind
      map_element "radius", to: :radius
    end
    json do
      map "kind", to: :kind
      map "radius", to: :radius
    end
  end

  class Shape < Lutaml::Model::Serializable
    attribute :child, Circle
    xml do
      element "shape"
      map_element "circle", to: :child
    end
    json do
      map "child", to: :child
    end
  end

  SOURCES = [Doc, Item, Entry, Circle, Shape, LmlOrderFixtures::Para,
             LmlOrderFixtures::Emphasis, LmlOrderFixtures::Transport].freeze

  module_function

  # Neutral bundle (string keys) of the given source classes.
  def bundle_for(*classes)
    models = classes.to_h do |klass|
      doc = Lutaml::Model::Lml::Exporter.project(klass)
      ["#{doc['model']}@#{doc['register']}", doc]
    end.sort.to_h
    { "lml_bundle" => 1, "roots" => models.keys.sort, "models" => models, "value_types" => {},
      "capabilities" => %w[json xml yaml] }
  end

  # The exporter does not project rule-level discriminators or
  # child_mappings yet (see the card report), so specs author them.
  def with_discriminator(bundle, id: "LmlMappingFixtures::Shape@default",
                         target: "LmlMappingFixtures::Circle@default")
    copy = Marshal.load(Marshal.dump(bundle))
    disc = { "attribute" => "kind", "cases" => { "circle" => target } }
    mappings = copy["models"][id]["mappings"]
    mappings["xml"]["rules"][0]["discriminator"] = disc
    mappings["json"]["rules"][0]["discriminator"] = disc
    copy
  end

  def with_child_mappings(bundle, id: "LmlMappingFixtures::Doc@default")
    copy = Marshal.load(Marshal.dump(bundle))
    rule = copy["models"][id]["mappings"]["json"]["rules"].find { |r| r["to"] == "entries" }
    rule["child_mappings"] = { "name" => "key", "value" => "value" }
    copy
  end

  # Fresh classes (attributes only) installed under +holder+, keyed by
  # model id. +prefix+ lets the same bundle be built into two holders.
  def fresh_classes(bundle, holder)
    classes = bundle["models"].to_h do |id, doc|
      klass = Class.new(Lutaml::Model::Serializable)
      holder.const_set(doc["model"].split("::").last, klass)
      [id, klass]
    end
    bundle["models"].each { |id, doc| declare_attributes(classes[id], doc, classes) }
    classes
  end

  def declare_attributes(klass, doc, classes)
    doc["attributes"].each do |attr|
      type = attr["type"]
      type = type["kind"] == "model" ? classes.fetch(type["id"]) : type["name"].to_sym
      options = {}
      options[:required] = true if attr["required"]
      options[:values] = attr["values"] if attr["values"]
      options[:default] = attr["default"]["value"] if attr.dig("default", "present")
      options[:collection] = collection(attr["collection"]) if attr["collection"]
      klass.attribute(attr["name"].to_sym, type, **options)
    end
  end

  def collection(spec)
    return true if spec == true

    spec["min"]..(spec["max"] || Float::INFINITY)
  end
end
