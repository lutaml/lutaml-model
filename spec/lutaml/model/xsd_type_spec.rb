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
