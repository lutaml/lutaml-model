# frozen_string_literal: true

require "lutaml/model"
require_relative "../../fixtures/lml_serialization_hooks/models"
require_relative "../../fixtures/lml_default_binding/models"

# Regressions found by the adversarial review of the LML exporter, hooks and
# namespace work (part of lutaml/lutaml-model#1033).
RSpec.describe "LML review fixes" do
  let(:lml) { Lutaml::Model::Lml }
  let(:hooks) { LmlSerializationHookFixtures }

  def refusal_of
    yield
    nil
  rescue Lutaml::Model::Lml::RejectedError => e
    e
  end

  describe "attribute_form_default :qualified round-trips" do
    let(:ns) do
      Class.new(Lutaml::Xml::Namespace) do
        uri "urn:q"
        prefix_default "q"
        attribute_form_default :qualified
      end
    end

    def qualified_model(namespace, prefix_name, collection: false, **rule)
      stub_const(prefix_name, Class.new(Lutaml::Model::Serializable) do
        attribute :x, :string, collection: collection
        xml do
          element "r"
          namespace namespace
          map_attribute "x", to: :x, **rule
        end
      end)
    end

    it "verifies and imports a model whose attributes are qualified by the namespace default" do
      klass = qualified_model(ns, "LmlQualifiedAttr")
      bundle = lml.export_bundle(klass)

      expect { lml.verify_materialization(bundle) }.not_to raise_error
      expect { lml.import_bundle(bundle, namespace: stub_const("LmlQualifiedHolder", Module.new)) }.not_to raise_error
    end

    it "round-trips a collection attribute and an explicit form: :qualified rule" do
      plain_ns = Class.new(Lutaml::Xml::Namespace) { uri "urn:d" }
      [qualified_model(ns, "LmlQualifiedList", collection: true),
       qualified_model(plain_ns, "LmlQualifiedForm", form: :qualified)].each do |klass|
        expect { lml.verify_materialization(lml.export_bundle(klass)) }.not_to raise_error
      end
    end

    it "keeps the imported attribute qualified" do
      klass = qualified_model(ns, "LmlQualifiedXml")
      holder = stub_const("LmlQualifiedXmlHolder", Module.new)
      imported = lml.import_bundle(lml.export_bundle(klass), namespace: holder).values.first

      expect(imported.new(x: "1").to_xml).to include('q:x="1"')
    end
  end

  describe "hook names share one rule" do
    let(:bundle) { lml.export_bundle(hooks::Measure) }

    def tampered(name, direction: "to")
      tree = Marshal.load(Marshal.dump(bundle.to_h))
      rule = tree["models"].values.first["mappings"]["json"]["rules"].find { |r| r["key"] == ["category"] }
      rule["custom"] = { direction => name }
      tree
    end

    %w[initialize class hash send __send__ object_id method_missing to_json amount category].each do |name|
      it "refuses to import a hook named #{name}" do
        error = refusal_of { lml.import_bundle(tampered(name), namespace: stub_const("LmlHookH", Module.new)) }

        expect(error&.detail).to include("hook name").and include("already has")
      end
    end

    it "does not depend on top-level methods other files happened to define" do
      name = "lml_toplevel_probe_hook"
      expect(Lutaml::Model::Lml::HandwrittenSerialization.hook_name_problem(name)).to be_nil

      Object.send(:define_method, name) { |*| nil }
      begin
        expect(Object.private_method_defined?(name) || Object.method_defined?(name)).to be(true)
        expect(Lutaml::Model::Lml::HandwrittenSerialization.hook_name_problem(name)).to be_nil
        # a genuinely inherited name is still refused
        expect(Lutaml::Model::Lml::HandwrittenSerialization.hook_name_problem("send"))
          .to include("already has")
      ensure
        Object.send(:remove_method, name)
      end
    end

    ["has space", "é", "a\nb", "", "foo?"].each do |name|
      it "refuses to export or import the hook name #{name.inspect}" do
        klass = stub_const("LmlBadHook", Class.new(Lutaml::Model::Serializable) do
          attribute :v, :string
          json { map "v", with: { to: name.to_sym, from: :ok_from } }
        end)

        expect(refusal_of { lml.export_bundle(klass) }&.detail).to include("hook")
        expect(refusal_of { lml.import_bundle(tampered(name)) }&.detail).to include("hook name")
      end
    end

    it "refuses equal to and from hooks on export" do
      klass = stub_const("LmlSameHook", Class.new(Lutaml::Model::Serializable) do
        attribute :v, :string
        json { map "v", with: { to: :a, from: :a } }
      end)

      expect(refusal_of { lml.export_bundle(klass) }&.detail).to include("must differ")
    end

    it "refuses a user hook that uses the reserved stub prefix instead of dropping it" do
      klass = stub_const("LmlStubPrefix", Class.new(Lutaml::Model::Serializable) do
        attribute :v, :string
        json { map "v", with: { to: :__lml_absent_from_x, from: :y } }
      end)

      expect(refusal_of { lml.export_bundle(klass) }&.detail).to include("__lml_absent_")
    end

    it "still drops the stub it generates for a one-directional rule" do
      rules = bundle.models.fetch("#{hooks::Measure.name}@default")["mappings"]["json"]["rules"]

      expect(rules.filter_map { |r| r["custom"] }).to all(satisfy { |c| c.values.none? { |n| n.start_with?("__lml_absent_") } })
    end
  end

  describe "portable pattern facet" do
    let(:fx) { LmlDefaultBindingFixtures }

    def export_pattern(pattern)
      lml.export_bundle(fx::Subject, value_types: { "Code" => { class: fx::CodeType, base: "string", facets: { "pattern" => pattern } } },
                                     default_bindings: { "#{fx::Subject.name}@default" => { "lang" => "en", "flag" => false, "note" => nil, "tags" => [],
                                                                                            "ratio" => 0.25, "code" => "abc" } })
    end

    ['(a)\1b', "(?=a)a+b", '\h+', "(?i)abc", "a++b", "^abc$", '\p{Alpha}+', "(?>a+)b", '\Gabc', 'ab\Kc', 'abc\Z', 'abc\z', "[[:alpha:]]+"].each do |pattern|
      it "refuses the Ruby-only pattern #{pattern}" do
        error = refusal_of { export_pattern(pattern) }

        expect(error&.reason).to eq(:invalid_document)
        expect(error.detail).to include("pattern")
      end
    end

    ["[a-z]+", "[a-c]{3}", "(?:ab)+c?", "[a-c]{2,}", "[a-c]+?", "a|b|abc"].each do |pattern|
      it "accepts the portable pattern #{pattern}" do
        expect(export_pattern(pattern).value_types["Code"]["facets"]).to eq("pattern" => pattern)
      end
    end

    it "refuses a tampered bundle whose pattern does not compile or is not portable" do
      tree = JSON.parse(JSON.generate(export_pattern("[a-z]+").to_h))
      ["[", '(a)\1', "(?=a)a"].each do |bad|
        tree["value_types"]["Code"]["facets"]["pattern"] = bad
        error = refusal_of { Lutaml::Model::Lml::DocumentValidator.validate!(tree, kind: :bundle) }

        expect(error&.reason).to eq(:invalid_document)
      end
    end
  end

  describe "binding wrappers are judged per export" do
    let(:fx) { LmlDefaultBindingFixtures }
    let(:id) { "#{fx::Subject.name}@default" }
    let(:types) { { "Code" => { class: fx::CodeType, base: "string" } } }
    let(:constants) { { "lang" => "en", "flag" => false, "note" => nil, "tags" => [], "ratio" => 0.25, "code" => "abc" } }

    it "refuses a reused DefaultBindings that matches nothing in the second export" do
      wrapper = Lutaml::Model::Lml::Exporter::DefaultBindings.new(id => constants)
      lml.export_bundle(fx::Subject, value_types: types, default_bindings: wrapper)

      error = refusal_of { lml.export_bundle(hooks::Plain, default_bindings: wrapper) }

      expect(error&.detail).to include("matched no Proc or delegated default")
    end

    it "refuses a reused PolymorphicBindings that matches nothing in the second export" do
      holder_id = "#{hooks::DynamicHolder.name}@default"
      wrapper = Lutaml::Model::Lml::Exporter::PolymorphicBindings.new(
        holder_id => { "json" => { "shape" => { "circle" => hooks::Circle } },
                       "yaml" => { "shape" => { "circle" => hooks::Circle } },
                       "toml" => { "shape" => { "circle" => hooks::Circle } } },
      )
      lml.export_bundle(hooks::DynamicHolder, polymorphic_bindings: wrapper)

      error = refusal_of { lml.export_bundle(hooks::Plain, polymorphic_bindings: wrapper) }

      expect(error&.detail).to include("matched no dynamic class map")
    end
  end

  describe "polymorphic binding tables" do
    let(:holder_id) { "#{hooks::DynamicHolder.name}@default" }

    def export_cases(cases)
      lml.export_bundle(hooks::DynamicHolder,
                        polymorphic_bindings: { holder_id => %w[json yaml toml].to_h { |f| [f, { "shape" => cases }] } })
    end

    it "refuses a symbol and a string key that spell one wire value" do
      error = refusal_of { export_cases(circle: hooks::Circle, "circle" => hooks::Square) }

      expect(error&.detail).to include("declared twice")
    end

    it "refuses a target that is not the declared base or a subclass" do
      error = refusal_of { export_cases("x" => hooks::Measure) }

      expect(error&.detail).to include("not #{hooks::Shape}")
    end

    it "leaves a class name that does not resolve to the graph's dangling_reference" do
      expect(refusal_of { export_cases("x" => "No::Such::Klass") }&.reason).to eq(:dangling_reference)
    end

    it "keeps accepting subclasses of the declared base" do
      bundle = export_cases("circle" => hooks::Circle, "square" => hooks::Square)

      expect(bundle.models.fetch(holder_id)["mappings"]["json"]["rules"].first["discriminator"]["cases"].keys).to eq(%w[circle square])
    end
  end

  describe "AdapterResolver.set_adapter_type" do
    # These examples clear the global XML slot the suite pins in spec_helper;
    # snapshot the resolver's tables and put them back exactly.
    around do |example|
      resolver = Lutaml::Model::AdapterResolver
      tables = %i[configured_types resolved detected_types detected_formats].to_h { |t| [t, resolver.send(t).dup] }
      example.run
    ensure
      tables.each { |t, saved| resolver.send(t).replace(saved) }
    end

    it "still refuses an unknown format when the type is nil" do
      expect { Lutaml::Model::AdapterResolver.set_adapter_type(:nope, nil) }.to raise_error(ArgumentError, /Unknown format/)
    end

    it "still restores detection for a known format" do
      expect(Lutaml::Model::AdapterResolver.set_adapter_type(:xml, nil)).to be_nil
    end
  end
end
