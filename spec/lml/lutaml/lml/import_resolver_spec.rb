# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"
require "tmpdir"
require "fileutils"

RSpec.describe Lutaml::Lml::ImportResolver do
  describe "#resolve" do
    it "resolves glob patterns to model files" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "foo.lutaml"), "class Foo { name: String }")
      File.write(File.join(dir, "bar.lutaml"), "class Bar { count: Integer }")

      doc = Lutaml::Lml::Document.new(
        view_imports: [Lutaml::Lml::ViewImport.new(path: File.join(dir, "*.lutaml"))]
      )
      resolver = described_class.new(nil)
      entities, _associations = resolver.resolve(doc)

      expect(entities.values.map(&:name)).to include("Foo", "Bar")
    ensure
      FileUtils.rm_rf(dir)
    end

    it "imports a model file whose comment mentions view (no sniffing)" do
      dir = Dir.mktmpdir
      model = File.join(dir, "model.lutaml")
      File.write(model, "// this is a view of the sensor domain\nclass Sensor {}")

      doc = Lutaml::Lml::Document.new(
        view_imports: [Lutaml::Lml::ViewImport.new(path: model)]
      )
      resolver = described_class.new(nil)
      entities, = resolver.resolve(doc)
      expect(entities.keys).to eq(["Sensor"])
    ensure
      FileUtils.rm_rf(dir)
    end

    it "raises when a glob matches no files" do
      doc = Lutaml::Lml::Document.new(
        view_imports: [Lutaml::Lml::ViewImport.new(path: "/nonexistent/path/*.lutaml")]
      )
      resolver = described_class.new(nil)
      expect { resolver.resolve(doc) }
        .to raise_error(Lutaml::Lml::ImportError, /matched no files/)
    end

    it "silently deduplicates identical entities imported twice" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "a.lutaml"), "class Foo { x: String }")
      File.write(File.join(dir, "b.lutaml"), "class Foo { x: String }")

      doc = Lutaml::Lml::Document.new(
        view_imports: [Lutaml::Lml::ViewImport.new(path: File.join(dir, "*.lutaml"))]
      )
      resolver = described_class.new(nil)
      entities, = resolver.resolve(doc)

      expect(entities.keys).to eq(["Foo"])
    ensure
      FileUtils.rm_rf(dir)
    end

    it "raises when the same name is defined differently in two imports" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "a.lutaml"), "class Foo { x: String }")
      File.write(File.join(dir, "b.lutaml"), "class Foo { y: Integer }")

      doc = Lutaml::Lml::Document.new(
        view_imports: [Lutaml::Lml::ViewImport.new(path: File.join(dir, "*.lutaml"))]
      )
      resolver = described_class.new(nil)

      expect { resolver.resolve(doc) }
        .to raise_error(Lutaml::Lml::ImportError, /'Foo' is defined differently/)
    ensure
      FileUtils.rm_rf(dir)
    end

    it "resolves relative to base_path" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "model.lutaml"), "class Baz {}")

      view_file = File.join(dir, "view.lutaml")
      File.write(view_file, "view V { import \"model.lutaml\" }")

      doc = Lutaml::Lml.parse(File.new(view_file))
      expect(doc.classes.map(&:name)).to include("Baz")
    ensure
      FileUtils.rm_rf(dir)
    end

    it "raises on unreadable files" do
      skip "Unix file modes not enforced on Windows" if Gem.win_platform?
      dir = Dir.mktmpdir
      path = File.join(dir, "unreadable.lutaml")
      File.write(path, "class Foo {}")
      FileUtils.chmod(0o000, path)
      doc = Lutaml::Lml::Document.new(
        view_imports: [Lutaml::Lml::ViewImport.new(path: path)]
      )
      resolver = described_class.new(nil)
      expect { resolver.resolve(doc) }
        .to raise_error(Lutaml::Lml::ImportError, /cannot read import/)
    ensure
      FileUtils.chmod(0o644, File.join(dir, "unreadable.lutaml")) rescue nil
      FileUtils.rm_rf(dir)
    end
  end
end
