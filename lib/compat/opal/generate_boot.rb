# frozen_string: true

# One-shot generator for lib/compat/opal/lutaml_model_boot.rb.
#
# Walks lib/lutaml/**/*.rb and extracts every `autoload :Name, "path"`
# declaration (single-line or multi-line), resolving the standard
# `"#{__dir__}/..."` and `"#{File.dirname(__FILE__)}/..."` interpolation
# patterns relative to the declaring file's directory.
#
# Opal treats autoload as a no-op, so every autoload target must appear
# here as an explicit `require` for nested constants to resolve at runtime.
#
# Run after adding/removing any autoload in lib/lutaml/:
#   ruby lib/compat/opal/generate_boot.rb

require "pathname"

REPO_ROOT = Pathname.new(File.expand_path("../../..", __dir__))
LIB       = REPO_ROOT.join("lib")

# Patterns excluded under Opal because they pull in native-only deps
# (Nokogiri/Ox C extensions, Thor CLI, etc.). REXML is pure Ruby and
# ships in the bundled gem + moxml's lib/compat/opal/rexml/* shadows,
# so it is NOT excluded — it is a fully working second Opal adapter.
NATIVE_ONLY_PATTERNS = [
  %r{(nokogiri|ox)_adapter\z},
  %r{/schema/(relaxng|xsd)\b},
  %r{/schema_builder/(nokogiri|oga)\b},
  %r{/schema/builder/(nokogiri|oga)\b},
  %r{\Alutaml/model/cli\z},
].freeze

# Match `autoload :Name, "...anything..."` where the string argument may
# span multiple physical lines (whitespace after the comma).
DECL_RE = /autoload\s+:[A-Za-z0-9_]+\s*,\s*"([^"]+)"/

# Stitches multi-line autoload declarations into a single logical line so
# DECL_RE can match. We only merge when the line ends right after the
# comma that follows `autoload :Name`.
def join_multiline_autoloads(src)
  src.gsub(/(autoload\s+:[A-Za-z0-9_]+\s*,)\s*\n\s*/) { "#{Regexp.last_match(1)} " }
end

# Resolve an autoload's raw string argument to a require path relative to
# LIB. Both common interpolation shapes resolve relative to the declaring
# file's directory, which is what MRI does for them.
def resolve_path(raw, declaring_file)
  declaring_dir = Pathname.new(declaring_file).dirname

  if raw.start_with?("\#{__dir__}/")
    subdir = raw.sub("\#{__dir__}/", "").delete_suffix(".rb")
    (declaring_dir + subdir).relative_path_from(LIB).to_s.delete_suffix(".rb")
  elsif raw.start_with?("\#{File.dirname(__FILE__)}/")
    subdir = raw.sub("\#{File.dirname(__FILE__)}/", "").delete_suffix(".rb")
    (declaring_dir + subdir).relative_path_from(LIB).to_s.delete_suffix(".rb")
  elsif raw.start_with?("lutaml/")
    raw.delete_suffix(".rb")
  else
    raw.delete_suffix(".rb")
  end
end

paths = []
Dir.glob("#{LIB}/lutaml/**/*.rb").each do |file|
  src = File.read(file)
  # Strip full-line and trailing comments so commented-out autoload
  # examples (e.g. in type_registry.rb) don't end up in the boot file.
  src = src.lines.reject { |line| line.lstrip.start_with?("#") }.join
  join_multiline_autoloads(src).scan(DECL_RE).each do |(raw)|
    paths << resolve_path(raw, file)
  end
end

paths = paths.uniq.sort
native_only = paths.select { |p| NATIVE_ONLY_PATTERNS.any? { |re| p =~ re } }
opal_paths  = paths - native_only

# Order matters: namespace-defining entry files must load before any of
# their nested files. lutaml/model.rb declares the Lutaml::Model module
# (referenced by every other file); lutaml/xml.rb declares Lutaml::Xml.
# After the entry files, load by depth-then-name so a parent file (e.g.
# lutaml/hash_format.rb) is required before its children (e.g.
# lutaml/hash_format/adapter/document.rb).
#
# ENTRY_FILES are added unconditionally: they are top-level entry points
# that nothing else autoloads (because they ARE the entry points users
# require directly), so they would otherwise be missing from the list.
ENTRY_FILES = %w[lutaml/model lutaml/xml].freeze
remaining = (opal_paths - ENTRY_FILES).sort_by { |p| [p.count("/"), p] }
ordered   = ENTRY_FILES + remaining

out = []
out << "# frozen_string_literal: true"
out << ""
out << "# DO NOT EDIT — regenerate with:"
out << "#   ruby lib/compat/opal/generate_boot.rb"
out << "#"
out << "# Opal does not support Ruby autoload (it is a no-op at parse time)."
out << "# This file explicitly requires every autoload target in lib/lutaml/**"
out << "# so that nested constants resolve at runtime under Opal."
out << "#"
out << "# Native-only paths excluded under Opal:"
out << "#   - nokogiri/ox/rexml adapters (C extensions unavailable)"
out << "#   - XSD / RELAX NG schema generators (require Nokogiri)"
out << "#   - lutaml/model/cli (thor-based, runtime-irrelevant under Opal)"
out << "#"
out << "# Ordering: lutaml/model and lutaml/xml define the Lutaml::Model and"
out << "# Lutaml::Xml namespaces, so they load first. Remaining paths are"
out << "# ordered by depth (shallower first) so parent files declare their"
out << "# child namespaces before children load."
out << "#"
out << "# Loaded by the Opal Rakefile before spec_helper."
out << ""
ordered.each { |p| out << %(require "#{p}") }
out << ""

# OPAL_BOOT_OUTPUT lets the in-sync guard spec regenerate to a temp path
# without clobbering the committed manifest; unset, it writes canonically.
target = ENV.fetch("OPAL_BOOT_OUTPUT") do
  File.expand_path("lutaml_model_boot.rb", __dir__)
end
File.write(target, out.join("\n"))
warn "Generated #{ordered.size} requires (excluded #{native_only.size} native-only paths) -> #{target}"
