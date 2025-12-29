require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/oga_adapter"
require "lutaml/model/xml/ox_adapter"

RSpec.describe "Passing metadata (custom args) in from_* and to_* methods" do
  context "with JSON format" do
    let(:json_data) do
      {
        name: "Test Name",
        size: 10
      }.to_json
    end

    context "when custom method accepts 2 arguments (model, value)" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :size, :integer

          json do
            map "name", to: :name, with: { from: :name_from_json, to: :name_to_json }
            map "size", to: :size
          end

          def name_from_json(model, value)
            model.metadata_received = nil
            model.name = value
          end

          def name_to_json(model, hash)
            model.to_metadata_received = nil
            hash["name"] = model.name
          end

          attr_accessor :metadata_received, :to_metadata_received
        end
      end

      it "does not pass metadata when method accepts 2 arguments for from_json" do
        instance = model_class.from_json(json_data, metadata: { key: "value" })
        expect(instance.metadata_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "does not pass metadata when method accepts 2 arguments for to_json" do
        instance = model_class.new(name: "Test Name", size: 10)
        json = instance.to_json(metadata: { key: "value" })
        parsed = JSON.parse(json)
        expect(instance.to_metadata_received).to be_nil
        expect(parsed["name"]).to eq("Test Name")
        expect(parsed["size"]).to eq(10)
      end
    end

    context "when custom method accepts 3 arguments (model, value, metadata)" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :size, :integer

          json do
            map "name", to: :name, with: { from: :name_from_json, to: :name_to_json }
            map "size", to: :size
          end

          def name_from_json(model, value, metadata)
            model.metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            model.name = "#{prefix}#{value}"
          end

          def name_to_json(model, hash, metadata)
            model.to_metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            hash["name"] = "#{prefix}#{model.name}"
          end

          attr_accessor :metadata_received, :to_metadata_received
        end
      end

      it "passes metadata when method accepts 3 arguments for from_json" do
        metadata = { prefix: "[", suffix: "]" }
        instance = model_class.from_json(json_data, metadata: metadata)
        expect(instance.metadata_received).to eq(metadata)
        expect(instance.name).to eq("[Test Name")
      end

      it "does not pass metadata to from_json when not provided" do
        instance = model_class.from_json(json_data)
        expect(instance.metadata_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes metadata when method accepts 3 arguments for to_json" do
        instance = model_class.new(name: "Test Name", size: 10)
        metadata = { prefix: "TO: " }
        json = instance.to_json(metadata: metadata)
        expect(instance.to_metadata_received).to eq(metadata)
        parsed = JSON.parse(json)
        expect(parsed["name"]).to eq("TO: Test Name")
        expect(parsed["size"]).to eq(10)
      end

      it "does not pass metadata to to_json when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        json = instance.to_json
        expect(instance.to_metadata_received).to be_nil
        parsed = JSON.parse(json)
        expect(parsed["name"]).to eq("Test Name")
        expect(parsed["size"]).to eq(10)
      end
    end
  end

  context "with YAML format" do
    let(:yaml_data) do
      {
        name: "Test Name",
        size: 10
      }.to_yaml
    end

    context "when custom method accepts 3 arguments" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :size, :integer

          yaml do
            map "name", to: :name, with: { from: :name_from_yaml, to: :name_to_yaml }
            map "size", to: :size
          end

          def name_from_yaml(model, value, metadata)
            model.metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            model.name = "#{prefix}#{value}"
          end

          def name_to_yaml(model, hash, metadata)
            model.to_metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            hash["name"] = "#{prefix}#{model.name}"
          end

          attr_accessor :metadata_received, :to_metadata_received
        end
      end

      it "passes metadata to YAML custom method for from_yaml" do
        metadata = { prefix: "YAML: " }
        instance = model_class.from_yaml(yaml_data, metadata: metadata)
        expect(instance.metadata_received).to eq(metadata)
        expect(instance.name).to eq("YAML: Test Name")
      end

      it "does not pass metadata when not provided to from_yaml" do
        instance = model_class.from_yaml(yaml_data)
        expect(instance.metadata_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes metadata to YAML custom method for to_yaml" do
        instance = model_class.new(name: "Test Name", size: 10)
        metadata = { prefix: "YAML: " }
        yaml = instance.to_yaml(metadata: metadata)
        expect(instance.to_metadata_received).to eq(metadata)
        expect(yaml).to include("name: 'YAML: Test Name'")
        expect(yaml).to include("size: 10")
      end

      it "does not pass metadata to to_yaml when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        yaml = instance.to_yaml
        expect(instance.to_metadata_received).to be_nil
        expect(yaml).to include("name: Test Name")
        expect(yaml).to include("size: 10")
      end
    end
  end

  context "with TOML format" do
    let(:toml_data) do
      <<~TOML
        name = "Test Name"
        size = 10
      TOML
    end

    context "when custom method accepts 3 arguments" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :size, :integer

          toml do
            map "name", to: :name, with: { from: :name_from_toml, to: :name_to_toml }
            map "size", to: :size
          end

          def name_from_toml(model, value, metadata)
            model.metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            model.name = "#{prefix}#{value}"
          end

          def name_to_toml(model, hash, metadata)
            model.to_metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            hash["name"] = "#{prefix}#{model.name}"
          end

          attr_accessor :metadata_received, :to_metadata_received
        end
      end

      it "passes metadata to TOML custom method for from_toml" do
        metadata = { prefix: "TOML: " }
        instance = model_class.from_toml(toml_data, metadata: metadata)
        expect(instance.metadata_received).to eq(metadata)
        expect(instance.name).to eq("TOML: Test Name")
      end

      it "does not pass metadata to from_toml when not provided" do
        instance = model_class.from_toml(toml_data)
        expect(instance.metadata_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes metadata to TOML custom method for to_toml" do
        instance = model_class.new(name: "Test Name", size: 10)
        metadata = { prefix: "TOML: " }
        toml = instance.to_toml(metadata: metadata)
        expect(instance.to_metadata_received).to eq(metadata)
        expect(toml).to include('name = "TOML: Test Name"')
        expect(toml).to include('size = 10')
      end

      it "does not pass metadata to to_toml when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        toml = instance.to_toml
        expect(instance.to_metadata_received).to be_nil
        expect(toml).to include('name = "Test Name"')
        expect(toml).to include('size = 10')
      end
    end
  end

  context "with hash format" do
    let(:hash_data) do
      {
        "name" => "Test Name",
        "size" => 10
      }
    end

    context "when custom method accepts 3 arguments" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :size, :integer

          hsh do
            map "name", to: :name, with: { from: :name_from_hash, to: :name_to_hash }
            map "size", to: :size
          end

          def name_from_hash(model, value, metadata)
            model.metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            model.name = "#{prefix}#{value}"
          end

          def name_to_hash(model, hash, metadata)
            model.to_metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            hash["name"] = "#{prefix}#{model.name}"
          end

          attr_accessor :metadata_received, :to_metadata_received
        end
      end

      it "passes metadata to hash custom method for from_hash" do
        metadata = { prefix: "Hash: " }
        instance = model_class.from_hash(hash_data, metadata: metadata)
        expect(instance.metadata_received).to eq(metadata)
        expect(instance.name).to eq("Hash: Test Name")
      end

      it "does not pass metadata to from_hash when not provided" do
        instance = model_class.from_hash(hash_data)
        expect(instance.metadata_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes metadata to hash custom method for to_hash" do
        instance = model_class.new(name: "Test Name", size: 10)
        metadata = { prefix: "Hash: " }
        hash_out = instance.to_hash(metadata: metadata)
        expect(instance.to_metadata_received).to eq(metadata)
        expect(hash_out["name"]).to eq("Hash: Test Name")
        expect(hash_out["size"]).to eq(10)
      end

      it "does not pass metadata to to_hash when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        hash_out = instance.to_hash
        expect(instance.to_metadata_received).to be_nil
        expect(hash_out["name"]).to eq("Test Name")
        expect(hash_out["size"]).to eq(10)
      end
    end
  end

  context "with multiple attributes using metadata" do
    let(:json_data) do
      {
        name: "Test Name",
        description: "Test Description"
      }.to_json
    end

    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :description, :string

        json do
          map "name", to: :name, with: { from: :name_from_json, to: :name_to_json }
          map "description", to: :description, with: { from: :description_from_json, to: :description_to_json }
        end

        def name_from_json(model, value, metadata)
          model.name_metadata = metadata
          suffix = metadata&.dig(:suffix) || ""
          model.name = "#{value}#{suffix}"
        end

        def description_from_json(model, value, metadata)
          model.description_metadata = metadata
          suffix = metadata&.dig(:suffix) || ""
          model.description = "#{value}#{suffix}"
        end

        def name_to_json(model, hash, metadata)
          model.name_to_metadata = metadata
          suffix = metadata&.dig(:suffix) || ""
          hash["name"] = "#{model.name}#{suffix}"
        end

        def description_to_json(model, hash, metadata)
          model.description_to_metadata = metadata
          suffix = metadata&.dig(:suffix) || ""
          hash["description"] = "#{model.description}#{suffix}"
        end

        attr_accessor :name_metadata, :description_metadata, :name_to_metadata, :description_to_metadata
      end
    end

    it "passes metadata to all custom methods on from_json" do
      metadata = { suffix: " (processed)" }
      instance = model_class.from_json(json_data, metadata: metadata)
      expect(instance.name_metadata).to eq(metadata)
      expect(instance.description_metadata).to eq(metadata)
      expect(instance.name).to eq("Test Name (processed)")
      expect(instance.description).to eq("Test Description (processed)")
    end

    it "passes metadata to all custom methods on to_json" do
      metadata = { suffix: " (t)" }
      instance = model_class.new(name: "N", description: "D")
      json_out = instance.to_json(metadata: metadata)
      expect(instance.name_to_metadata).to eq(metadata)
      expect(instance.description_to_metadata).to eq(metadata)
      parsed = JSON.parse(json_out)
      expect(parsed["name"]).to eq("N (t)")
      expect(parsed["description"]).to eq("D (t)")
    end
  end

  context "with nested models" do
    let(:json_data) do
      {
        name: "Parent",
        child: {
          name: "Child"
        }
      }.to_json
    end

    let(:child_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        json do
          map "name", to: :name, with: { from: :name_from_json, to: :name_to_json }
        end

        def name_from_json(model, value, metadata)
          model.metadata_received = metadata
          prefix = metadata&.dig(:nested_prefix) || ""
          model.name = "#{prefix}#{value}"
        end

        def name_to_json(model, hash, metadata)
          model.to_metadata_received = metadata
          prefix = metadata&.dig(:nested_prefix) || ""
          hash["name"] = "#{prefix}#{model.name}"
        end

        attr_accessor :metadata_received, :to_metadata_received
      end
    end

    let(:parent_class) do
      child_cls = child_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :child, child_cls

        json do
          map "name", to: :name
          map "child", to: :child
        end
      end
    end

    it "does not pass metadata to nested model custom methods on from_json" do
      metadata = { nested_prefix: "Nested: " }
      instance = parent_class.from_json(json_data, metadata: metadata)
      expect(instance.child.metadata_received).to be_nil
      expect(instance.child.name).to eq("Child")
    end

    it "does not pass metadata to nested model custom methods on to_json" do
      c = child_class.new(name: "Child")
      p = parent_class.new(name: "My Parent", child: c)
      metadata = { nested_prefix: "NESTED: " }
      json_out = p.to_json(metadata: metadata)
      expect(c.to_metadata_received).to eq(metadata)
      parsed = JSON.parse(json_out)
      expect(parsed["child"]["name"]).to eq("NESTED: Child")
    end
  end

  context "with practical use cases" do
    let(:json_data) do
      {
        title: "My Document",
        content: "Document content"
      }.to_json
    end

    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :content, :string

        json do
          map "title", to: :title, with: { from: :title_from_json, to: :title_to_json }
          map "content", to: :content
        end

        def title_from_json(model, value, metadata)
          source = metadata&.dig(:source) || "unknown"
          prefix = metadata&.dig(:prefix) || ""
          model.title = "#{prefix}[#{source}] #{value}"
        end

        def title_to_json(model, hash, metadata)
          source = metadata&.dig(:source) || "unknown"
          prefix = metadata&.dig(:prefix) || ""
          model.title_to_metadata = metadata
          hash["title"] = "#{prefix}[#{source}] #{model.title}"
        end

        attr_accessor :title_to_metadata
      end
    end

    it "uses metadata for processing context in from_json" do
      metadata = { source: "api", prefix: "DOC: " }
      instance = model_class.from_json(json_data, metadata: metadata)
      expect(instance.title).to eq("DOC: [api] My Document")
    end

    it "handles metadata with different data types on from_json" do
      metadata = {
        source: "file",
        timestamp: Time.now,
        options: { validate: true, transform: false }
      }
      instance = model_class.from_json(json_data, metadata: metadata)
      expect(instance.title).to eq("[file] My Document")
      # Verify metadata was passed correctly
      expect(metadata[:timestamp]).to be_a(Time)
      expect(metadata[:options]).to eq({ validate: true, transform: false })
    end

    it "uses metadata for processing context in to_json" do
      metadata = { source: "api", prefix: "DOC: " }
      instance = model_class.new(title: "T", content: "C")
      json = instance.to_json(metadata: metadata)
      expect(instance.title_to_metadata).to eq(metadata)
      parsed = JSON.parse(json)
      expect(parsed["title"]).to eq("DOC: [api] T")
    end

    it "handles metadata with different data types in to_json" do
      metadata = {
        source: "file",
        timestamp: Time.now,
        options: { validate: true, transform: false }
      }
      instance = model_class.new(title: "ZZZ", content: "C")
      json = instance.to_json(metadata: metadata)
      expect(instance.title_to_metadata).to eq(metadata)
      parsed = JSON.parse(json)
      expect(parsed["title"]).to eq("[file] ZZZ")
      expect(metadata[:timestamp]).to be_a(Time)
      expect(metadata[:options]).to eq({ validate: true, transform: false })
    end
  end

  shared_examples "with XML format" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    let(:xml_data) do
      <<~XML
        <TestModel Size="10">
          <Name>Test Name</Name>
        </TestModel>
      XML
    end

    context "when custom method accepts 3 arguments" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :size, :integer

          xml do
            root "TestModel"
            map_element "Name", to: :name, with: { from: :name_from_xml, to: :name_to_xml }
            map_attribute "Size", to: :size
          end

          def name_from_xml(model, value, metadata)
            model.metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            model.name = "#{prefix}#{value.text}"
          end

          def name_to_xml(model, parent, doc, metadata = nil)
            model.to_metadata_received = metadata
            prefix = metadata&.dig(:prefix) || ""
            if Lutaml::Model::Config.xml_adapter == Lutaml::Model::Xml::OxAdapter
              doc.create_element("Name") do |el|
                doc.add_text(el, "#{prefix}#{model.name}")
              end
            else
              el = doc.create_element("Name")
              doc.add_text(el, "#{prefix}#{model.name}")
              doc.add_element(parent, el)
            end
          end

          attr_accessor :metadata_received, :to_metadata_received
        end
      end

      it "passes metadata to XML custom method on from_xml" do
        metadata = { prefix: "XML: " }
        instance = model_class.from_xml(xml_data, metadata: metadata)
        expect(instance.metadata_received).to eq(metadata)
        expect(instance.name).to eq("XML: Test Name")
        expect(instance.size).to eq(10)
      end

      it "does not pass metadata to from_xml when not provided" do
        instance = model_class.from_xml(xml_data)
        expect(instance.metadata_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes metadata to XML custom method on to_xml" do
        instance = model_class.new(name: "Test Name", size: 10)
        metadata = { prefix: "XML: " }
        xml = instance.to_xml(metadata: metadata)
        expect(instance.to_metadata_received).to eq(metadata)
        expect(xml).to include("<Name>XML: Test Name</Name>")
        expect(xml).to include('Size="10"')
      end

      it "does not pass metadata to XML custom method on to_xml when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        xml = instance.to_xml
        expect(instance.to_metadata_received).to be_nil
        expect(xml).to include("<Name>Test Name</Name>")
        expect(xml).to include('Size="10"')
      end
    end
  end

  context "with Nokogiri adapter" do
    it_behaves_like "with XML format", Lutaml::Model::Xml::NokogiriAdapter
  end

  context "with Oga adapter" do
    it_behaves_like "with XML format", Lutaml::Model::Xml::OgaAdapter
  end

  context "with Ox adapter" do
    it_behaves_like "with XML format", Lutaml::Model::Xml::OxAdapter
  end
end
