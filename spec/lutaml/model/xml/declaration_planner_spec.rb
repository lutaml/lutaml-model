require "spec_helper"
require "lutaml/model/xml/namespace_collector"
require "lutaml/model/xml/declaration_planner"

RSpec.describe Lutaml::Model::Xml::DeclarationPlanner do
  # Define reusable namespace classes
  let(:vcard_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "urn:ietf:params:xml:ns:vcard-4.0"
      prefix_default "vcard"
    end
  end

  let(:dc_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://purl.org/dc/elements/1.1/"
      prefix_default "dc"
    end
  end

  let(:dcterms_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://purl.org/dc/terms/"
      prefix_default "dcterms"
    end
  end

  let(:register) { :default }
  let(:planner) { described_class.new(register) }
  let(:collector) { Lutaml::Model::Xml::NamespaceCollector.new(register) }

  describe "#initialize" do
    it "initializes with default register" do
      planner = described_class.new
      expect(planner).to be_a(described_class)
    end

    it "initializes with custom register" do
      planner = described_class.new(:custom)
      expect(planner).to be_a(described_class)
    end
  end

  describe "#plan" do
    context "with root element" do
      context "with default namespace" do
        let(:model_class) do
          vcard_ns = vcard_namespace
          Class.new(Lutaml::Model::Serializable) do
            attribute :version, :string

            xml do
              namespace vcard_ns
              element "vCard"
              map_element "version", to: :version
            end
          end
        end

        let(:mapping) { model_class.mappings_for(:xml) }
        let(:needs) { collector.collect(nil, mapping, mapper_class: model_class) }

        it "creates xmlns declaration for default namespace" do
          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: model_class })

          # W3C-compliant: Use OOP API to access NamespaceDeclaration
          expect(plan.namespaces).to have_key(vcard_namespace.to_key)
          ns_decl = plan.namespace(vcard_namespace.to_key)
          expect(ns_decl.xmlns_declaration).to eq("xmlns=\"urn:ietf:params:xml:ns:vcard-4.0\"")
        end

        it "sets format to :default" do
          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: model_class })

          # W3C-compliant: Use OOP API to access format
          ns_decl = plan.namespace(vcard_namespace.to_key)
          expect(ns_decl.format).to eq(:default)
        end

        it "marks namespace as declared_at :here" do
          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: model_class })

          # W3C-compliant: Use OOP API to access declared_at
          ns_decl = plan.namespace(vcard_namespace.to_key)
          expect(ns_decl.declared_at).to eq(:here)
        end
      end

      context "with prefixed namespace" do
        # Helper method to create everything fresh for each test
        # This prevents any sharing of namespace classes, attributes, or mappings
        def create_fresh_model_with_prefixed_namespace
          # Create fresh namespace
          vcard_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
            uri "urn:ietf:params:xml:ns:vcard-4.0"
            prefix_default "vcard"
          end

          # Create fresh type with namespace
          lang_type = Class.new(Lutaml::Model::Type::String) do
            xml_namespace vcard_ns
          end

          # Create fresh model_class
          model_class = Class.new(Lutaml::Model::Serializable) do
            attribute :version, :string
            attribute :lang, lang_type

            xml do
              namespace vcard_ns
              element "vCard"
              map_element "version", to: :version
              map_attribute "lang", to: :lang
            end
          end

          [vcard_ns, model_class]
        end

        it "creates xmlns:prefix declaration" do
          vcard_ns, model_class = create_fresh_model_with_prefixed_namespace
          mapping = model_class.mappings_for(:xml)
          needs = collector.collect(nil, mapping, mapper_class: model_class)

          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: model_class })

          # W3C-compliant: Use OOP API to access NamespaceDeclaration
          ns_decl = plan.namespace(vcard_ns.to_key)
          expect(ns_decl.xmlns_declaration).to eq("xmlns:vcard=\"urn:ietf:params:xml:ns:vcard-4.0\"")
        end

        it "sets format to :prefix" do
          vcard_ns, model_class = create_fresh_model_with_prefixed_namespace
          mapping = model_class.mappings_for(:xml)
          needs = collector.collect(nil, mapping, mapper_class: model_class)

          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: model_class })

          # W3C-compliant: Use OOP API to access format
          ns_decl = plan.namespace(vcard_ns.to_key)
          expect(ns_decl.format).to eq(:prefix)
        end

        it "marks namespace as declared_at :here" do
          vcard_ns, model_class = create_fresh_model_with_prefixed_namespace
          mapping = model_class.mappings_for(:xml)
          needs = collector.collect(nil, mapping, mapper_class: model_class)

          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: model_class })

          # W3C-compliant: Use OOP API to access declared_at
          ns_decl = plan.namespace(vcard_ns.to_key)
          expect(ns_decl.declared_at).to eq(:here)
        end
      end

      context "with explicit use_prefix option" do
        # Helper method to create everything fresh for each test
        def create_fresh_simple_model
          # Create fresh namespace
          vcard_ns = Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
            uri "urn:ietf:params:xml:ns:vcard-4.0"
            prefix_default "vcard"
          end

          # Create fresh model_class
          model_class = Class.new(Lutaml::Model::Serializable) do
            attribute :version, :string

            xml do
              namespace vcard_ns
              element "vCard"
              map_element "version", to: :version
            end
          end

          [vcard_ns, model_class]
        end

        it "forces prefix format when use_prefix: true" do
          vcard_ns, model_class = create_fresh_simple_model
          mapping = model_class.mappings_for(:xml)
          needs = collector.collect(nil, mapping, mapper_class: model_class)
          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: model_class, use_prefix: true })

          # W3C-compliant: Use OOP API
          ns_decl = plan.namespace(vcard_ns.to_key)
          expect(ns_decl.format).to eq(:prefix)
          expect(ns_decl.xmlns_declaration).to eq("xmlns:vcard=\"urn:ietf:params:xml:ns:vcard-4.0\"")
        end

        it "forces default format when use_prefix: false" do
          vcard_ns, model_class = create_fresh_simple_model
          mapping = model_class.mappings_for(:xml)
          needs = collector.collect(nil, mapping, mapper_class: model_class)
          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: model_class, use_prefix: false })

          # W3C-compliant: Use OOP API
          ns_decl = plan.namespace(vcard_ns.to_key)
          expect(ns_decl.format).to eq(:default)
          expect(ns_decl.xmlns_declaration).to eq("xmlns=\"urn:ietf:params:xml:ns:vcard-4.0\"")
        end

        it "uses custom prefix string when provided" do
          vcard_ns, model_class = create_fresh_simple_model
          mapping = model_class.mappings_for(:xml)
          needs = collector.collect(nil, mapping, mapper_class: model_class)
          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: model_class, use_prefix: "custom" })

          # W3C-compliant: Use OOP API
          ns_decl = plan.namespace(vcard_ns.to_key)
          expect(ns_decl.format).to eq(:prefix)
          expect(ns_decl.xmlns_declaration).to eq("xmlns:custom=\"urn:ietf:params:xml:ns:vcard-4.0\"")
        end
      end
    end

    context "with nested elements" do
      context "when child namespace matches parent default (KEY TEST)" do
        let(:name_model) do
          vcard_ns = vcard_namespace
          Class.new(Lutaml::Model::Serializable) do
            attribute :given, :string
            attribute :family, :string

            xml do
              namespace vcard_ns
              element "n"
              map_element "given", to: :given
              map_element "family", to: :family
            end
          end
        end

        let(:contact_model) do
          vcard_ns = vcard_namespace
          n_model = name_model
          Class.new(Lutaml::Model::Serializable) do
            attribute :version, :string
            attribute :n, n_model

            xml do
              namespace vcard_ns
              element "vCard"
              map_element "version", to: :version
              map_element "n", to: :n
            end
          end
        end

        let(:mapping) { contact_model.mappings_for(:xml) }
        let(:child_mapping) { name_model.mappings_for(:xml) }
        let(:needs) { collector.collect(nil, mapping, mapper_class: contact_model) }

        it "parent declares default namespace" do
          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: contact_model })

          # W3C-compliant: Use OOP API
          expect(plan.namespaces).to have_key(vcard_namespace.to_key)
          ns_decl = plan.namespace(vcard_namespace.to_key)
          expect(ns_decl.xmlns_declaration).to eq("xmlns=\"urn:ietf:params:xml:ns:vcard-4.0\"")
          expect(ns_decl.format).to eq(:default)
        end

        it "child inherits parent's namespace declaration" do
          plan = planner.plan(nil, mapping, needs,
                              options: { mapper_class: contact_model })
          # W3C-compliant: Use OOP API to get child plan
          child_plan = plan.child_plan(:n)

          # Child should have namespace in its plan (inherited from parent)
          expect(child_plan.namespaces).to have_key(vcard_namespace.to_key)

          # Child's namespace should be inherited, not redeclared
          # (We don't set declared_at on inherited namespaces, they remain from parent)
          ns_decl = child_plan.namespace(vcard_namespace.to_key)
          expect(ns_decl.format).to eq(:default)
        end
      end

      context "when child namespace differs from parent" do
        let(:metadata_model) do
          dc_ns = dc_namespace
          Class.new(Lutaml::Model::Serializable) do
            attribute :title, :string
            attribute :creator, :string

            xml do
              namespace dc_ns
              element "metadata"
              map_element "title", to: :title
              map_element "creator", to: :creator
            end
          end
        end

        let(:document_model) do
          vcard_ns = vcard_namespace
          meta_model = metadata_model
          Class.new(Lutaml::Model::Serializable) do
            attribute :version, :string
            attribute :metadata, meta_model

            xml do
              namespace vcard_ns
              element "document"
              map_element "version", to: :version
              map_element "metadata", to: :metadata
            end
          end
        end

        let(:mapping) { document_model.mappings_for(:xml) }
        # Create actual instance so collector can detect child namespaces
        let(:metadata_instance) { metadata_model.new(title: "Test", creator: "Author") }
        let(:document_instance) { document_model.new(version: "1.0", metadata: metadata_instance) }
        let(:needs) { collector.collect(document_instance, mapping, mapper_class: document_model) }

        it "parent declares both namespaces at root" do
          plan = planner.plan(document_instance, mapping, needs,
                              options: { mapper_class: document_model })

          # Parent declares own namespace
          # W3C-compliant: Use OOP API
          expect(plan.namespaces).to have_key(vcard_namespace.to_key)
          vcard_decl = plan.namespace(vcard_namespace.to_key)
          expect(vcard_decl.format).to eq(:default)

          # Parent also declares child's namespace (declared once at root principle)
          expect(plan.namespaces).to have_key(dc_namespace.to_key)
          dc_decl = plan.namespace(dc_namespace.to_key)
          expect(dc_decl.format).to eq(:prefix)
          expect(dc_decl.xmlns_declaration).to eq("xmlns:dc=\"http://purl.org/dc/elements/1.1/\"")
        end

        it "child inherits parent's namespace declarations" do
          plan = planner.plan(document_instance, mapping, needs,
                              options: { mapper_class: document_model })
          # W3C-compliant: Use OOP API to get child plan
          child_plan = plan.child_plan(:metadata)

          # Child should have both namespaces (inherited from parent)
          expect(child_plan.namespaces).to have_key(vcard_namespace.to_key)
          expect(child_plan.namespaces).to have_key(dc_namespace.to_key)
        end
      end
    end

    context "with namespace_scope" do
      let(:contact_model) do
        vcard_ns = vcard_namespace
        dc_ns = dc_namespace
        dcterms_ns = dcterms_namespace

        Class.new(Lutaml::Model::Serializable) do
          attribute :version, :string

          xml do
            namespace vcard_ns
            element "vCard"
            namespace_scope [
              { namespace: dc_ns, declare: :always },
              { namespace: dcterms_ns, declare: :always }
            ]
            map_element "version", to: :version
          end
        end
      end

      let(:mapping) { contact_model.mappings_for(:xml) }
      let(:needs) { collector.collect(nil, mapping, mapper_class: contact_model) }

      it "declares namespace_scope namespaces as prefixed (with :always mode)" do
        plan = planner.plan(nil, mapping, needs,
                            options: { mapper_class: contact_model })

        # W3C-compliant: Use OOP API
        expect(plan.namespaces).to have_key(dc_namespace.to_key)
        dc_decl = plan.namespace(dc_namespace.to_key)
        expect(dc_decl.xmlns_declaration).to eq("xmlns:dc=\"http://purl.org/dc/elements/1.1/\"")

        expect(plan.namespaces).to have_key(dcterms_namespace.to_key)
        dcterms_decl = plan.namespace(dcterms_namespace.to_key)
        expect(dcterms_decl.xmlns_declaration).to eq("xmlns:dcterms=\"http://purl.org/dc/terms/\"")
      end

      it "tracks namespace_scope namespaces with :prefix format (with :always mode)" do
        plan = planner.plan(nil, mapping, needs,
                            options: { mapper_class: contact_model })

        # W3C-compliant: Use OOP API
        dc_decl = plan.namespace(dc_namespace.to_key)
        expect(dc_decl.format).to eq(:prefix)

        dcterms_decl = plan.namespace(dcterms_namespace.to_key)
        expect(dcterms_decl.format).to eq(:prefix)
      end
    end

    context "with Type namespaces" do
      let(:vcard_version_type) do
        vcard_ns = vcard_namespace
        t = Class.new(Lutaml::Model::Type::String)
        t.xml_namespace(vcard_ns)
        t
      end

      let(:model_class) do
        vcard_ver_type = vcard_version_type
        vcard_ns = vcard_namespace
        Class.new(Lutaml::Model::Serializable) do
          Lutaml::Model::Type.register(:vcard_version, vcard_ver_type)
          attribute :version, :vcard_version

          xml do
            namespace vcard_ns
            element "vCard"
            map_element "version", to: :version
          end
        end
      end

      let(:mapping) { model_class.mappings_for(:xml) }
      let(:needs) { collector.collect(nil, mapping, mapper_class: model_class) }

      it "handles Type namespace matching root default namespace" do
        plan = planner.plan(nil, mapping, needs,
                            options: { mapper_class: model_class })

        # Type namespace matches root, should use default format
        # W3C-compliant: Use OOP API
        ns_decl = plan.namespace(vcard_namespace.to_key)
        expect(ns_decl.format).to eq(:default)
        expect(ns_decl.xmlns_declaration).to eq("xmlns=\"urn:ietf:params:xml:ns:vcard-4.0\"")
      end
    end

    context "with type-only models (no_element)" do
      let(:type_only_model) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string

          xml do
            # No root = type-only model
            map_content to: :value
          end
        end
      end

      let(:mapping) { type_only_model.mappings_for(:xml) }
      let(:needs) { collector.collect(nil, mapping, mapper_class: type_only_model) }

      it "returns plan with no xmlns declarations" do
        plan = planner.plan(nil, mapping, needs,
                            options: { mapper_class: type_only_model })

        # W3C-compliant: Use OOP API
        expect(plan.namespaces).to be_empty
      end
    end
  end

  describe "#plan_collection" do
    let(:item_model) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "item"
          map_element "name", to: :name
        end
      end
    end

    let(:collection_class) do
      item_m = item_model
      Class.new(Lutaml::Model::Collection) do
        instances :items, item_m

        xml do
          element "items"
          map_element "item", to: :items
        end
      end
    end

    let(:collection) { collection_class.new }
    let(:mapping) { collection_class.mappings_for(:xml) }
    let(:needs) { collector.collect_collection(collection, mapping) }

    it "creates plan for collection" do
      plan = planner.plan_collection(collection, mapping, needs)

      # W3C-compliant: DeclarationPlan is now an object, not a hash
      expect(plan).to be_a(Lutaml::Model::Xml::DeclarationPlan)
      expect(plan.namespaces).to be_a(Hash)
      expect(plan.children_plans).to be_a(Hash)
    end
  end

end
