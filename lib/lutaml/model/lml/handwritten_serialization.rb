# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      # The integration point of a materialized class whose key-value rules
      # carry `custom: {to:, from:}` hook names (lutaml-model#1033). The
      # document names the hooks; it never carries their bodies, and no
      # source method is called, translated or looked up.
      #
      # Each named hook becomes a real method on the class (the shape
      # `map key, with: {to:, from:}` calls) that fails with the named
      # `custom_serialization` error until a hand-written implementation is
      # installed with {#implement_serialization}. A missing `from` hook fails
      # only when a read reaches that key; a missing `to` hook only when a
      # write does. Declared-data construction and every ordinary rule run no
      # hook at all.
      #
      # Signatures (the source methods' own): a write hook is called
      # `(model, document_object)`, a read hook `(model, value)`.
      module HandwrittenSerialization
        # Ruby's `with:` needs both directions; a rule that names one gets an
        # internal stub for the other, named with this reserved prefix. The
        # exporter drops such names, so the document stays one-directional.
        ABSENT_PREFIX = "__lml_absent_"

        def self.absent_name(direction, other_name)
          "#{ABSENT_PREFIX}#{direction}_#{other_name}"
        end

        # @return [Hash{String=>Symbol}] hook name => :to (write) or :from (read)
        def lml_serialization_hooks
          @lml_serialization_hooks ||= {}
        end

        # Declares the hooks and defines their failing-by-default methods.
        def lml_declare_serialization_hooks(table)
          table.each do |name, direction|
            hook = name.to_s
            lml_serialization_hooks[hook] = direction
            define_method(hook) do |model, payload|
              self.class.lml_run_serialization_hook(hook, model, payload)
            end
          end
          self
        end

        # Installs hand-written implementations: `implement_serialization(name) { |model, payload| ... }`,
        # `implement_serialization(name, callable)` or `implement_serialization(name => callable, ...)`.
        # @return [self]
        # @raise [RejectedError] :custom_serialization for a name the model did not declare
        def implement_serialization(name_or_table, callable = nil, &block)
          table = name_or_table.is_a?(::Hash) ? name_or_table : { name_or_table => callable || block }
          table.each do |name, implementation|
            lml_check_hook!(name.to_s)
            unless implementation.respond_to?(:call)
              raise ArgumentError, "implement_serialization needs a callable or a block for #{name}"
            end

            lml_serialization_implementations[name.to_s] = implementation
          end
          self
        end

        # @return [#call, nil] the installed implementation for a hook name
        def lml_serialization_implementation(name)
          lml_serialization_implementations[name.to_s] ||
            (superclass.respond_to?(:lml_serialization_implementation) ? superclass.lml_serialization_implementation(name) : nil)
        end

        def lml_run_serialization_hook(name, model, payload)
          if name.start_with?(ABSENT_PREFIX)
            direction = lml_serialization_hooks[name] == :from ? "read" : "write"
            raise RejectedError.new(:custom_serialization, self,
                                    "the rule declares no #{direction} hook, so it cannot be #{direction == 'read' ? 'read' : 'written'}")
          end

          implementation = lml_serialization_implementation(name)
          if implementation.nil?
            direction = lml_serialization_hooks[name] == :from ? "read" : "write"
            raise RejectedError.new(:custom_serialization, self,
                                    "the hand-written #{direction} hook #{name} is not implemented; " \
                                    "install it with implement_serialization")
          end

          implementation.call(model, payload)
        end

        private

        def lml_serialization_implementations
          @lml_serialization_implementations ||= {}
        end

        def lml_check_hook!(name)
          return if lml_serialization_hooks.key?(name) && !name.start_with?(ABSENT_PREFIX)

          raise RejectedError.new(:custom_serialization, self, "#{name} is not a serialization hook of this model")
        end
      end
    end
  end
end
