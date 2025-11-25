require "spec_helper"
require "lutaml/model/xml/namespace_collector"

RSpec.describe Lutaml::Model::Xml::NamespaceCollector do
  # Define reusable namespace classes
  let(:vcard_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "urn:ietf:params:xml:ns:vcard-4.0"
      prefix_default "vcard"
    end
  end

  let(:dc_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://purl.org/dc/elements/1.1/"
      prefix_default "dc"
    end
  end

  let(:dcterms_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://purl.org/dc/terms/"
      prefix_default "dcterms"
    end
  end

  let(:register) { :default }
  let(:collector) { described_class.new(register) }

  describe "#initialize" do
    it "initializes with default register" do
      collector = described_class.new
      expect(collector).to be_a(described_class)
    end

    it "initializes with custom register" do
      collector = described_class.new(:custom)
      expect(collector).to be_a(described_class)
    end
  end

  describe "#collect" do
    context "with simple model" do
      let(:model_class) do
        vcard_ns = vcard_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :version, :string

          xml do
            namespace vcard_ns
            root "vCard"
            map_element "version", to: :version
          end
        end
      end

      let(:mapping) { model_class.mappings_for(:xml) }

      it "collects root element namespace" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)

        expect(needs[:namespaces].keys).to include(vcard_namespace.to_key)
        expect(needs[:namespaces][vcard_namespace.to_key][:used_in]).to include(:elements)
      end

      it "returns empty namespaces hash when tracking attributes only" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)

        # Should not include :attributes in used_in for this model
        vcard_entry = needs[:namespaces][vcard_namespace.to_key]
        expect(vcard_entry[:used_in]).not_to include(:attributes)
      end

      it "returns empty children when no nested models" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)

        expect(needs[:children]).to be_empty
      end
    end

    context "with XML attributes" do
      let(:model_class) do
        vcard_ns = vcard_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :version, :string
          attribute :lang, :string

          xml do
            namespace vcard_ns
            root "vCard"
            map_element "version", to: :version
            map_attribute "lang", to: :lang, namespace: vcard_ns
          end
        end
      end

      let(:mapping) { model_class.mappings_for(:xml) }

      it "collects XML attribute namespaces" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)

        expect(needs[:namespaces].keys).to include(vcard_namespace.to_key)
        expect(needs[:namespaces][vcard_namespace.to_key][:used_in]).to include(:attributes)
      end
    end

    context "with Type namespaces" do
      let(:custom_type) do
        vcard_ns = vcard_namespace
        Class.new(Lutaml::Model::Type::Value) do
          define_singleton_method(:xml_namespace) { vcard_ns }
        end
      end

      let(:model_class) do
        custom_t = custom_type
        Class.new(Lutaml::Model::Serializable) do
          attribute :custom, custom_t

          xml do
            root "Model"
            map_element "custom", to: :custom
          end
        end
      end

      let(:mapping) { model_class.mappings_for(:xml) }

      it "collects Type namespaces for elements" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)

        expect(needs[:namespaces].keys).to include(vcard_namespace.to_key)
        expect(needs[:type_namespaces][:custom]).to eq(vcard_namespace)
      end

      it "collects both model and Type namespaces" do
        dc_ns = dc_namespace
        custom_t = custom_type
        model = Class.new(Lutaml::Model::Serializable) do
          attribute :custom, custom_t

          xml do
            namespace dc_ns
            root "Model"
            map_element "custom", to: :custom
          end
        end

        mapping = model.mappings_for(:xml)
        needs = collector.collect(nil, mapping, mapper_class: model)

        expect(needs[:namespaces].keys).to include(dc_namespace.to_key)
        expect(needs[:namespaces].keys).to include(vcard_namespace.to_key)
      end
    end

    context "with nested models" do
      let(:name_model) do
        vcard_ns = vcard_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :given, :string
          attribute :family, :string

          xml do
            namespace vcard_ns
            root "n"
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
            root "vCard"
            map_element "version", to: :version
            map_element "n", to: :n
          end
        end
      end

      let(:mapping) { contact_model.mappings_for(:xml) }

      it "recursively collects child model needs" do
        needs = collector.collect(nil, mapping, mapper_class: contact_model)

        expect(needs[:children]).to have_key(:n)
        expect(needs[:children][:n]).to be_a(Hash)
      end

      it "collects child element namespaces" do
        needs = collector.collect(nil, mapping, mapper_class: contact_model)
        child_needs = needs[:children][:n]

        expect(child_needs[:namespaces].keys).to include(vcard_namespace.to_key)
      end

      it "bubbles up child namespace requirements" do
        needs = collector.collect(nil, mapping, mapper_class: contact_model)

        expect(needs[:namespaces].keys).to include(vcard_namespace.to_key)
      end
    end

    context "with namespace_scope" do
      let(:model_class) do
        dc_ns = dc_namespace
        vcard_ns = vcard_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :version, :string

          xml do
            namespace vcard_ns
            root "vCard"
            namespace_scope [{ namespace: dc_ns, declare: :auto }]
            map_element "version", to: :version
          end
        end
      end

      let(:mapping) { model_class.mappings_for(:xml) }

      it "preserves namespace_scope configuration" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)

        expect(needs[:namespace_scope_configs]).not_to be_nil
        expect(needs[:namespace_scope_configs]).to be_a(Array)
      end
    end

    context "with type-only models (no_element)" do
      let(:type_only_model) do
        vcard_ns = vcard_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string

          xml do
            namespace vcard_ns
            no_root
            map_element "value", to: :value
          end
        end
      end

      let(:mapping) { type_only_model.mappings_for(:xml) }

      it "skips root namespace but collects child element namespaces" do
        needs = collector.collect(nil, mapping, mapper_class: type_only_model)

        # Type-only models don't have root elements, but child elements
        # with native types inherit parent namespace
        expect(needs[:namespaces].keys).to include(vcard_namespace.to_key)
        expect(needs[:type_namespaces][:value]).to eq(vcard_namespace)
      end

      it "collects inherited namespaces for native type children" do
        needs = collector.collect(nil, mapping, mapper_class: type_only_model)

        # Native type children inherit parent namespace
        expect(needs[:namespaces]).not_to be_empty
        expect(needs[:namespaces][vcard_namespace.to_key][:used_in]).to include(:elements)
      end
    end

    context "with explicit element namespace" do
      let(:model_class) do
        vcard_ns = vcard_namespace
        dc_ns = dc_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :title, :string

          xml do
            namespace vcard_ns
            root "vCard"
            map_element "title", to: :title, namespace: dc_ns
          end
        end
      end

      let(:mapping) { model_class.mappings_for(:xml) }

      it "collects explicit element namespace" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)

        expect(needs[:namespaces].keys).to include(dc_namespace.to_key)
        expect(needs[:namespaces].keys).to include(vcard_namespace.to_key)
      end
    end
  end

  describe "#collect_collection" do
    let(:collection_model) do
      Class.new(Lutaml::Model::Collection) do
        instances :items, String
      end
    end

    let(:collection) { collection_model.new }
    let(:mapping) { collection_model.mappings_for(:xml) }

    it "collects needs from collection" do
      needs = collector.collect_collection(collection, mapping)

      expect(needs).to have_key(:namespaces)
      expect(needs).to have_key(:children)
    end

    it "collects needs from instance type" do
      item_model = Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        xml do
          root "item"
          map_element "value", to: :value
        end
      end

      coll_model = Class.new(Lutaml::Model::Collection) do
        i_model = item_model
        instances :items, i_model

        xml do
          root "items"
          map_element "item", to: :items
        end
      end

      coll = coll_model.new
      mapping = coll_model.mappings_for(:xml)
      needs = collector.collect_collection(coll, mapping)

      expect(needs).to have_key(:namespaces)
      expect(needs).to have_key(:children)
    end
  end

  describe "#needs_prefix?" do
    context "when attributes use root namespace" do
      let(:model_class) do
        vcard_ns = vcard_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :version, :string
          attribute :lang, :string

          xml do
            namespace vcard_ns
            root "vCard"
            map_element "version", to: :version
            map_attribute "lang", to: :lang, namespace: vcard_ns
          end
        end
      end

      let(:mapping) { model_class.mappings_for(:xml) }

      it "returns true" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)
        result = collector.needs_prefix?(needs, mapping)

        expect(result).to be true
      end
    end

    context "when no attributes use root namespace" do
      let(:model_class) do
        vcard_ns = vcard_namespace
        Class.new(Lutaml::Model::Serializable) do
          attribute :version, :string

          xml do
            namespace vcard_ns
            root "vCard"
            map_element "version", to: :version
          end
        end
      end

      let(:mapping) { model_class.mappings_for(:xml) }

      it "returns false" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)
        result = collector.needs_prefix?(needs, mapping)

        expect(result).to be false
      end
    end

    context "when no root namespace" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :version, :string

          xml do
            root "vCard"
            map_element "version", to: :version
          end
        end
      end

      let(:mapping) { model_class.mappings_for(:xml) }

      it "returns false" do
        needs = collector.collect(nil, mapping, mapper_class: model_class)
        result = collector.needs_prefix?(needs, mapping)

        expect(result).to be false
      end
    end
  end

  describe "#all_namespaces" do
    let(:name_model) do
      dc_ns = dc_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string

        xml do
          namespace dc_ns
          root "name"
          map_element "title", to: :title
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
          root "contact"
          map_element "title", to: :title
          map_element "n", to: :n
        end
      end
    end

    let(:mapping) { contact_model.mappings_for(:xml) }

    it "returns all unique namespaces from tree" do
      needs = collector.collect(nil, mapping, mapper_class: contact_model)
      all_ns = collector.all_namespaces(needs)

      expect(all_ns).to include(dc_namespace)
      expect(all_ns).to include(vcard_namespace)
    end

    it "returns a Set" do
      needs = collector.collect(nil, mapping, mapper_class: contact_model)
      all_ns = collector.all_namespaces(needs)

      expect(all_ns).to be_a(Set)
    end
  end

  describe "#namespace_used?" do
    let(:model_class) do
      vcard_ns = vcard_namespace
      Class.new(Lutaml::Model::Serializable) do
        attribute :version, :string

        xml do
          namespace vcard_ns
          root "vCard"
          map_element "version", to: :version
        end
      end
    end

    let(:mapping) { model_class.mappings_for(:xml) }

    it "returns true when namespace is used in elements" do
      needs = collector.collect(nil, mapping, mapper_class: model_class)
      result = collector.namespace_used?(needs, vcard_namespace)

      expect(result).to be true
    end

    it "returns false when namespace is not used" do
      needs = collector.collect(nil, mapping, mapper_class: model_class)
      unused_ns = Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/not-used"
        prefix_default "unused"
      end
      result = collector.namespace_used?(needs, unused_ns)

      expect(result).to be false
    end

    it "recursively checks child needs" do
      dc_ns = dc_namespace
      vcard_ns = vcard_namespace
      name_model = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string

        xml do
          namespace dc_ns
          root "name"
          map_element "title", to: :title
        end
      end

      parent_model = Class.new(Lutaml::Model::Serializable) do
        n_model = name_model
        attribute :n, n_model

        xml do
          namespace vcard_ns
          root "parent"
          map_element "n", to: :n
        end
      end

      parent_mapping = parent_model.mappings_for(:xml)
      needs = collector.collect(nil, parent_mapping, mapper_class: parent_model)
      result = collector.namespace_used?(needs, dc_namespace)

      expect(result).to be true
    end
  end

  describe "#empty_needs (private)" do
    it "returns empty needs structure" do
      result = collector.send(:empty_needs)

      expect(result).to eq({
                             namespaces: {},
                             children: {},
                             namespace_scope_configs: nil,
                             type_namespaces: {},
                           })
    end
  end
end
