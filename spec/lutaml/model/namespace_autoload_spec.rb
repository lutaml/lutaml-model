# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "securerandom"

# When a Serializable declares an attribute with a string type that points
# into a namespace using autoload + lazy per-file registration, resolving
# just the leaf constant via const_get leaves sibling types unregistered.
# Deserialization of the root then fails because child element types are
# missing from the registry.
#
# The fix in `Lutaml::Model::Attribute.cast_from_string!` walks each parent
# namespace segment of the string type and force-resolves its constants so
# autoloads fire and per-file registration side-effects complete.

RSpec.describe "string-type resolution with namespace autoload" do
  # Build a throwaway namespace with autoloads pointing at files that
  # self-register on load. This mirrors the pattern used by gems like
  # `mml` (where each `lib/mml/v3/<tag>.rb` ends with
  # `Configuration.register_model(...)`).
  def build_namespace(name)
    Object.const_set(name, Module.new)

    ns = Object.const_get(name)
    ns.const_set(:REGISTRY, {})
    ns.const_set(:LOADED_FILES, [])
    ns.singleton_class.define_method(:loaded_files) { ns::LOADED_FILES }
    ns.singleton_class.define_method(:registry) { ns::REGISTRY }

    tmpdir = Dir.mktmpdir("lutaml-autoload-#{name.downcase}")

    root_file = File.join(tmpdir, "root.rb")
    sibling_file = File.join(tmpdir, "sibling.rb")

    File.write(root_file, <<~RUBY)
      #{name}::LOADED_FILES << "root"
      #{name}::REGISTRY[:root] = Class.new
      #{name}.const_set(:Root, #{name}::REGISTRY[:root])
    RUBY

    File.write(sibling_file, <<~RUBY)
      #{name}::LOADED_FILES << "sibling"
      #{name}::REGISTRY[:sibling] = Class.new
      #{name}.const_set(:Sibling, #{name}::REGISTRY[:sibling])
    RUBY

    ns.autoload(:Root, root_file)
    ns.autoload(:Sibling, sibling_file)
    ns
  end

  # Each spec builds a uniquely-named namespace (via SecureRandom), so
  # cross-test cleanup is unnecessary. Constants leak for the duration of
  # the process but never collide.

  let(:namespace_name) { :"LutamlAutoloadTest#{SecureRandom.hex(4)}" }
  let(:namespace_module) { Object.const_get(namespace_name) }

  it "eager-resolves sibling autoloads when a namespaced string type is cast" do
    build_namespace(namespace_name)
    expect(namespace_module.loaded_files).to be_empty

    Lutaml::Model::Attribute.cast_from_string!("#{namespace_module}::Root")

    expect(namespace_module.loaded_files).to include("root", "sibling")
    expect(namespace_module.registry.key?(:root)).to be(true)
    expect(namespace_module.registry.key?(:sibling)).to be(true)
  end

  it "is idempotent across multiple cast_from_string! calls within the same namespace" do
    build_namespace(namespace_name)

    Lutaml::Model::Attribute.cast_from_string!("#{namespace_module}::Root")
    first_count = namespace_module.loaded_files.length

    Lutaml::Model::Attribute.cast_from_string!("#{namespace_module}::Sibling")
    expect(namespace_module.loaded_files.length).to eq(first_count)
  end

  it "raises ArgumentError for unknown types" do
    expect do
      Lutaml::Model::Attribute.cast_from_string!("LutamlAutoloadDoesNotExist::X")
    end.to raise_error(ArgumentError, /Unknown Lutaml::Model::Type/)
  end
end
