# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "lutaml/model/schema/renderer"
require "lutaml/model/schema/helpers/template_helper"

RSpec.describe Lutaml::Model::Schema::Renderer do
  describe ".render" do
    let(:template_path) do
      file = Tempfile.new(["template", ".erb"])
      file.write(template_content)
      file.close
      file.path
    end

    after do
      File.delete(template_path) if File.exist?(template_path)
    end

    context "with simple variable" do
      let(:template_content) { "<%= name %>" }

      it "renders template with single variable" do
        result = described_class.render(template_path, name: "Test")
        expect(result).to eq("Test")
      end
    end

    context "with multiple variables" do
      let(:template_content) { "<%= first %> <%= last %>" }

      it "renders template with multiple variables" do
        result = described_class.render(template_path, first: "John", last: "Doe")
        expect(result).to eq("John Doe")
      end
    end

    context "with TemplateHelper methods" do
      let(:template_content) { "<%= indent(2) %>indented" }

      it "provides access to helper methods" do
        result = described_class.render(template_path, {})
        expect(result).to eq("    indented")
      end
    end

    context "with complex object" do
      let(:template_content) do
        <<~ERB
          <%= schema.name %>
          <% schema.attributes.each do |attr| -%>
          - <%= attr %>
          <% end -%>
        ERB
      end

      let(:schema) do
        double("schema", name: "TestClass", attributes: %w[name email])
      end

      it "renders template with complex object" do
        result = described_class.render(template_path, schema: schema)
        expect(result).to eq("TestClass\n- name\n- email\n")
      end
    end

    context "with trim mode" do
      let(:template_content) do
        <<~ERB
          line1
          - <% if show_line2 -%>
          line2
          <% end -%>
          line3
        ERB
      end

      it "respects trim mode for cleaner output" do
        result = described_class.render(template_path, show_line2: true)
        expect(result).to eq("line1\n- line2\nline3\n")
      end

      it "handles conditional rendering" do
        result = described_class.render(template_path, show_line2: false)
        expect(result).to eq("line1\n- line3\n")
      end
    end
  end

  describe "#initialize" do
    let(:template_path) do
      file = Tempfile.new(["template", ".erb"])
      file.write("test")
      file.close
      file.path
    end

    after do
      File.delete(template_path) if File.exist?(template_path)
    end

    it "reads template file content" do
      renderer = described_class.new(template_path)
      expect(renderer.render({})).to eq("test")
    end
  end

  describe Lutaml::Model::Schema::Renderer::Context do
    it "allows dynamic attribute access" do
      context = described_class.new(foo: "bar", baz: 123)
      expect(context.foo).to eq("bar")
      expect(context.baz).to eq(123)
    end

    it "allows modifying attributes" do
      context = described_class.new(foo: "bar")
      context.foo = "changed"
      expect(context.foo).to eq("changed")
    end

    it "returns nil for undefined attributes" do
      context = described_class.new
      expect(context.undefined_attr).to be_nil
    end
  end
end
