# frozen_string_literal: true

require "rubygems/version"

module Lutaml
  module Lml
    # RS 3001 §Validation rules evaluated over a parsed document:
    # class constraints (unique names, unique attribute names), attribute
    # constraints (mandatory cardinality-1 attributes populated, values
    # matching declared types) and reference validity (ref: paths resolve
    # to instances and are acyclic).
    class Validator
      Violation = Struct.new(:rule, :message, :position, keyword_init: true)

      RULE_CODES = {
        'unique_names' => 'validation/LML-V01',
        'unique_attribute_names' => 'validation/LML-V02',
        'mandatory_attributes' => 'validation/LML-V03',
        'type_conformity' => 'validation/LML-V04',
        'values_set_membership' => 'validation/LML-V05',
        'unknown_attributes' => 'validation/LML-V06',
        'reference_validity' => 'validation/LML-V07',
        'reference_circularity' => 'validation/LML-V08',
        'pattern_conformity' => 'validation/LML-V09',
        'pattern_compiles' => 'validation/LML-V10',
      }.freeze

      PRIMITIVE_CONFORMITY = {
        'Integer' => /\A-?\d+\z/,
        'Number' => /\A-?\d+\z/,
        'Float' => /\A-?\d+\.\d+\z/,
        'Boolean' => /\A(true|false)\z/,
        'Null' => /\Anull\z/,
      }.freeze

      COLLECTION_KEYS = %i[properties attributes instances].freeze

      def self.violations(document)
        new(document).violations
      end

      # The structured form of the same rules: one Diagnostic per
      # violation, with its code and the source position of the
      # offending member when the parser retained one.
      def self.diagnostics(document)
        new(document).diagnostics
      end

      def initialize(document)
        @document = document
      end

      def diagnostics
        version_diagnostics + violations.map do |violation|
          Diagnostic.build(
            RULE_CODES.fetch(violation.rule),
            message: violation.message,
            file: @document.source_path,
            line: violation.position&.line,
            column: violation.position&.column,
            length: violation.position&.length,
          )
        end
      end

      # Version negotiation: a document may declare the language version
      # it speaks with an `lml "x.y"` prologue. A version newer than this
      # build is a warning, not an error (forward compatibility).
      def version_diagnostics
        declared = @document.lml_version.to_s
        return [] if declared.empty?
        return [] unless newer_language_version?(declared)

        position = @document.source_position
        [Diagnostic.build(
          'contract/LML-C06',
          message: "document declares LML #{declared}; this build supports #{Grammar.version}",
          file: @document.source_path,
          line: position&.line,
          column: position&.column,
          length: position&.length,
        )]
      end

      def newer_language_version?(declared)
        Gem::Version.new(declared) > Gem::Version.new(Grammar.version)
      rescue ArgumentError
        false
      end

      def violations
        unique_name_violations +
          unique_attribute_violations +
          instance_violations +
          circular_reference_violations
      end

      # RS 3001 scopes definitions to packages: uniqueness is per scope
      # (the document root and each package, recursively), not global.
      def definition_scopes
        scopes = [[nil, document_definitions]]
        Array(@document.packages).each { |pkg| collect_package_scopes(pkg, scopes) }
        scopes
      end

      def document_definitions
        [
          *Array(@document.classes),
          *Array(@document.enums),
          *Array(@document.data_types),
        ]
      end

      def collect_package_scopes(pkg, scopes, parent = nil)
        path = parent ? "#{parent}.#{pkg.name}" : pkg.name.to_s
        scopes << [path, [*Array(pkg.classes), *Array(pkg.enums), *Array(pkg.data_types)]]
        Array(pkg.packages).each { |nested| collect_package_scopes(nested, scopes, path) }
      end

      private

      def all_definitions
        @all_definitions ||= begin
          pairs = Array(@document.classes).map { |c| [c.name.to_s, c] } +
                  Array(@document.enums).map { |e| [e.name.to_s, e] } +
                  Array(@document.data_types).map { |d| [d.name.to_s, d] }
          Array(@document.packages).each { |pkg| collect_package_definitions(pkg, pairs) }
          pairs
        end
      end

      def collect_package_definitions(pkg, pairs)
        Array(pkg.classes).each { |c| pairs << [c.name.to_s, c] }
        Array(pkg.enums).each { |e| pairs << [e.name.to_s, e] }
        Array(pkg.data_types).each { |d| pairs << [d.name.to_s, d] }
        Array(pkg.packages).each { |nested| collect_package_definitions(nested, pairs) }
      end

      def type_definitions
        @type_definitions ||= all_definitions.to_h
      end

      def unique_name_violations
        definition_scopes.flat_map do |scope, definitions|
          scope_label = scope ? "package '#{scope}'" : 'the document root'
          definitions.map { |d| d.name.to_s }
                     .tally
                     .filter_map do |name, count|
            next if count == 1

            Violation.new(
              rule: 'unique_names',
              message: "'#{name}' is defined #{count} times in #{scope_label}",
              position: definitions.find { |definition| definition.name.to_s == name }&.source_position,
            )
          end
        end
      end

      def unique_attribute_violations
        type_definitions.filter_map do |name, definition|
          dupes = attribute_names(definition)
                  .tally.select { |_attr, count| count > 1 }.keys
          next if dupes.empty?

          Violation.new(
            rule: 'unique_attribute_names',
            message: "#{name}: duplicate attribute(s) #{dupes.inspect}",
            position: definition.source_position,
          )
        end
      end

      def attribute_names(definition)
        Array(definition.attributes).map(&:name).map(&:to_s)
      end

      def entry_position(instance, name)
        entry = Array(instance.attributes).find { |attribute| attribute.name.to_s == name }
        entry&.source_position || instance.source_position
      end

      # RS 3001 par. Attribute: a `pattern` declaration constrains
      # string values; a pattern that does not compile is itself a
      # definition error.
      def pattern_violations(instance)
        definition = type_definitions[definition_type(instance)]
        return [] unless definition.is_a?(UmlClass) || definition.is_a?(DataType)

        instance_attribute_pairs(instance).filter_map do |name, value|
          attr = Array(definition.attributes).find { |a| a.name.to_s == name }
          next unless attr&.pattern

          regexp = compile_pattern(attr.pattern)
          next invalid_pattern_violation(definition_type(instance), name, attr) unless regexp

          literal = value.respond_to?(:value) ? value.value : value
          next unless literal.is_a?(String)
          next if regexp.match?(literal)

          Violation.new(
            rule: 'pattern_conformity',
            message: "instance '#{instance_name(instance)}': attribute '#{name}' " \
                     "does not match #{attr.pattern.inspect}, got #{literal.inspect}",
            position: entry_position(instance, name),
          )
        end
      end

      def compile_pattern(pattern)
        Regexp.new(pattern)
      rescue RegexpError
        nil
      end

      def invalid_pattern_violation(type, name, attr)
        Violation.new(
          rule: 'pattern_compiles',
          message: "#{type}: attribute '#{name}' has an invalid pattern #{attr.pattern.inspect}",
          position: attr.source_position,
        )
      end

      def instance_violations
        instances.flat_map do |instance|
          mandatory_violations(instance) +
            type_conformity_violations(instance) +
            values_set_violations(instance) +
            pattern_violations(instance) +
            unknown_attribute_violations(instance) +
            reference_violations(instance)
        end.compact
      end

      # RS 3001 par. Attribute: a `values` declaration restricts an
      # attribute to its declared set.
      def values_set_violations(instance)
        definition = type_definitions[definition_type(instance)]
        return [] unless definition.is_a?(UmlClass) || definition.is_a?(DataType)

        instance_attribute_pairs(instance).filter_map do |name, value|
          attr = Array(definition.attributes).find { |a| a.name.to_s == name }
          next unless attr && !attr.value_set.empty?

          literal = value.respond_to?(:value) ? value.value : value
          next if attr.value_set.map(&:to_s).include?(literal.to_s)

          Violation.new(
            rule: 'values_set_membership',
            message: "instance '#{instance_name(instance)}': attribute '#{name}' " \
                     "must be one of #{attr.value_set.inspect}, got #{literal.to_s.inspect}",
            position: entry_position(instance, name),
          )
        end
      end

      def unknown_attribute_violations(instance)
        definition = type_definitions[definition_type(instance)]
        return [] unless definition.is_a?(UmlClass) || definition.is_a?(DataType)

        declared = attribute_names(definition)
        instance_attribute_pairs(instance)
          .reject { |pair| declared.include?(pair[0]) }
          .map do |name, _value|
            Violation.new(
              rule: 'unknown_attributes',
              message: "instance '#{instance_name(instance)}' (#{definition_type(instance)}): " \
                       "unknown attribute '#{name}'",
              position: entry_position(instance, name),
            )
          end
      end

      def instances
        Array(@document.instances&.instances)
      end

      def mandatory_violations(instance)
        definition = type_definitions[definition_type(instance)]
        return [] unless definition.is_a?(UmlClass) || definition.is_a?(DataType)

        definition.attributes.filter_map do |attr|
          next unless mandatory?(attr)
          next if populated?(instance, attr.name.to_s)

          Violation.new(
            rule: 'mandatory_attributes',
            message: "instance '#{instance_name(instance)}' (#{definition_type(instance)}): " \
                     "mandatory attribute '#{attr.name}' is not populated",
            position: instance.source_position,
          )
        end
      end

      def mandatory?(attr)
        attr.cardinality && attr.cardinality.min == '1'
      end

      def type_conformity_violations(instance)
        definition = type_definitions[definition_type(instance)]
        return [] unless definition.respond_to?(:attributes)

        instance_attribute_pairs(instance).filter_map do |name, value|
          attr = Array(definition.attributes).find { |a| a.name.to_s == name }
          next unless attr

          conformity_violation(instance, name, attr, value)
        end
      end

      def conformity_violation(instance, name, attr, value)
        pattern = PRIMITIVE_CONFORMITY[attr.type.to_s]
        return unless pattern
        return if pattern.match?(value.to_s)

        Violation.new(
          rule: 'type_conformity',
          message: "instance '#{instance_name(instance)}': attribute '#{name}' " \
                   "expects #{attr.type}, got #{value.to_s.inspect}",
          position: entry_position(instance, name),
        )
      end

      def reference_violations(instance)
        reference_values(instance).filter_map do |name, path|
          segments = path.to_s.split('.')
          unless resolvable_reference?(segments)
            next Violation.new(
              rule: 'reference_validity',
              message: "instance '#{instance_name(instance)}': attribute '#{name}' " \
                       "references unknown path '#{path}'",
              position: entry_position(instance, name),
            )
          end

          attribute_violation(instance, name, path, segments.first)
        end
      end

      # RS 3001 reference paths: `instance` / `instance.attribute` /
      # `collection.instance`.
      def resolvable_reference?(segments)
        case segments.length
        when 1 then instance_names.include?(segments.first)
        when 2 then instance_names.include?(segments.first) ||
          collection_names.include?(segments.first)
        else false
        end
      end

      def collection_names
        @collection_names ||= [@document.instances&.name].compact
      end

      def attribute_violation(instance, name, path, target)
        segment = path.to_s.split('.')[1]
        target_instance = instances.find { |i| instance_name(i) == target }
        return if segment.nil? || target_instance.nil? ||
                  instance_attribute(target_instance, segment)

        Violation.new(
          rule: 'reference_validity',
          message: "instance '#{instance_name(instance)}': reference '#{path}' " \
                   "does not resolve (no attribute '#{segment}' on '#{target}')",
          position: entry_position(instance, name),
        )
      end

      def instance_attribute_pairs(instance)
        pairs = []
        instance.each_attribute do |name, value, instances|
          pairs << [name.to_s, value_for(value, instances)]
        end
        pairs
      end

      def instance_attribute(instance, attr_name)
        instance_attribute_pairs(instance).find { |name, _value| name == attr_name }
      end

      def value_for(value, instances)
        literal = value.respond_to?(:value) ? value.value : value
        return instances.first if literal.is_a?(Hash) && literal[:instances]

        literal
      end

      def populated?(instance, attr_name)
        pair = instance_attribute(instance, attr_name)
        return false unless pair

        value = pair[1]
        literal = value.respond_to?(:value) ? value.value : value
        !literal.to_s.empty?
      end

      def reference_values(instance)
        Array(instance.attributes).filter_map do |attr|
          ref = attr.reference
          next unless ref

          [attr.name.to_s, ref.path]
        end
      end

      def instance_names
        @instance_names ||= instances.map { |i| instance_name(i) }
      end

      # RS 3001: circular references are invalid.
      def circular_reference_violations
        graph = instances.to_h do |instance|
          targets = reference_values(instance)
                    .map { |_name, path| path.to_s.split('.').first }
          [instance_name(instance), targets]
        end
        cycles = cycles_in(graph)
        cycles.map do |cycle|
          Violation.new(
            rule: 'reference_circularity',
            message: "circular reference: #{cycle.join(' -> ')}",
            position: instances.find { |instance| instance_name(instance) == cycle.first }&.source_position,
          )
        end
      end

      def cycles_in(graph)
        cycles = []
        graph.each_key do |start|
          path = walk_for_cycle(graph, start)
          cycles << path if path
        end
        cycles.uniq(&:sort)
      end

      def walk_for_cycle(graph, start)
        path = [start]
        node = start
        loop do
          nexts = graph[node] || []
          node = nexts.first
          return nil if node.nil? || node == '' || !graph.key?(node)
          return path + [node] if path.include?(node)

          path << node
        end
      end

      def instance_name(instance)
        instance.respond_to?(:name) ? instance.name.to_s : ''
      end

      def definition_type(instance)
        (instance.isa || instance.type).to_s
      end
    end
  end
end
