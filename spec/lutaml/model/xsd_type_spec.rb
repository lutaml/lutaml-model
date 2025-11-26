require "spec_helper"
require "lutaml/model/schema"

RSpec.describe "XSD Type Declaration" do
  describe "class-level xsd_type directive" do
    it "allows setting xsd_type on Type::Value classes" do
      custom_type = Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:token"
      end

      expect(custom_type.xsd_type).to eq("xs:token")
    end

    it "returns default_xsd_type when not explicitly set" do
      custom_type = Class.new(Lutaml::Model::Type::String)

      # String's default is xs:string
      expect(custom_type.xsd_type).to eq("xs:string")
    end

    it "allows ID type with proper validation" do
      id_type = Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:ID"

        def self.cast(value)
          id = super.strip
          unless id.match?(/\A[A-Za-z_][\w.-]*\z/)
            raise Lutaml::Model::TypeError, "Invalid XML ID: #{id}"
          end

          id
        end
      end

      expect(id_type.xsd_type).to eq("xs:ID")
      expect(id_type.cast("valid-id")).to eq("valid-id")
      expect(id_type.cast("_valid")).to eq("_valid")

      expect { id_type.cast("invalid:id") }
        .to raise_error(Lutaml::Model::TypeError, /Invalid XML ID/)
    end
  end

  describe "xsd_type inheritance" do
    it "inherits xsd_type from parent Type class" do
      parent_type = Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:token"
      end

      child_type = Class.new(parent_type)

      expect(child_type.xsd_type).to eq("xs:token")
    end

    it "allows child to override parent's xsd_type" do
      parent_type = Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:token"
      end

      child_type = Class.new(parent_type) do
        xsd_type "xs:ID"
      end

      expect(parent_type.xsd_type).to eq("xs:token")
      expect(child_type.xsd_type).to eq("xs:ID")
    end

    it "inherits default_xsd_type when xsd_type not set" do
      parent_type = Class.new(Lutaml::Model::Type::Value) do
        def self.default_xsd_type
          "xs:customDefault"
        end
      end

      child_type = Class.new(parent_type)

      expect(child_type.xsd_type).to eq("xs:customDefault")
    end

    it "child can set xsd_type even if parent uses default" do
      parent_type = Class.new(Lutaml::Model::Type::String)
      # Parent uses default xs:string

      child_type = Class.new(parent_type) do
        xsd_type "xs:token"
      end

      expect(parent_type.xsd_type).to eq("xs:string")
      expect(child_type.xsd_type).to eq("xs:token")
    end
  end

  describe "attribute-level :xsd_type deprecation" do
    it "shows deprecation warning when using :xsd_type option" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :product_id, :string, xsd_type: "xs:ID"
        end
      end.to output(/DEPRECATION.*:xsd_type attribute option is deprecated/).to_stderr
    end

    it "still works with deprecation warning" do
      klass = nil
      expect do
        klass = Class.new(Lutaml::Model::Serializable) do
          attribute :product_id, :string, xsd_type: "xs:ID"

          xml do
            element "product"
            map_attribute "id", to: :product_id
          end
        end
      end.to output(/DEPRECATION/).to_stderr

      # Should still function correctly
      instance = klass.new(product_id: "test-123")
      expect(instance.product_id).to eq("test-123")
    end
  end

  describe "schema generation with xsd_type" do
    it "uses class-level xsd_type in generated XSD" do
      id_type = Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:ID"
      end

      Lutaml::Model::Type.register(:id_test, id_type)

      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :identifier, :id_test

        xml do
          element "test"
          map_attribute "id", to: :identifier
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      expect(xsd).to include('type="xs:ID"')
    end

    it "prioritizes attribute-level xsd_type over class-level (deprecated)" do
      custom_type = Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:token"
      end

      Lutaml::Model::Type.register(:custom_test, custom_type)

      klass = nil
      expect do
        klass = Class.new(Lutaml::Model::Serializable) do
          attribute :field, :custom_test, xsd_type: "xs:ID"

          xml do
            element "test"
            map_attribute "field", to: :field
          end
        end
      end.to output(/DEPRECATION/).to_stderr

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      # Attribute-level override still takes precedence (deprecated behavior)
      expect(xsd).to include('type="xs:ID"')
      expect(xsd).not_to include('type="xs:token"')
    end
  end

  describe "mapping-level xsd_type removal" do
    it "raises error when xsd_type used on map_element" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          xml do
            element "test"
            map_element "name", to: :name, xsd_type: "xs:token"
          end
        end
      end.to raise_error(
        Lutaml::Model::IncorrectMappingArgumentsError,
        /xsd_type is not allowed at mapping level/
      )
    end

    it "raises error when xsd_type used on map_attribute" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string

          xml do
            element "test"
            map_attribute "id", to: :id, xsd_type: "xs:ID"
          end
        end
      end.to raise_error(
        Lutaml::Model::IncorrectMappingArgumentsError,
        /xsd_type is not allowed at mapping level/
      )
    end

    it "proper solution: use Type::Value class with xsd_type directive" do
      token_type = Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:token"
      end

      Lutaml::Model::Type.register(:proper_token, token_type)

      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :proper_token

        xml do
          element "test"
          map_element "name", to: :name
        end
      end

      xsd = Lutaml::Model::Schema.to_xsd(klass)

      expect(xsd).to include('name="name"')
      expect(xsd).to include('type="xs:token"')
      expect(xsd).not_to include('type="xs:string"')
    end
  end

  describe "xsd_type precedence" do
    it "follows Attribute(deprecated) > Type > Default precedence" do
      custom_type = Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:normalizedString"
      end

      Lutaml::Model::Type.register(:precedence_test, custom_type)

      # Test 1: Attribute-level wins over Type-level (deprecated)
      klass1 = nil
      expect do
        klass1 = Class.new(Lutaml::Model::Serializable) do
          attribute :field, :precedence_test, xsd_type: "xs:token"

          xml do
            element "test"
            map_element "field", to: :field
          end
        end
      end.to output(/DEPRECATION/).to_stderr

      xsd1 = Lutaml::Model::Schema.to_xsd(klass1)
      expect(xsd1).to include('type="xs:token"')  # Attribute-level

      # Test 2: Type-level used when no attribute override
      klass2 = Class.new(Lutaml::Model::Serializable) do
        attribute :field, :precedence_test

        xml do
          element "test"
          map_element "field", to: :field
        end
      end

      xsd2 = Lutaml::Model::Schema.to_xsd(klass2)
      expect(xsd2).to include('type="xs:normalizedString"')  # Type-level

      # Test 3: Default used when no custom type
      klass3 = Class.new(Lutaml::Model::Serializable) do
        attribute :field, :string

        xml do
          element "test"
          map_element "field", to: :field
        end
      end

      xsd3 = Lutaml::Model::Schema.to_xsd(klass3)
      expect(xsd3).to include('type="xs:string"')  # Default
    end
  end

  describe "type library examples" do
    let(:id_type) do
      Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:ID"

        def self.cast(value)
          id = super.strip
          unless id.match?(/\A[A-Za-z_][\w.-]*\z/)
            raise Lutaml::Model::TypeError, "Invalid XML ID: #{id}"
          end

          id
        end
      end
    end

    let(:language_type) do
      Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:language"

        def self.cast(value)
          lang = super.downcase
          unless lang.match?(/\A[a-z]{2,3}(-[A-Za-z0-9]+)*\z/i)
            raise Lutaml::Model::TypeError, "Invalid language code: #{lang}"
          end

          lang
        end
      end
    end

    let(:token_type) do
      Class.new(Lutaml::Model::Type::String) do
        xsd_type "xs:token"

        def self.cast(value)
          super.strip.gsub(/\s+/, " ")
        end
      end
    end

    it "ID type validates NCName format" do
      expect(id_type.cast("valid-id")).to eq("valid-id")
      expect(id_type.cast("_valid123")).to eq("_valid123")

      expect { id_type.cast("invalid:colon") }
        .to raise_error(Lutaml::Model::TypeError, /Invalid XML ID/)
      expect { id_type.cast("123start") }
        .to raise_error(Lutaml::Model::TypeError, /Invalid XML ID/)
    end

    it "language type validates language codes" do
      expect(language_type.cast("en")).to eq("en")
      expect(language_type.cast("en-US")).to eq("en-us")
      expect(language_type.cast("zh-Hans")).to eq("zh-hans")
      expect(language_type.cast("en-US-x-twain")).to eq("en-us-x-twain")

      expect { language_type.cast("invalid_underscore") }
        .to raise_error(Lutaml::Model::TypeError, /Invalid language code/)
    end

    it "token type normalizes whitespace" do
      expect(token_type.cast("  multiple   spaces  ")).to eq("multiple spaces")
      expect(token_type.cast("single")).to eq("single")
    end
  end
end
