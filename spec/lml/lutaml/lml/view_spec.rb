# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"
require "lutaml/lml"
require "tmpdir"
require "fileutils"

RSpec.describe "View import and filtering" do
  let(:fixtures_dir) { File.expand_path("../../fixtures/view", __dir__) }

  describe "ImportResolver" do
    it "imports model files via glob pattern" do
      file_path = File.join(fixtures_dir, "import_model.lutaml")
      doc = Lutaml::Lml.parse(File.new(file_path))

      class_names = doc.classes.map(&:name)
      expect(class_names).to include("Foo", "Bar", "Baz")
    end

    it "imports model files from nested view" do
      file_path = File.join(fixtures_dir, "import_view.lutaml")
      doc = Lutaml::Lml.parse(File.new(file_path))

      class_names = doc.classes.map(&:name)
      expect(class_names).to include("Foo", "Bar", "Baz")
    end

    it "handles circular imports without infinite loop" do
      file_path = File.join(fixtures_dir, "cycle_a.lutaml")
      expect { Lutaml::Lml.parse(File.new(file_path)) }.not_to raise_error
    end
  end

  describe "ViewResolver show/hide filtering" do
    it "filters entities with show directive" do
      file_path = File.join(fixtures_dir, "import_with_show.lutaml")
      doc = Lutaml::Lml.parse(File.new(file_path))

      class_names = doc.classes.map(&:name)
      expect(class_names).to include("Foo", "Bar")
      expect(class_names).not_to include("Baz")
    end

    it "filters entities with hide directive" do
      file_path = File.join(fixtures_dir, "import_with_hide.lutaml")
      doc = Lutaml::Lml.parse(File.new(file_path))

      class_names = doc.classes.map(&:name)
      expect(class_names).not_to include("Baz")
      expect(class_names).to include("Foo", "Bar")
    end
  end

  describe "inline and imported entities combined" do
    it "merges inline class definitions with imported ones" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "model.lutaml"), "class Imported {}")
      view = File.join(dir, "view.lutaml")
      File.write(view, "view V {\n  import \"model.lutaml\"\n  class Inline {}\n}")

      doc = Lutaml::Lml.parse(File.new(view))
      expect(doc.classes.map(&:name)).to contain_exactly("Imported", "Inline")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  describe "show/hide naming unknown entities" do
    it "does not error; the name is simply not present" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "model.lutaml"), "class Foo {}")
      view = File.join(dir, "view.lutaml")
      File.write(view, "view V {\n  import \"model.lutaml\"\n  show Foo, DoesNotExist\n}")

      doc = Lutaml::Lml.parse(File.new(view))
      expect(doc.classes.map(&:name)).to eq(["Foo"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  describe "glob mixing model and view files" do
    it "imports entities from both kinds through one glob" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "a_model.lutaml"), "class FromModel {}")
      File.write(File.join(dir, "b_view.lutaml"), "view Inner {\n  class FromView {}\n}")
      view = File.join(dir, "view.lutaml")
      File.write(view, "view V { import \"*_*.lutaml\" }")

      doc = Lutaml::Lml.parse(File.new(view))
      expect(doc.classes.map(&:name)).to contain_exactly("FromModel", "FromView")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  describe "backward compatibility" do
    it "diagram keyword with preprocessor include still works" do
      dir = Dir.mktmpdir
      shared = File.join(dir, "shared.lutaml")
      File.write(shared, "class Shared {}")
      main = File.join(dir, "main.lutaml")
      File.write(main, "diagram D {\n  include #{shared}\n}")

      doc = Lutaml::Lml.parse(File.new(main))
      expect(doc.classes.map(&:name)).to eq(["Shared"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
