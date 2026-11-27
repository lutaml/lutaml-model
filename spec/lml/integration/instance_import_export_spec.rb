# frozen_string_literal: true

require "spec_helper"
require_relative "../lml_spec_setup"
require "lutaml/lml"
require "lutaml/lml/executor"
require "tmpdir"

RSpec.describe "End-to-end instance import/export", type: :integration do
  let(:models_lml) do
    <<~LML
      models Catalog {
        class Product {
          attribute id { type String }
          attribute name { type String }
          attribute price { type String }
        }
      }
    LML
  end

  let(:input_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Products>
        <Product>
          <id>P001</id>
          <name>Widget</name>
          <price>9.99</price>
        </Product>
        <Product>
          <id>P002</id>
          <name>Gadget</name>
          <price>14.50</price>
        </Product>
      </Products>
    XML
  end

  let(:workdir) { Dir.mktmpdir("lml-integration-") }

  after do
    FileUtils.rm_rf(workdir)
  end

  it "compiles models, imports XML, validates, and exports XML" do
    compiled = Lutaml::Lml.compile(StringIO.new(models_lml))
    expect(compiled).to include("Product")

    product_class = compiled["Product"]
    expect(product_class).to respond_to(:from_xml)
    expect(product_class.instance_method(:to_xml)).to be_an(UnboundMethod)

    input_path = File.join(workdir, "products.xml")
    output_path = File.join(workdir, "products_out.xml")
    File.write(input_path, input_xml)

    instances_lml = <<~LML
      instances {
        collection "all_products" {
          validation {
            condition "count >= 2"
          }
        }

        import {
          xml "#{input_path}" {
            map_to Product
            where "/Products/Product"
          }
        }

        export {
          format xml {
            file "#{output_path}"
            root "Products"
            indent true
          }
        }
      }
    LML

    doc = Lutaml::Lml.parse_document(StringIO.new(instances_lml))

    instances = Lutaml::Lml::Executor.run(doc, compiled: compiled)

    expect(instances.length).to eq(2)
    expect(instances[0]).to be_a(product_class)
    expect(instances[0].id).to eq("P001")
    expect(instances[0].name).to eq("Widget")
    expect(instances[1].id).to eq("P002")

    expect(File.exist?(output_path)).to be true
    output = File.read(output_path)
    expect(output).to include("<Products>")
    expect(output).to include("<id>P001</id>")
    expect(output).to include("<name>Widget</name>")
    expect(output).to include("<id>P002</id>")
    expect(output).to include("<name>Gadget</name>")
    expect(output).to include("</Products>")
  end
end
