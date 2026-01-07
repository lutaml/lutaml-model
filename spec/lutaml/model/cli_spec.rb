# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require "lutaml/model/cli"

RSpec.describe Lutaml::Model::Cli do
  let(:cli) { described_class.new }

  # Shared test data - defined once at top level
  def test_model_content
    <<~RUBY
      require "lutaml/model"

      class ExtractLanguage < Lutaml::Model::Serializable
        attribute :language, :string
        attribute :order, :integer

        xml do
          map_attribute "language", to: :language, namespace: nil
          map_attribute "order", to: :order, namespace: nil
        end
      end

      class TermiumExtract < Lutaml::Model::Serializable
        attribute :language, :string
        attribute :extract_language, ExtractLanguage, collection: true

        xml do
          root "termium_extract"
          namespace "http://termium.tpsgc-pwgsc.gc.ca/schemas/2012/06/Termium", "ns2"

          map_attribute "language", to: :language, namespace: nil
          map_element "extractLanguage", to: :extract_language, namespace: nil
        end
      end
    RUBY
  end

  def xml_file1_content
    <<~XML
      <ns2:termium_extract xmlns:ns2="http://termium.tpsgc-pwgsc.gc.ca/schemas/2012/06/Termium"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" language="EN"
        xsi:schemaLocation="http://termium.tpsgc-pwgsc.gc.ca/schemas/2012/06/Termium http://termium.tpsgc-pwgsc.gc.ca/schemas/2012/06/Termium.xsd">
          <extractLanguage language="EN" order="0" />
          <extractLanguage language="FR" order="1" />
      </ns2:termium_extract>
    XML
  end

  def xml_file2_content
    <<~XML
      <ns2:termium_extract xmlns:ns2="http://termium.tpsgc-pwgsc.gc.ca/schemas/2012/06/Termium"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://termium.tpsgc-pwgsc.gc.ca/schemas/2012/06/Termium http://termium.tpsgc-pwgsc.gc.ca/schemas/2012/06/Termium.xsd">
          <extractLanguage language="EN1" order="1" />
      </ns2:termium_extract>
    XML
  end

  def yaml_file_content
    <<~YAML
      ---
      language: EN
      extract_language:
      - language: EN
        order: 0
      - language: FR
        order: 1
    YAML
  end

  def json_file_content
    <<~JSON
      {
        "language": "EN",
        "extract_language": [
          {
            "language": "EN",
            "order": 0
          },
          {
            "language": "FR",
            "order": 1
          }
        ]
      }
    JSON
  end

  # Setup and teardown helpers
  def setup_test_files(temp_dir)
    model_file = File.join(temp_dir, "test_model.rb")
    source_xml_path = File.join(temp_dir, "source.xml")
    target_xml_path = File.join(temp_dir, "target.xml")
    yaml_file_path = File.join(temp_dir, "file.yml")
    json_file_path = File.join(temp_dir, "file.json")

    File.write(model_file, test_model_content)
    File.write(source_xml_path, xml_file1_content)
    File.write(target_xml_path, xml_file2_content)
    File.write(yaml_file_path, yaml_file_content)
    File.write(json_file_path, json_file_content)

    {
      model_file: model_file,
      source_xml_path: source_xml_path,
      target_xml_path: target_xml_path,
      yaml_file_path: yaml_file_path,
      json_file_path: json_file_path,
    }
  end

  before do
    lib_path = File.expand_path("../../../lib", __dir__)
    $LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)
  end

  describe "#compare" do
    context "when comparing XML files" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:files) { setup_test_files(temp_dir) }
      let(:options) do
        {
          model_file: files[:model_file],
          root_class: "TermiumExtract",
        }
      end

      after { FileUtils.rm_rf(temp_dir) }

      it "outputs differences and similarity score" do
        cli.options = options

        expect { cli.compare(files[:source_xml_path], files[:target_xml_path]) }.to output(
          a_string_including(
            "Differences between",
            "TermiumExtract",
            "language",
            "extract_language",
            "Similarity score:",
          ),
        ).to_stdout
      end

      it "shows the correct file paths in output" do
        cli.options = options

        expect { cli.compare(files[:source_xml_path], files[:target_xml_path]) }.to output(
          a_string_including("Differences between #{files[:source_xml_path]} and #{files[:target_xml_path]}:"),
        ).to_stdout
      end

      it "includes similarity percentage in output" do
        cli.options = options

        expect { cli.compare(files[:source_xml_path], files[:target_xml_path]) }.to output(
          a_string_matching(/Similarity score: \d+(\.\d+)?%/),
        ).to_stdout
      end

      it "shows 100% similarity when comparing identical files" do
        cli.options = options

        expect { cli.compare(files[:source_xml_path], files[:source_xml_path]) }.to output(
          a_string_including("Similarity score: 100%"),
        ).to_stdout
      end
    end

    context "when comparing different format files" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:files) { setup_test_files(temp_dir) }
      let(:options) do
        {
          model_file: files[:model_file],
          root_class: "TermiumExtract",
        }
      end

      after { FileUtils.rm_rf(temp_dir) }

      it "successfully compares YAML and XML files" do
        cli.options = options

        expect { cli.compare(files[:yaml_file_path], files[:target_xml_path]) }.to output(
          a_string_including(
            "Differences between",
            "TermiumExtract",
            "Similarity score:",
          ),
        ).to_stdout
      end

      it "detects YAML vs XML format-specific differences correctly" do
        cli.options = options

        expect { cli.compare(files[:yaml_file_path], files[:target_xml_path]) }.to output(
          a_string_including("language", "extract_language"),
        ).to_stdout
      end

      it "successfully compares JSON and XML files" do
        cli.options = options

        expect { cli.compare(files[:json_file_path], files[:target_xml_path]) }.to output(
          a_string_including(
            "Differences between",
            "TermiumExtract",
            "Similarity score:",
          ),
        ).to_stdout
      end
    end

    context "with invalid file inputs" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:files) { setup_test_files(temp_dir) }
      let(:options) do
        {
          model_file: files[:model_file],
          root_class: "TermiumExtract",
        }
      end

      after { FileUtils.rm_rf(temp_dir) }

      it "raises error when first file doesn't exist" do
        cli.options = options

        expect do
          cli.compare("nonexistent1.xml", files[:target_xml_path])
        end.to raise_error(ArgumentError, /File not found: nonexistent1\.xml/)
      end

      it "raises error when second file doesn't exist" do
        cli.options = options

        expect do
          cli.compare(files[:source_xml_path], "nonexistent2.xml")
        end.to raise_error(ArgumentError, /File not found: nonexistent2\.xml/)
      end
    end

    context "with invalid configuration options" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:files) { setup_test_files(temp_dir) }

      after { FileUtils.rm_rf(temp_dir) }

      it "raises error when model_file option is missing" do
        options = { root_class: "TermiumExtract" }
        cli.options = options

        expect do
          cli.compare(files[:source_xml_path], files[:target_xml_path])
        end.to raise_error(ArgumentError, "model_file argument is required")
      end

      it "raises error when root_class option is missing" do
        options = { model_file: files[:model_file] }
        cli.options = options

        expect do
          cli.compare(files[:source_xml_path], files[:target_xml_path])
        end.to raise_error(ArgumentError, "root_class argument is required")
      end

      it "raises error when model file doesn't exist" do
        options = {
          model_file: "nonexistent_model.rb",
          root_class: "TermiumExtract",
        }
        cli.options = options

        expect do
          cli.compare(files[:source_xml_path], files[:target_xml_path])
        end.to raise_error(ArgumentError, /Model file not found: nonexistent_model\.rb/)
      end

      it "raises error when root class doesn't exist" do
        options = {
          model_file: files[:model_file],
          root_class: "NonExistentClass",
        }
        cli.options = options

        expect do
          cli.compare(files[:source_xml_path], files[:target_xml_path])
        end.to raise_error(NameError, /NonExistentClass not defined in model-file/)
      end
    end

    context "with malformed files" do
      let(:temp_dir) { Dir.mktmpdir }
      let(:files) { setup_test_files(temp_dir) }
      let(:malformed_xml) { File.join(temp_dir, "malformed.xml") }
      let(:malformed_yaml) { File.join(temp_dir, "malformed.yml") }
      let(:options) do
        {
          model_file: files[:model_file],
          root_class: "TermiumExtract",
        }
      end

      before do
        # Create XML with invalid structure that Nokogiri will reject
        File.write(malformed_xml, "<?xml version='1.0'?><invalid>>malformed<<xml>")
        File.write(malformed_yaml, "invalid: yaml: content: [unclosed")
      end

      after { FileUtils.rm_rf(temp_dir) }

      it "handles malformed XML gracefully" do
        cli.options = options

        # The XML parser is forgiving and creates empty models for malformed XML
        expect { cli.compare(malformed_xml, files[:target_xml_path]) }.to output(
          a_string_including("Differences between", "Similarity score:"),
        ).to_stdout
      end

      it "raises error when parsing malformed YAML" do
        cli.options = options

        expect do
          cli.compare(malformed_yaml, files[:target_xml_path])
        end.to raise_error(StandardError, /Error parsing file.*malformed\.yml/)
      end
    end
  end

  describe "#validate_compare_options!" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:files) { setup_test_files(temp_dir) }

    after { FileUtils.rm_rf(temp_dir) }

    it "passes with valid options" do
      options = {
        model_file: files[:model_file],
        root_class: "TermiumExtract",
      }

      expect do
        cli.send(:validate_compare_options!, options)
      end.not_to raise_error
    end

    it "fails when model_file is nil" do
      options = { root_class: "TermiumExtract" }

      expect do
        cli.send(:validate_compare_options!, options)
      end.to raise_error(ArgumentError, "model_file argument is required")
    end

    it "fails when root_class is nil" do
      options = { model_file: files[:model_file] }

      expect do
        cli.send(:validate_compare_options!, options)
      end.to raise_error(ArgumentError, "root_class argument is required")
    end
  end

  describe "#model_from_file" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:files) { setup_test_files(temp_dir) }

    before do
      require files[:model_file]
    end

    after { FileUtils.rm_rf(temp_dir) }

    it "loads model from XML file" do
      model_class = TermiumExtract
      result = cli.send(:model_from_file, files[:source_xml_path], model_class)

      expect(result).to be_a(TermiumExtract)
      expect(result.language).to eq("EN")
      expect(result.extract_language.length).to eq(2)
      expect(result.extract_language.first.language).to eq("EN")
    end

    it "loads model from YAML file" do
      model_class = TermiumExtract
      result = cli.send(:model_from_file, files[:yaml_file_path], model_class)

      expect(result).to be_a(TermiumExtract)
      expect(result.language).to eq("EN")
      expect(result.extract_language.length).to eq(2)
    end

    it "loads model from JSON file" do
      model_class = TermiumExtract
      result = cli.send(:model_from_file, files[:json_file_path], model_class)

      expect(result).to be_a(TermiumExtract)
      expect(result.language).to eq("EN")
      expect(result.extract_language.length).to eq(2)
    end

    it "handles YAML file with .yml extension" do
      yml_file = File.join(temp_dir, "test.yml")
      File.write(yml_file, yaml_file_content)

      model_class = TermiumExtract
      result = cli.send(:model_from_file, yml_file, model_class)

      expect(result).to be_a(TermiumExtract)
      expect(result.language).to eq("EN")
    end

    it "raises error for unsupported file format" do
      txt_file = File.join(temp_dir, "test.txt")
      File.write(txt_file, "some text content")

      model_class = TermiumExtract

      expect do
        cli.send(:model_from_file, txt_file, model_class)
      end.to raise_error(StandardError, /Error parsing file/)
    end
  end
end
