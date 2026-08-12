# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles enum-related methods for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for adding enum getter/setter methods to model classes.
      module EnumHandling
        # Add enum methods to a model class
        #
        # @param klass [Class] The model class to add methods to
        # @param enum_name [Symbol] The name of the enum attribute
        # @param values [Array] The valid enum values
        # @param collection [Boolean] Whether the enum is a collection
        def add_enum_methods_to_model(klass, enum_name, values,
                                      collection: false)
          add_enum_getter_if_not_defined(klass, enum_name, collection)
          add_enum_setter_if_not_defined(klass, enum_name, values, collection)

          return unless values.all?(::String)

          values.each do |value|
            Utils.add_method_if_not_defined(klass, "#{value}?") do
              curr_value = public_send(:"#{enum_name}")

              if collection
                curr_value.include?(value)
              else
                curr_value == value
              end
            end

            # Record value name so regular attribute definitions can
            # override these shorthand methods when an attribute shares
            # the same name as an enum value (e.g. attribute :char with
            # align values including "char").
            enum_shorthand_names = klass.instance_variable_get(:@__enum_shorthand_names__) || Set.new
            enum_shorthand_names << value.to_s
            klass.instance_variable_set(:@__enum_shorthand_names__,
                                        enum_shorthand_names)

            Utils.add_method_if_not_defined(klass, value.to_s) do
              public_send(:"#{value}?")
            end

            Utils.add_method_if_not_defined(klass, "#{value}=") do |val|
              value_set_for(enum_name)
              enum_vals = public_send(:"#{enum_name}")

              # `+` and `-` rather than `<<` and `delete`. The reader hands
              # back the stored Array now, so mutating it here would reach an
              # Array a caller already holds — and would land even when the
              # store below raises on a frozen model.
              enum_vals = if !!val
                            if collection
                              enum_vals.include?(value) ? enum_vals : enum_vals + [value]
                            else
                              [value]
                            end
                          elsif collection
                            enum_vals - [value]
                          else
                            instance_variable_get(:"@#{enum_name}") - [value]
                          end

              instance_variable_set(:"@#{enum_name}", enum_vals)
            end

            Utils.add_method_if_not_defined(klass, "#{value}!") do
              public_send(:"#{value}=", true)
            end
          end
        end

        # Add enum getter method to model class
        #
        # @param klass [Class] The model class
        # @param enum_name [Symbol] The enum attribute name
        # @param collection [Boolean] Whether the enum is a collection
        def add_enum_getter_if_not_defined(klass, enum_name, collection)
          Utils.add_method_if_not_defined(klass, enum_name) do
            unless collection
              i = instance_variable_get(:"@#{enum_name}") || []
              next i.is_a?(::Array) ? i.first : i
            end

            current = materialize_lazy_collection(enum_name)

            # An enum collection reads as an Array even when nothing was
            # stored — the old `(ivar || []).uniq` never returned nil — so
            # unlike a regular collection this one materializes nil too, and
            # stores what it materialized so a push reaches the model.
            if current.nil?
              next [] if frozen?

              next instance_variable_set(:"@#{enum_name}", [])
            end

            # Not an Array, which means a model-defined writer stored
            # something else. Read it the way the old reader did and leave
            # what it stored alone — replacing it here would discard data.
            next current.uniq unless current.is_a?(::Array)

            # A frozen Array cannot be deduped in place, and handing back a
            # copy would lose the shared sentinel's identity, so only copy
            # when there is actually something to remove.
            if current.frozen?
              deduped = current.uniq
              next deduped.size == current.size ? current : deduped
            end

            # Hand back the stored Array, not a copy. This used to be
            # `i.uniq`, a fresh Array on every read, so `model.roles << "b"`
            # pushed onto a throwaway and the value never reached the model —
            # no error, no warning, the item simply never showed up in the
            # document. It still has to read unique, which is what that `uniq`
            # guaranteed, so dedupe in place rather than into a copy.
            current.uniq!
            current
          end
        end

        # Add enum setter method to model class
        #
        # @param klass [Class] The model class
        # @param enum_name [Symbol] The enum attribute name
        # @param _values [Array] The valid enum values (unused)
        # @param collection [Boolean] Whether the enum is a collection
        def add_enum_setter_if_not_defined(klass, enum_name, _values,
                                           collection)
          Utils.add_method_if_not_defined(klass, "#{enum_name}=") do |value|
            value = [] if value.nil?
            value = [value] if !value.is_a?(Array)

            value_set_for(enum_name)

            if collection
              curr_value = public_send(:"#{enum_name}")

              # Build a new Array rather than appending into the stored one.
              # The reader hands back the real Array now, so `curr_value` may
              # be this model's own collection — or, when the model defines
              # its own reader, something shared between instances or not an
              # Array at all. Duplicates are the reader's job either way.
              instance_variable_set(:"@#{enum_name}", curr_value + value)
            else
              instance_variable_set(:"@#{enum_name}", value)
            end
          end
        end

        # Get all enum attributes for this model
        #
        # @return [Hash] Hash of enum attribute names to attributes
        def enums
          attributes.select { |_, attr| attr.enum? }
        end
      end
    end
  end
end
