# frozen_string_literal: true

require_relative "rejected_error"

module Lutaml
  module Model
    module Lml
      # Validates LML hashes against the agreed contract and returns a
      # deeply frozen neutral tree. Raises RejectedError (named code,
      # JSON-pointer location) on the first violation; never returns a
      # tree with a feature silently dropped.
      #
      #   DocumentValidator.validate!(hash, kind: :document | :bundle | :manifest)
      #
      # Schema-evolution policy: versions are exact. Each kind dispatches
      # on its version field through a closed table; an unlisted version
      # is `unsupported_version` and is never coerced, down-converted or
      # defaulted. Version 1 documents are accepted indefinitely and
      # unchanged (legacy tolerance: unknown keys are ignored, as the
      # v1 Document always did, so existing checksums hold). Version 2
      # is strict: an unknown key, kind, type, facet or format is a
      # refusal, so any new feature requires a new version (or an
      # explicit new capability) rather than being dropped by old readers.
      class DocumentValidator
        BUILTIN_TYPES = %w[
          string token uri email hostname ip boolean integer decimal float
          rational date time date_time time_without_date duration qname
          base64_binary hex_binary symbol hash
        ].freeze
        # IEEE-754 binary64 wire form: shortest round-trip decimal, one
        # canonical spelling (see float_wire).
        FLOAT_WIRE = /\A-?\d+\.\d+(?:e-?\d+)?\z/
        UNSUPPORTED_BUILTINS = %w[double].freeze
        FORMATS = %w[xml json yaml toml].freeze
        NAMESPACE_MODES = %w[inherit unqualified uri].freeze
        MANIFEST_TARGETS = %w[ruby ts rust wasm].freeze
        XML_RULE_KINDS = %w[attribute element content any_attribute sequence choice].freeze
        ANY_ATTRIBUTE_KEYS = %w[kind to].freeze
        REGISTER_PATTERN = /\A[A-Za-z0-9_.:-]+\z/
        SHA256_PATTERN = /\Asha256:[0-9a-f]{64}\z/
        ORDERED_CONTENT_MEMBER = "__lml_content"
        FLAG_KEYS = %w[required initialize_empty].freeze
        BOOLEANS = [true, false].freeze
        DOT_SEGMENTS = ["", ".", ".."].freeze
        MAX_SAFE_INTEGER = (2**53) - 1
        # Containers nest at most this deep (the json gem's own default
        # limit), so a hand-built Hash cannot overflow the Ruby stack.
        MAX_DEPTH = 100
        # Attribute names become instance variables and accessors:
        # identifiers only (no ?, ! or = suffix, no leading digit/capital).
        ATTRIBUTE_NAME = /\A[a-z_][a-zA-Z0-9_]*\z/
        # A model name is a Ruby constant path (the rule Materialization
        # applies to v2 names); v1 names reach Object.const_get on verify.
        MODEL_NAME = /\A[A-Z]\w*(::[A-Z]\w*)*\z/
        # Builtin types whose default must be a JSON integer / boolean /
        # string / object (mirrors the exporter's portable_scalar).
        INTEGER_DEFAULT_TYPES = %w[integer].freeze
        BOOLEAN_DEFAULT_TYPES = %w[boolean].freeze
        STRING_DEFAULT_TYPES = %w[string token uri email hostname ip decimal rational date time
                                  date_time time_without_date duration qname base64_binary
                                  hex_binary symbol].freeze
        # Attribute names a generated class cannot carry. MEASURED, not
        # guessed: every identifier-shaped public/protected instance method
        # of Object and Lutaml::Model::Serializable, plus the construction
        # hooks (93 candidates), was declared as `attribute :<name>,
        # :string` on a throwaway Serializable and kept here if it broke
        # new, new(<name>: "v"), or a json/xml/yaml round trip in either of
        # two runs: a bare script with default adapters (20 broke) and the
        # spec_helper adapter setup (24 broke); the union is pinned.
        # Overridable names such as display, hash or schema_location work
        # and stay allowed. The spec "re-derives the reserved attribute
        # names" repeats the spec_helper measurement, so a lutaml-model
        # change shows up.
        RESERVED_ATTRIBUTE_NAMES = %w[
          __id__ __send__ attribute_order class doctype element_order
          encoding extract_register_id import_declaration_plan initialize
          initialize_clone initialize_copy initialize_dup lutaml_register
          pending_plan_root_element prepare_instance_format_options
          public_send record_mutation to_format to_json to_xml to_yaml
          value_set_for xml_declaration xml_ns_prefixes
        ].freeze
        MAPPING_OBJECT_KEYS = %w[root_mappings child_mappings].freeze
        XML_PREFIX = /\A[A-Za-z_][A-Za-z0-9_.-]*\z/

        MODEL_KEYS = %w[lml model register attributes mappings ordered_content].freeze
        ATTRIBUTE_KEYS = %w[name type required collection default
                            initialize_empty values discriminator].freeze
        RULE_KEYS = %w[kind name key to namespace prefix cdata render
                       discriminator members min max child_mappings root_mappings polymorphic_map].freeze
        FORMAT_KEYS = %w[root namespace rules root_mappings child_mappings
                         ordered mixed_content sequence].freeze
        COMPOSITOR_KINDS = %w[sequence choice].freeze
        EXECUTABLE_RULE_KEYS = %w[with custom_methods delegate transform
                                  proc lambda method callback].freeze
        BUNDLE_KEYS = %w[lml_bundle roots models value_types capabilities provenance].freeze
        MANIFEST_KEYS = %w[manifest lml_checksum schema_version generator_version
                           target capabilities corpora files dependencies].freeze

        KINDS = %i[document bundle manifest].freeze

        def self.validate!(hash, kind:)
          raise ArgumentError, "unknown kind #{kind.inspect}" unless KINDS.include?(kind)

          new.validate!(hash, kind)
        end

        def validate!(hash, kind)
          tree = neutral(hash, "", legacy: legacy_document?(hash, kind), depth: 0)
          case kind
          when :document then document(tree)
          when :bundle then bundle(tree)
          else manifest(tree)
          end
          tree
        end

        # Canonical `float` wire string: Ruby's shortest round-trip digits
        # with the exponent normalised (no "+", no leading zeros), e.g.
        # 0.71 -> "0.71", 1e-5 -> "1.0e-5", 1e20 -> "1.0e20", -0.0 -> "-0.0".
        # Non-finite values have no wire form.
        def self.float_wire(value)
          float = Float(value)
          raise ArgumentError, "non-finite float" unless float.finite?

          float.to_s.sub(/e(-?)\+?0*(\d+)\z/) { "e#{Regexp.last_match(1)}#{Regexp.last_match(2)}" }
        end

        def self.canonical_float?(value)
          return false unless value.is_a?(::String) && FLOAT_WIRE.match?(value)

          float_wire(Float(value)) == value
        rescue ArgumentError
          false
        end

        private

        def fail!(reason, detail, location, **context)
          raise RejectedError.new(reason, nil, detail, location: location, **context)
        end

        def pointer(*parts)
          parts.map { |part| "/#{part.to_s.gsub('~', '~0').gsub('/', '~1')}" }.join
        end

        def legacy_document?(hash, kind)
          kind == :document && hash.is_a?(::Hash) && hash["lml"] == 1
        end

        # Deep-copy into a frozen neutral tree. v2 admits only JSON
        # scalars with bounded integers; legacy v1 keeps whatever the
        # exporter produced (floats in defaults) so identity is unchanged.
        def neutral(node, at, legacy:, depth:)
          if (node.is_a?(::Hash) || node.is_a?(::Array)) && depth >= MAX_DEPTH
            fail!(:invalid_document, "nesting deeper than #{MAX_DEPTH} levels", at)
          end
          case node
          when ::Hash
            node.each_with_object({}) do |(key, value), out|
              fail!(:invalid_document, "non-string key #{key.inspect}", at) unless key.is_a?(::String)
              out[key.dup.freeze] = neutral(value, "#{at}#{pointer(key)}", legacy: legacy, depth: depth + 1)
            end.freeze
          when ::Array
            node.each_with_index.map { |item, i| neutral(item, "#{at}/#{i}", legacy: legacy, depth: depth + 1) }.freeze
          when ::String
            unless node.valid_encoding? && (node.encoding == Encoding::UTF_8 || node.ascii_only?)
              fail!(:invalid_document, "string is not valid UTF-8", at)
            end
            node.dup.freeze
          when ::Integer
            if !legacy && node.abs > MAX_SAFE_INTEGER
              fail!(:invalid_document, "structural integer out of bounds", at)
            end
            node
          when true, false, nil then node
          when ::Float
            if legacy
              return node if node.finite?

              fail!(:invalid_document, "non-finite float has no wire form", at)
            end

            fail!(:invalid_document, "floats are not portable; use an exact string", at)
          else
            fail!(:invalid_document, "unsupported value #{node.class}", at)
          end
        end

        def expect_hash(node, at)
          fail!(:invalid_document, "expected an object", at) unless node.is_a?(::Hash)
        end

        def expect_array(node, at)
          fail!(:invalid_document, "expected an array", at) unless node.is_a?(::Array)
        end

        def expect_string(node, at)
          return if node.is_a?(::String) && !node.empty?

          fail!(:invalid_document, "expected a non-empty string", at)
        end

        def expect_bool(node, at)
          return if [true, false].include?(node)

          fail!(:invalid_document, "expected a boolean", at)
        end

        def require_keys(node, keys, at)
          keys.each do |key|
            fail!(:invalid_document, "missing #{key}", at + pointer(key)) unless node.key?(key)
          end
        end

        def only_keys(node, allowed, at, reason = :invalid_document)
          node.each_key do |key|
            next if allowed.include?(key)

            fail!(reason, "unknown key #{key}", at + pointer(key))
          end
        end

        def check_version(node, field, supported, at)
          version = node[field]
          fail!(:invalid_document, "missing #{field}", at + pointer(field)) unless node.key?(field)
          return if version.is_a?(::Integer) && supported.include?(version)

          fail!(:unsupported_version, "#{field} #{version.inspect} is not supported " \
                                      "(supported: #{supported.join(', ')})", at + pointer(field))
        end

        # -- documents -------------------------------------------------

        def document(node, at = "")
          expect_hash(node, at)
          check_version(node, "lml", [1, 2], at)
          node["lml"] == 1 ? document_v1(node, at) : model_v2(node, at)
        end

        def document_v1(node, at)
          expect_string(node["model"], at + pointer("model"))
          unless node["model"].match?(MODEL_NAME)
            fail!(:invalid_document, "model name #{node['model'].inspect} is not a Ruby constant path",
                  at + pointer("model"))
          end
          unless node["register"].nil? || node["register"].is_a?(::String)
            fail!(:invalid_document, "register must be a string", at + pointer("register"))
          end
          if node.key?("attributes")
            expect_array(node["attributes"], at + pointer("attributes"))
            node["attributes"].each_with_index do |attr, i|
              expect_hash(attr, "#{at}/attributes/#{i}")
            end
          end
          expect_hash(node["mappings"], at + pointer("mappings")) if node.key?("mappings")
        end

        def model_v2(node, at, expected_id: nil)
          reject_executable_flags(node, at)
          only_keys(node, MODEL_KEYS, at)
          require_keys(node, %w[lml model register attributes], at)
          expect_string(node["model"], at + pointer("model"))
          register = node["register"]
          unless register.is_a?(::String) && register.match?(REGISTER_PATTERN)
            fail!(:invalid_document, "register must match #{REGISTER_PATTERN.source}", at + pointer("register"))
          end
          id = "#{node['model']}@#{register}"
          if expected_id && expected_id != id
            fail!(:invalid_document, "key #{expected_id} does not match model ID #{id}", at, model_id: id)
          end
          attributes_v2(node["attributes"], at, id)
          mappings_v2(node["mappings"], at, id, node["attributes"]) if node.key?("mappings")
          ordered_content(node, at, id)
          id
        end

        def reject_executable_flags(node, at)
          { "custom_initialize" => :custom_initialize,
            "imperative_element_order" => :imperative_element_order }.each do |key, reason|
            next unless node.key?(key)

            fail!(reason, "#{key} models have no declarative equivalent", at + pointer(key),
                  model_id: node["model"] && "#{node['model']}@#{node['register']}")
          end
        end

        def attributes_v2(attributes, at, id)
          expect_array(attributes, at + pointer("attributes"))
          seen = {}
          attributes.each_with_index do |attr, i|
            loc = "#{at}/attributes/#{i}"
            expect_hash(attr, loc)
            reject_lambda_default(attr, loc, id)
            only_keys(attr, ATTRIBUTE_KEYS, loc)
            require_keys(attr, %w[name type], loc)
            expect_string(attr["name"], loc + pointer("name"))
            name = attr["name"]
            attribute_name(name, loc + pointer("name"), id)
            if name == ORDERED_CONTENT_MEMBER
              fail!(:reserved_member, "#{name} is reserved for ordered content", loc + pointer("name"),
                    model_id: id, attribute: name)
            end
            if seen[name]
              fail!(:duplicate_id, "attribute #{name} declared twice", loc + pointer("name"),
                    model_id: id, attribute: name)
            end
            seen[name] = true
            type(attr["type"], loc + pointer("type"), id, name)
            FLAG_KEYS.each do |flag|
              expect_bool(attr[flag], loc + pointer(flag)) if attr.key?(flag)
            end
            collection(attr["collection"], loc + pointer("collection")) if attr.key?("collection")
            if attr.key?("default")
              default(attr["default"], loc + pointer("default"), id, name)
              typed_default(attr, loc, id, name)
            end
            float_default(attr, loc, id, name)
            expect_array(attr["values"], loc + pointer("values")) if attr.key?("values")
            discriminator_shape(attr["discriminator"], loc + pointer("discriminator"), id) if attr.key?("discriminator")
          end
        end

        def attribute_name(name, at, id)
          unless name.match?(ATTRIBUTE_NAME)
            fail!(:invalid_document, "attribute name #{name.inspect} must match #{ATTRIBUTE_NAME.source}", at,
                  model_id: id, attribute: name)
          end
          return unless RESERVED_ATTRIBUTE_NAMES.include?(name)

          fail!(:reserved_member, "attribute name #{name} breaks Serializable (reserved attribute name)", at,
                model_id: id, attribute: name)
        end

        def reject_lambda_default(attr, loc, id)
          default = attr["default"]
          return unless default.is_a?(::Hash) && (default.key?("lambda") || default.key?("proc"))

          fail!(:lambda_default, "executable defaults are not portable", loc + pointer("default"),
                model_id: id, attribute: attr["name"])
        end

        def type(node, at, id, attribute)
          expect_hash(node, at)
          case node["kind"]
          when "builtin"
            only_keys(node, %w[kind name], at)
            name = node["name"]
            return if BUILTIN_TYPES.include?(name)

            reason = UNSUPPORTED_BUILTINS.include?(name) ? :unsupported_type : :unknown_type
            fail!(reason, "builtin type #{name.inspect}", at + pointer("name"), model_id: id, attribute: attribute)
          when "model", "value"
            only_keys(node, %w[kind id], at)
            expect_string(node["id"], at + pointer("id"))
          else
            fail!(:unknown_type, "type kind #{node['kind'].inspect}", at + pointer("kind"),
                  model_id: id, attribute: attribute)
          end
        end

        def collection(node, at)
          return if node == false

          expect_hash(node, at)
          only_keys(node, %w[min max class], at)
          require_keys(node, %w[min max], at)
          min = node["min"]
          max = node["max"]
          fail!(:invalid_document, "min must be a non-negative integer", at + pointer("min")) unless min.is_a?(::Integer) && min >= 0
          unless max.nil? || (max.is_a?(::Integer) && max >= min)
            fail!(:invalid_document, "max must be null or an integer >= min", at + pointer("max"))
          end
          expect_string(node["class"], at + pointer("class")) if node.key?("class")
        end

        def default(node, at, id, attribute)
          expect_hash(node, at)
          only_keys(node, %w[present value], at)
          expect_bool(node["present"], at + pointer("present"))
          if node["present"]
            unless node.key?("value")
              fail!(:invalid_document, "present default needs a value", at + pointer("value"),
                    model_id: id, attribute: attribute)
            end
          elsif node.key?("value")
            fail!(:invalid_document, "absent default carries no value", at + pointer("value"),
                  model_id: id, attribute: attribute)
          end
        end

        # A present default must be the JSON shape its builtin type
        # declares (an integer on a string attribute is refused, as Rust does).
        def typed_default(attr, loc, id, name)
          return unless attr.dig("default", "present") && attr.dig("type", "kind") == "builtin"

          kind = attr.dig("type", "name")
          return if kind == "float" # float_default owns the wire string rule

          value = attr["default"]["value"]
          items = attr["collection"] && value.is_a?(::Array) ? value : [value]
          return if items.all? { |item| default_shape?(kind, item) }

          fail!(:non_serializable_default, "default #{value.inspect} is not a #{kind}",
                loc + pointer("default", "value"), model_id: id, attribute: name)
        end

        def default_shape?(kind, item)
          return true if item.nil?

          if INTEGER_DEFAULT_TYPES.include?(kind) then item.is_a?(::Integer)
          elsif BOOLEAN_DEFAULT_TYPES.include?(kind) then BOOLEANS.include?(item)
          elsif STRING_DEFAULT_TYPES.include?(kind) then item.is_a?(::String)
          elsif kind == "hash" then item.is_a?(::Hash)
          else true
          end
        end

        def float_default(attr, loc, id, name)
          return unless attr.dig("type", "kind") == "builtin" && attr.dig("type", "name") == "float"
          return unless attr.dig("default", "present")

          value = attr["default"]["value"]
          return if self.class.canonical_float?(value)

          fail!(:invalid_document, "float default must be a canonical float string", loc + pointer("default", "value"),
                model_id: id, attribute: name)
        end

        def discriminator_shape(node, at, id)
          expect_hash(node, at)
          only_keys(node, %w[attribute cases], at)
          require_keys(node, %w[attribute cases], at)
          expect_string(node["attribute"], at + pointer("attribute"))
          expect_hash(node["cases"], at + pointer("cases"))
          fail!(:unknown_discriminator, "no cases", at + pointer("cases"), model_id: id) if node["cases"].empty?
          node["cases"].each do |wire, target|
            expect_string(target, "#{at}/cases#{pointer(wire)}")
          end
        end

        def mappings_v2(mappings, at, id, attributes = [])
          expect_hash(mappings, at + pointer("mappings"))
          mappings.each do |format, mapping|
            loc = "#{at}/mappings#{pointer(format)}"
            fail!(:unsupported_format, "format #{format}", loc, model_id: id, format: format) unless FORMATS.include?(format)
            expect_hash(mapping, loc)
            only_keys(mapping, FORMAT_KEYS, loc, :unsupported_mapping)
            namespace(mapping["namespace"], "#{loc}/namespace", id, format) if mapping.key?("namespace")
            mapping_root(mapping["root"], "#{loc}/root", id, format) if mapping.key?("root")
            MAPPING_OBJECT_KEYS.each do |key|
              expect_hash(mapping[key], "#{loc}/#{key}") if mapping.key?(key)
            end
            mapping_flags(mapping, loc, id, format)
            next unless mapping.key?("rules")

            expect_array(mapping["rules"], "#{loc}/rules")
            mapping["rules"].each_with_index { |rule, i| rule_v2(rule, "#{loc}/rules/#{i}", id, format) }
            any_attribute_rules(mapping["rules"], loc, id, format, attributes)
          end
        end

        # any_attribute (map_all_attributes): xml only, top-level only,
        # at most one per mapping, `to` a declared hash attribute.
        def any_attribute_rules(rules, loc, id, format, attributes)
          found = rules.each_index.select { |i| rules[i].is_a?(::Hash) && rules[i]["kind"] == "any_attribute" }
          return if found.empty?

          unless format == "xml"
            fail!(:unsupported_mapping, "any_attribute is xml only", "#{loc}/rules/#{found.first}", model_id: id,
                                                                                                    format: format)
          end
          if found.length > 1
            fail!(:unsupported_mapping, "at most one any_attribute rule per mapping", "#{loc}/rules/#{found[1]}",
                  model_id: id, format: format)
          end
          at = "#{loc}/rules/#{found.first}"
          rule = rules[found.first]
          only_keys(rule, ANY_ATTRIBUTE_KEYS, at, :unsupported_mapping)
          expect_string(rule["to"], at + pointer("to"))
          target = Array(attributes).find { |a| a.is_a?(::Hash) && a["name"] == rule["to"] }
          unless target
            fail!(:dangling_reference, "any_attribute `to` #{rule['to'].inspect} is not an attribute of the model",
                  at + pointer("to"), model_id: id, format: format)
          end
          return if target.dig("type", "kind") == "builtin" && target.dig("type", "name") == "hash" && !target["collection"]

          fail!(:unsupported_mapping, "any_attribute `to` #{rule['to'].inspect} must be a non-collection hash attribute",
                at + pointer("to"), model_id: id, format: format)
        end

        def mapping_root(node, at, id, format)
          expect_hash(node, at)
          expect_string(node["element"], at + pointer("element")) if node.key?("element")
          return unless node.key?("mixed") && !BOOLEANS.include?(node["mixed"])

          fail!(:unsupported_mapping, "root mixed must be true or false", at + pointer("mixed"),
                model_id: id, format: format)
        end

        # ordered / mixed_content are booleans; sequence is an array of
        # sequence compositors (xml only).
        def mapping_flags(mapping, loc, id, format)
          %w[ordered mixed_content].each do |flag|
            next unless mapping.key?(flag)

            next if BOOLEANS.include?(mapping[flag])

            fail!(:unsupported_mapping, "#{flag} must be true or false", "#{loc}/#{flag}",
                  model_id: id, format: format)
          end
          return unless mapping.key?("sequence")

          unless format == "xml"
            fail!(:unsupported_mapping, "sequence is xml only", "#{loc}/sequence", model_id: id, format: format)
          end
          expect_array(mapping["sequence"], "#{loc}/sequence")
          mapping["sequence"].each_with_index do |group, i|
            compositor_v2(group, "#{loc}/sequence/#{i}", id, format)
          end
        end

        def compositor_v2(node, at, id, format)
          rule_v2(node, at, id, format)
          unless COMPOSITOR_KINDS.include?(node["kind"])
            fail!(:unsupported_mapping, "expected a sequence or choice", at + pointer("kind"),
                  model_id: id, format: format)
          end
          expect_array(node["members"], "#{at}/members")
          node["members"].each_with_index do |member, i|
            loc = "#{at}/members/#{i}"
            expect_hash(member, loc)
            if member["kind"] == "any_attribute"
              fail!(:unsupported_mapping, "any_attribute is not allowed inside a compositor", loc + pointer("kind"),
                    model_id: id, format: format)
            end
            COMPOSITOR_KINDS.include?(member["kind"]) ? compositor_v2(member, loc, id, format) : rule_v2(member, loc, id, format)
          end
        end

        def rule_v2(rule, at, id, format)
          expect_hash(rule, at)
          rule.each_key do |key|
            next unless EXECUTABLE_RULE_KEYS.include?(key)

            fail!(:unsupported_mapping, "executable rule key #{key}", at + pointer(key),
                  model_id: id, format: format)
          end
          only_keys(rule, RULE_KEYS, at, :unsupported_mapping)
          if format == "xml" && rule.key?("kind") && !XML_RULE_KINDS.include?(rule["kind"])
            fail!(:unsupported_mapping, "rule kind #{rule['kind'].inspect}", at + pointer("kind"),
                  model_id: id, format: format)
          end
          namespace(rule["namespace"], "#{at}/namespace", id, format) if rule.key?("namespace")
          MAPPING_OBJECT_KEYS.each do |key|
            expect_hash(rule[key], "#{at}/#{key}") if rule.key?(key)
          end
          expect_bool(rule["cdata"], "#{at}/cdata") if rule.key?("cdata")
          if rule.key?("polymorphic_map")
            expect_hash(rule["polymorphic_map"], "#{at}/polymorphic_map")
            rule["polymorphic_map"].each { |k, v| expect_string(v, "#{at}/polymorphic_map#{pointer(k)}") }
          end
          expect_array(rule["name"], "#{at}/name") if rule.key?("name")
          expect_array(rule["key"], "#{at}/key") if rule.key?("key")
          render(rule["render"], "#{at}/render", id, format) if rule.key?("render")
          discriminator_shape(rule["discriminator"], "#{at}/discriminator", id) if rule.key?("discriminator")
        end

        def namespace(node, at, id, format)
          expect_hash(node, at)
          unless NAMESPACE_MODES.include?(node["mode"])
            fail!(:unsupported_mapping, "namespace mode #{node['mode'].inspect}", at + pointer("mode"),
                  model_id: id, format: format)
          end
          only_keys(node, %w[mode uri prefix], at, :unsupported_mapping)
          prefix(node["prefix"], at + pointer("prefix")) if node.key?("prefix")
          if node["mode"] == "uri"
            expect_string(node["uri"], at + pointer("uri"))
          elsif node.key?("uri") || node.key?("prefix")
            fail!(:unsupported_mapping, "uri/prefix only with mode uri", at, model_id: id, format: format)
          end
        end

        def prefix(node, at)
          return if node.is_a?(::String) && node.match?(XML_PREFIX)

          fail!(:invalid_document, "prefix must match #{XML_PREFIX.source}", at)
        end

        def render(node, at, id, format)
          expect_hash(node, at)
          only_keys(node, %w[nil empty default], at, :unsupported_mapping)
          node.each do |key, value|
            next if value.is_a?(::String) || BOOLEANS.include?(value)

            fail!(:unsupported_mapping, "render policy #{key}", at + pointer(key), model_id: id, format: format)
          end
        end

        def ordered_content(node, at, id)
          return unless node.key?("ordered_content")

          loc = at + pointer("ordered_content")
          content = node["ordered_content"]
          valid = content.is_a?(::Hash) && content.keys.sort == %w[member version] &&
            content["member"] == ORDERED_CONTENT_MEMBER && content["version"] == 1
          unless valid
            fail!(:invalid_ordered_content,
                  "expected {member: #{ORDERED_CONTENT_MEMBER}, version: 1}", loc, model_id: id)
          end
        end

        # -- bundles ---------------------------------------------------

        def bundle(node)
          expect_hash(node, "")
          check_version(node, "lml_bundle", [1], "")
          only_keys(node, BUNDLE_KEYS, "")
          require_keys(node, %w[roots models value_types capabilities], "")
          roots, models, values, caps = node.values_at("roots", "models", "value_types", "capabilities")
          expect_hash(models, "/models")
          expect_hash(values, "/value_types")
          sorted_unique_strings(roots, "/roots")
          sorted_unique_strings(caps, "/capabilities")
          expect_hash(node["provenance"], "/provenance") if node.key?("provenance")

          values.each do |vid, definition|
            value_type(vid, definition, "/value_types#{pointer(vid)}")
          end
          models.each do |mid, doc|
            loc = "/models#{pointer(mid)}"
            expect_hash(doc, loc)
            check_version(doc, "lml", [2], loc)
            model_v2(doc, loc, expected_id: mid)
            doc.fetch("mappings", {}).each_key do |format|
              next if caps.include?(format)

              fail!(:capability_missing, "format #{format} is not in capabilities",
                    "#{loc}/mappings#{pointer(format)}", model_id: mid, format: format)
            end
          end
          roots.each_with_index do |root, i|
            next if models.key?(root)

            fail!(:dangling_reference, "root #{root} is not a bundled model", "/roots/#{i}", model_id: root)
          end
          check_graph(models, values)
        end

        def sorted_unique_strings(node, at)
          expect_array(node, at)
          node.each_with_index { |item, i| expect_string(item, "#{at}/#{i}") }
          if node.uniq.length != node.length
            dup = node.find { |item| node.count(item) > 1 }
            fail!(:duplicate_id, "#{dup} listed twice", at)
          end
          fail!(:invalid_document, "must be sorted", at) unless node == node.sort
        end

        def value_type(vid, definition, at)
          expect_hash(definition, at)
          only_keys(definition, %w[base facets], at)
          require_keys(definition, %w[base facets], at)
          expect_hash(definition["facets"], "#{at}/facets")
          base = definition["base"]
          return if BUILTIN_TYPES.include?(base)

          reason = UNSUPPORTED_BUILTINS.include?(base) ? :unsupported_type : :unknown_type
          fail!(reason, "value type #{vid} base #{base.inspect}", "#{at}/base")
        end

        def check_graph(models, values)
          models.each do |mid, doc|
            doc["attributes"].each_with_index do |attr, i|
              loc = "/models#{pointer(mid)}/attributes/#{i}"
              ref = attr["type"]
              check_type_ref(ref, models, values, "#{loc}/type", mid)
              check_discriminator(attr["discriminator"], models, "#{loc}/discriminator", mid) if attr["discriminator"]
            end
            doc.fetch("mappings", {}).each do |format, mapping|
              (mapping["rules"] || []).each_with_index do |rule, i|
                next unless rule["discriminator"]

                check_discriminator(rule["discriminator"], models,
                                    "/models#{pointer(mid)}/mappings#{pointer(format)}/rules/#{i}/discriminator", mid)
              end
            end
          end
        end

        def check_type_ref(ref, models, values, at, mid)
          table = { "model" => models, "value" => values }[ref["kind"]]
          return if table.nil? || table.key?(ref["id"])

          fail!(:dangling_reference, "#{ref['kind']} #{ref['id']} is not in the bundle", "#{at}/id", model_id: mid)
        end

        def check_discriminator(disc, models, at, mid)
          disc["cases"].each do |wire, target|
            unless models.key?(target)
              fail!(:dangling_reference, "case #{wire} targets #{target}", "#{at}/cases#{pointer(wire)}", model_id: mid)
            end
            next if models[target]["attributes"].any? { |a| a["name"] == disc["attribute"] }

            fail!(:unknown_discriminator, "#{target} has no attribute #{disc['attribute']}",
                  "#{at}/attribute", model_id: mid)
          end
        end

        # -- manifests -------------------------------------------------

        def manifest(node)
          expect_hash(node, "")
          check_version(node, "manifest", [1], "")
          only_keys(node, MANIFEST_KEYS, "")
          require_keys(node, MANIFEST_KEYS, "")
          digest(node["lml_checksum"], "/lml_checksum")
          check_version(node, "schema_version", [2], "")
          expect_string(node["generator_version"], "/generator_version")
          unless MANIFEST_TARGETS.include?(node["target"])
            fail!(:invalid_document, "target #{node['target'].inspect}", "/target")
          end
          sorted_unique_strings(node["capabilities"], "/capabilities")
          expect_array(node["corpora"], "/corpora")
          node["corpora"].each_with_index { |c, i| corpus(c, "/corpora/#{i}") }
          pinned_list(node["files"], "/files", "path", relative: true)
          pinned_list(node["dependencies"], "/dependencies", "name", extra: "revision")
        end

        def digest(node, at)
          return if node.is_a?(::String) && node.match?(SHA256_PATTERN)

          fail!(:invalid_document, "expected sha256:<64 lowercase hex>", at)
        end

        def corpus(node, at)
          expect_hash(node, at)
          only_keys(node, %w[generation sha256], at)
          require_keys(node, %w[generation sha256], at)
          digest(node["sha256"], "#{at}/sha256")
        end

        def pinned_list(list, at, id_key, relative: false, extra: nil)
          expect_array(list, at)
          keys = [id_key, extra, "sha256"].compact
          ids = list.each_with_index.map do |entry, i|
            loc = "#{at}/#{i}"
            expect_hash(entry, loc)
            only_keys(entry, keys, loc)
            require_keys(entry, keys, loc)
            expect_string(entry[id_key], "#{loc}/#{id_key}")
            expect_string(entry[extra], "#{loc}/#{extra}") if extra
            digest(entry["sha256"], "#{loc}/sha256")
            safe_path(entry[id_key], "#{loc}/#{id_key}") if relative
            entry[id_key]
          end
          fail!(:duplicate_id, "duplicate #{id_key}", at) if ids.uniq.length != ids.length
          fail!(:invalid_document, "must be sorted by #{id_key}", at) unless ids == ids.sort
        end

        def safe_path(path, at)
          segments = path.split("/", -1)
          unsafe = path.start_with?("/") || path.include?("\\") || path.include?("\0") ||
            segments.any? { |s| DOT_SEGMENTS.include?(s) }
          return unless unsafe

          fail!(:invalid_document, "path must be relative without traversal", at)
        end
      end
    end
  end
end
