# frozen_string_literal: true

# Named stand-in classes plus an injectable v2 projector for the LML graph
# exporter specs. The projector is table driven: it returns the declared
# document for (class, register), exactly the callable shape GraphExporter
# expects, with no dependency on the real single-model exporter.
module LmlGraphFixtures
  class Node
    def self.model?
      true
    end
  end

  class Left
    def self.model?
      true
    end
  end

  class Right
    def self.model?
      true
    end
  end

  class Leaf
    def self.model?
      true
    end
  end

  class Shape
    def self.model?
      true
    end
  end

  class Circle
    def self.model?
      true
    end
  end

  class Square
    def self.model?
      true
    end
  end

  class Holder
    def self.model?
      true
    end
  end

  class Substitute
    def self.model?
      true
    end
  end

  def self.model_ref(id)
    { "kind" => "model", "id" => id }
  end

  def self.attribute(name, type)
    { "name" => name, "type" => type, "required" => false }
  end

  def self.document(klass, register, attributes = [], extra = {})
    {
      "lml" => 2, "model" => klass.name, "register" => register,
      "attributes" => attributes,
      "mappings" => { "xml" => { "rules" => [] } }
    }.merge(extra)
  end

  # Returns a projector lambda. +overrides+ maps "Model@register" => hash
  # and replaces the built-in table; +calls+ records every invocation.
  def self.projector(overrides = {}, calls = [])
    table = {
      "#{Node.name}@default" => ->(r) { document(Node, r, [attribute("children", model_ref("#{Node.name}@#{r}"))]) },
      "#{Left.name}@default" => ->(r) { document(Left, r, [attribute("right", model_ref("#{Right.name}@#{r}"))]) },
      "#{Right.name}@default" => ->(r) { document(Right, r, [attribute("left", model_ref("#{Left.name}@#{r}"))]) },
      "#{Leaf.name}@default" => ->(r) { document(Leaf, r) },
      "#{Shape.name}@default" => lambda { |r|
        document(Shape, r, [attribute("kind", { "kind" => "builtin", "name" => "string" }).merge(
          "discriminator" => { "attribute" => "kind",
                               "cases" => { "c" => "#{Circle.name}@#{r}", "s" => "#{Square.name}@#{r}" } },
        )])
      },
      "#{Circle.name}@default" => ->(r) { document(Circle, r) },
      "#{Square.name}@default" => ->(r) { document(Square, r) },
      "#{Holder.name}@default" => lambda { |r|
        document(Holder, r, [attribute("size", { "kind" => "value", "id" => "Size" })],
                 "value_types" => { "Size" => { "base" => "integer", "facets" => {} } })
      },
    }
    lambda do |klass, register|
      calls << [klass, register]
      key = "#{klass.name}@#{register}"
      return overrides.fetch(key) if overrides.key?(key)

      builder = table["#{klass.name}@default"] or raise "no fixture for #{key}"
      builder.call(register)
    end
  end
end
