require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/oga_adapter"
require "lutaml/model/xml/ox_adapter"

RSpec.describe "Passing state (custom args) in from_* and to_* methods" do
  context "with JSON format" do
    let(:json_data) do
      {
        name: "Test Name",
        size: 10,
        price: 10.99,
      }.to_json
    end

    context "when custom method accepts 2 arguments (model, value)" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :size, :integer
          attribute :price, :decimal

          json do
            map "name", to: :name, with: { from: :name_from_json, to: :name_to_json }
            map "size", to: :size
            map "price", to: :price
          end

          def name_from_json(model, value)
            model.state_received = nil
            model.name = value
          end

          def name_to_json(model, hash)
            model.to_state_received = nil
            hash["name"] = model.name
          end

          attr_accessor :state_received, :to_state_received
        end
      end

      it "does not pass state when method accepts 2 arguments for from_json" do
        instance = model_class.from_json(json_data, state: { key: "value" })
        expect(instance.state_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "does not pass state when method accepts 2 arguments for to_json" do
        instance = model_class.new(name: "Test Name", size: 10, price: 11.99)
        json = instance.to_json(state: { key: "value" })
        parsed = JSON.parse(json)
        expect(instance.to_state_received).to be_nil
        expect(parsed["name"]).to eq("Test Name")
        expect(parsed["size"]).to eq(10)
      end
    end

    context "when custom method accepts 3 arguments (model, value, state)" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :size, :integer

          json do
            map "name", to: :name, with: { from: :name_from_json, to: :name_to_json }
            map "size", to: :size
          end

          def name_from_json(model, value, state)
            model.state_received = state
            prefix = state&.dig(:prefix) || ""
            model.name = "#{prefix}#{value}"
          end

          def name_to_json(model, hash, state)
            model.to_state_received = state
            prefix = state&.dig(:prefix) || ""
            hash["name"] = "#{prefix}#{model.name}"
          end

          attr_accessor :state_received, :to_state_received
        end
      end

      it "passes state when method accepts 3 arguments for from_json" do
        state = { prefix: "[", suffix: "]" }
        instance = model_class.from_json(json_data, state: state)
        expect(instance.state_received).to eq(state)
        expect(instance.name).to eq("[Test Name")
      end

      it "does not pass state to from_json when not provided" do
        instance = model_class.from_json(json_data)
        expect(instance.state_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes state when method accepts 3 arguments for to_json" do
        instance = model_class.new(name: "Test Name", size: 10)
        state = { prefix: "TO: " }
        json = instance.to_json(state: state)
        expect(instance.to_state_received).to eq(state)
        parsed = JSON.parse(json)
        expect(parsed["name"]).to eq("TO: Test Name")
        expect(parsed["size"]).to eq(10)
      end

      it "does not pass state to to_json when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        json = instance.to_json
        expect(instance.to_state_received).to be_nil
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
        size: 10,
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

          def name_from_yaml(model, value, state)
            model.state_received = state
            prefix = state&.dig(:prefix) || ""
            model.name = "#{prefix}#{value}"
          end

          def name_to_yaml(model, hash, state)
            model.to_state_received = state
            prefix = state&.dig(:prefix) || ""
            hash["name"] = "#{prefix}#{model.name}"
          end

          attr_accessor :state_received, :to_state_received
        end
      end

      it "passes state to YAML custom method for from_yaml" do
        state = { prefix: "YAML: " }
        instance = model_class.from_yaml(yaml_data, state: state)
        expect(instance.state_received).to eq(state)
        expect(instance.name).to eq("YAML: Test Name")
      end

      it "does not pass state when not provided to from_yaml" do
        instance = model_class.from_yaml(yaml_data)
        expect(instance.state_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes state to YAML custom method for to_yaml" do
        instance = model_class.new(name: "Test Name", size: 10)
        state = { prefix: "YAML: " }
        yaml = instance.to_yaml(state: state)
        expect(instance.to_state_received).to eq(state)
        expect(yaml).to include("name: 'YAML: Test Name'")
        expect(yaml).to include("size: 10")
      end

      it "does not pass state to to_yaml when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        yaml = instance.to_yaml
        expect(instance.to_state_received).to be_nil
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

          def name_from_toml(model, value, state)
            model.state_received = state
            prefix = state&.dig(:prefix) || ""
            model.name = "#{prefix}#{value}"
          end

          def name_to_toml(model, hash, state)
            model.to_state_received = state
            prefix = state&.dig(:prefix) || ""
            hash["name"] = "#{prefix}#{model.name}"
          end

          attr_accessor :state_received, :to_state_received
        end
      end

      it "passes state to TOML custom method for from_toml" do
        state = { prefix: "TOML: " }
        instance = model_class.from_toml(toml_data, state: state)
        expect(instance.state_received).to eq(state)
        expect(instance.name).to eq("TOML: Test Name")
      end

      it "does not pass state to from_toml when not provided" do
        instance = model_class.from_toml(toml_data)
        expect(instance.state_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes state to TOML custom method for to_toml" do
        instance = model_class.new(name: "Test Name", size: 10)
        state = { prefix: "TOML: " }
        toml = instance.to_toml(state: state)
        expect(instance.to_state_received).to eq(state)
        expect(toml).to include('name = "TOML: Test Name"')
        expect(toml).to include("size = 10")
      end

      it "does not pass state to to_toml when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        toml = instance.to_toml
        expect(instance.to_state_received).to be_nil
        expect(toml).to include('name = "Test Name"')
        expect(toml).to include("size = 10")
      end
    end
  end

  context "with hash format" do
    let(:hash_data) do
      {
        "name" => "Test Name",
        "size" => 10,
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

          def name_from_hash(model, value, state)
            model.state_received = state
            prefix = state&.dig(:prefix) || ""
            model.name = "#{prefix}#{value}"
          end

          def name_to_hash(model, hash, state)
            model.to_state_received = state
            prefix = state&.dig(:prefix) || ""
            hash["name"] = "#{prefix}#{model.name}"
          end

          attr_accessor :state_received, :to_state_received
        end
      end

      it "passes state to hash custom method for from_hash" do
        state = { prefix: "Hash: " }
        instance = model_class.from_hash(hash_data, state: state)
        expect(instance.state_received).to eq(state)
        expect(instance.name).to eq("Hash: Test Name")
      end

      it "does not pass state to from_hash when not provided" do
        instance = model_class.from_hash(hash_data)
        expect(instance.state_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes state to hash custom method for to_hash" do
        instance = model_class.new(name: "Test Name", size: 10)
        state = { prefix: "Hash: " }
        hash_out = instance.to_hash(state: state)
        expect(instance.to_state_received).to eq(state)
        expect(hash_out["name"]).to eq("Hash: Test Name")
        expect(hash_out["size"]).to eq(10)
      end

      it "does not pass state to to_hash when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        hash_out = instance.to_hash
        expect(instance.to_state_received).to be_nil
        expect(hash_out["name"]).to eq("Test Name")
        expect(hash_out["size"]).to eq(10)
      end
    end
  end

  context "with multiple attributes using state" do
    let(:json_data) do
      {
        name: "Test Name",
        description: "Test Description",
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

        def name_from_json(model, value, state)
          model.name_state = state
          suffix = state&.dig(:suffix) || ""
          model.name = "#{value}#{suffix}"
        end

        def description_from_json(model, value, state)
          model.description_state = state
          suffix = state&.dig(:suffix) || ""
          model.description = "#{value}#{suffix}"
        end

        def name_to_json(model, hash, state)
          model.name_to_state = state
          suffix = state&.dig(:suffix) || ""
          hash["name"] = "#{model.name}#{suffix}"
        end

        def description_to_json(model, hash, state)
          model.description_to_state = state
          suffix = state&.dig(:suffix) || ""
          hash["description"] = "#{model.description}#{suffix}"
        end

        attr_accessor :name_state, :description_state, :name_to_state, :description_to_state
      end
    end

    it "passes state to all custom methods on from_json" do
      state = { suffix: " (processed)" }
      instance = model_class.from_json(json_data, state: state)
      expect(instance.name_state).to eq(state)
      expect(instance.description_state).to eq(state)
      expect(instance.name).to eq("Test Name (processed)")
      expect(instance.description).to eq("Test Description (processed)")
    end

    it "passes state to all custom methods on to_json" do
      state = { suffix: " (t)" }
      instance = model_class.new(name: "N", description: "D")
      json_out = instance.to_json(state: state)
      expect(instance.name_to_state).to eq(state)
      expect(instance.description_to_state).to eq(state)
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
          name: "Child",
        },
      }.to_json
    end

    let(:child_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        json do
          map "name", to: :name, with: { from: :name_from_json, to: :name_to_json }
        end

        def name_from_json(model, value, state)
          model.state_received = state
          prefix = state&.dig(:nested_prefix) || ""
          model.name = "#{prefix}#{value}"
        end

        def name_to_json(model, hash, state)
          model.to_state_received = state
          prefix = state&.dig(:nested_prefix) || ""
          hash["name"] = "#{prefix}#{model.name}"
        end

        attr_accessor :state_received, :to_state_received
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

    it "does not pass state to nested model custom methods on from_json" do
      state = { nested_prefix: "Nested: " }
      instance = parent_class.from_json(json_data, state: state)
      expect(instance.child.state_received).to be_nil
      expect(instance.child.name).to eq("Child")
    end

    it "does not pass state to nested model custom methods on to_json" do
      c = child_class.new(name: "Child")
      p = parent_class.new(name: "My Parent", child: c)
      state = { nested_prefix: "NESTED: " }
      json_out = p.to_json(state: state)
      expect(c.to_state_received).to eq(state)
      parsed = JSON.parse(json_out)
      expect(parsed["child"]["name"]).to eq("NESTED: Child")
    end
  end

  context "with practical use cases" do
    let(:json_data) do
      {
        title: "My Document",
        content: "Document content",
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

        def title_from_json(model, value, state)
          source = state&.dig(:source) || "unknown"
          prefix = state&.dig(:prefix) || ""
          model.title = "#{prefix}[#{source}] #{value}"
        end

        def title_to_json(model, hash, state)
          source = state&.dig(:source) || "unknown"
          prefix = state&.dig(:prefix) || ""
          model.title_to_state = state
          hash["title"] = "#{prefix}[#{source}] #{model.title}"
        end

        attr_accessor :title_to_state
      end
    end

    it "uses state for processing context in from_json" do
      state = { source: "api", prefix: "DOC: " }
      instance = model_class.from_json(json_data, state: state)
      expect(instance.title).to eq("DOC: [api] My Document")
    end

    it "handles state with different data types on from_json" do
      state = {
        source: "file",
        timestamp: Time.now,
        options: { validate: true, transform: false },
      }
      instance = model_class.from_json(json_data, state: state)
      expect(instance.title).to eq("[file] My Document")
      # Verify state was passed correctly
      expect(state[:timestamp]).to be_a(Time)
      expect(state[:options]).to eq({ validate: true, transform: false })
    end

    it "uses state for processing context in to_json" do
      state = { source: "api", prefix: "DOC: " }
      instance = model_class.new(title: "T", content: "C")
      json = instance.to_json(state: state)
      expect(instance.title_to_state).to eq(state)
      parsed = JSON.parse(json)
      expect(parsed["title"]).to eq("DOC: [api] T")
    end

    it "handles state with different data types in to_json" do
      state = {
        source: "file",
        timestamp: Time.now,
        options: { validate: true, transform: false },
      }
      instance = model_class.new(title: "ZZZ", content: "C")
      json = instance.to_json(state: state)
      expect(instance.title_to_state).to eq(state)
      parsed = JSON.parse(json)
      expect(parsed["title"]).to eq("[file] ZZZ")
      expect(state[:timestamp]).to be_a(Time)
      expect(state[:options]).to eq({ validate: true, transform: false })
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

          def name_from_xml(model, value, state)
            model.state_received = state
            prefix = state&.dig(:prefix) || ""
            model.name = "#{prefix}#{value.text}"
          end

          def name_to_xml(model, parent, doc, state = nil)
            model.to_state_received = state
            prefix = state&.dig(:prefix) || ""
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

          attr_accessor :state_received, :to_state_received
        end
      end

      it "passes state to XML custom method on from_xml" do
        state = { prefix: "XML: " }
        instance = model_class.from_xml(xml_data, state: state)
        expect(instance.state_received).to eq(state)
        expect(instance.name).to eq("XML: Test Name")
        expect(instance.size).to eq(10)
      end

      it "does not pass state to from_xml when not provided" do
        instance = model_class.from_xml(xml_data)
        expect(instance.state_received).to be_nil
        expect(instance.name).to eq("Test Name")
      end

      it "passes state to XML custom method on to_xml" do
        instance = model_class.new(name: "Test Name", size: 10)
        state = { prefix: "XML: " }
        xml = instance.to_xml(state: state)
        expect(instance.to_state_received).to eq(state)
        expect(xml).to include("<Name>XML: Test Name</Name>")
        expect(xml).to include('Size="10"')
      end

      it "does not pass state to XML custom method on to_xml when not provided" do
        instance = model_class.new(name: "Test Name", size: 10)
        xml = instance.to_xml
        expect(instance.to_state_received).to be_nil
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
