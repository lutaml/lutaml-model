# frozen_string_literal: true

require "spec_helper"

# lutaml-model#811: the parse path re-resolved per (element × rule) what is
# static per (attribute/rule, register). These guards pin the hoisting
# contracts: register-keyed type caching with replacement invalidation,
# the lock-free child-register resolution, per-rule treatment flags, and
# the transform dispatch verdicts.
RSpec.describe "parse-path dispatch hoisting" do
  describe "Attribute#type register caching" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string
      end
    end

    it "returns the same resolved class for a repeated register" do
      attr = klass.attributes[:value]
      expect(attr.type(:default)).to equal(attr.type(:default))
    end

    it "does not pin an unregistered register to the thread default" do
      attr = klass.attributes[:value]
      expect(attr.type(:nonexistent_register)).to eq(Lutaml::Model::Type::String)
    end

    it "re-resolves when a context is replaced under the same id" do
      attr = klass.attributes[:value]

      build_context = lambda do |string_type|
        Lutaml::Model::TypeContext.new(
          id: :hoist_test,
          registry: Lutaml::Model::TypeRegistry.new.tap do |r|
            r.register(:string, string_type)
          end,
        )
      end

      Lutaml::Model::GlobalContext.register_context(
        build_context.call(Lutaml::Model::Type::String),
      )
      expect(attr.type(:hoist_test)).to equal(Lutaml::Model::Type::String)
      expect(attr.type(:hoist_test)).to equal(Lutaml::Model::Type::String)

      Lutaml::Model::GlobalContext.register_context(
        build_context.call(Lutaml::Model::Type::Integer),
      )
      expect(attr.type(:hoist_test)).to equal(Lutaml::Model::Type::Integer)

      Lutaml::Model::GlobalContext.unregister_context(:hoist_test)
    end
  end

  describe "Register.resolve_for_child" do
    it "caches a nil answer without recomputing" do
      klass = Class.new(Lutaml::Model::Serializable)
      expect(Lutaml::Model::Register.resolve_for_child(klass, nil)).to be_nil
      expect(Lutaml::Model::Register.resolve_for_child(klass, nil)).to be_nil
    end

    it "resolves the child's own default register over the parent's" do
      klass = Class.new(Lutaml::Model::Serializable) do
        def self.lutaml_default_register
          :child_default
        end
      end
      expect(Lutaml::Model::Register.resolve_for_child(klass, :other)).to eq(:child_default)
      expect(Lutaml::Model::Register.resolve_for_child(klass, nil)).to eq(:child_default)
    end
  end

  describe "MappingRule treatment flags" do
    def rule_with(treat_nil: :nil, treat_empty: :empty, treat_omitted: :nil)
      Lutaml::Model::MappingRule.new(
        "name", to: :name,
                treat_nil: treat_nil, treat_empty: treat_empty,
                treat_omitted: treat_omitted
      )
    end

    it "computes the same answers as the value_map walk" do
      rule = rule_with(treat_omitted: :omitted, treat_nil: :omitted)
      expect(rule.treat_omitted?).to be(false)
      expect(rule.treat_nil?).to be(false)
      expect(rule.treat_empty?).to be(true)

      expect(rule.treat_omitted?({})).to eq(rule.treat_omitted?)
      expect(rule.treat_nil?({})).to eq(rule.treat_nil?)
    end

    it "honors per-call overrides over the precomputed flags" do
      rule = rule_with
      expect(rule.treat_omitted?).to be(true)
      expect(rule.treat_omitted?({ omitted: :omitted })).to be(false)
      expect(rule.treat_nil?({ nil: :omitted })).to be(false)
      expect(rule.treat_empty?({ empty: :omitted })).to be(false)
    end
  end

  describe "transform dispatch" do
    let(:base) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :plain, :string
        attribute :mapped, :string
      end
    end

    it "assigns directly for a rule without transformers" do
      rule = Lutaml::Model::MappingRule.new("mapped", to: :mapped)
      expect(Lutaml::Model::MappingRule.transform_dispatch(
               rule, base.attributes[:mapped]
             )).to be(:assign)
    end

    it "routes hash transformers through ImportTransformer" do
      rule = Lutaml::Model::MappingRule.new(
        "mapped", to: :mapped,
                  transform: { import: ->(v) { v.to_s.upcase } }
      )
      expect(Lutaml::Model::MappingRule.transform_dispatch(
               rule, base.attributes[:mapped]
             )).to be(:import)
    end

    it "applies an import transform through a real round trip" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :shout, :string

        xml do
          element "doc"
          map_element "shout", to: :shout,
                               transform: { import: ->(v) { v.to_s.upcase } }
        end
      end

      expect(klass.from_xml("<doc><shout>soft</shout></doc>").shout).to eq("SOFT")
    end
  end

  describe "uninitialized defaults are cached" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :nothing, :string
      end
    end

    it "returns the same uninitialized sentinel without re-casting" do
      attr = klass.attributes[:nothing]
      expect(attr.default(:default)).to equal(attr.default(:default))
      expect(attr.default(:default)).to equal(
        Lutaml::Model::UninitializedClass.instance,
      )
    end
  end

  describe "html-entities decode flag" do
    it "memoizes per class without changing the answer" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :body, :string

        xml do
          element "doc"
          map_element "body", to: :body
          html_entities
        end
      end

      expect(klass.from_xml("<doc><body>a &amp; b</body></doc>").body).to eq("a & b")
      expect(klass.from_xml("<doc><body>a &amp; b</body></doc>").body).to eq("a & b")
    end
  end
end
