# frozen_string_literal: true

module Lutaml
  module Model
    # Invokes a user-defined custom (de)serialization method declared via
    # `with: { to:, from: }`, optionally forwarding a caller-supplied `state`
    # argument passed through `from_<format>(data, state:)` /
    # `to_<format>(state:)` (see lutaml-model issue #550).
    #
    # The `state` is appended as a trailing positional argument ONLY when the
    # custom method's signature can accept it. Existing custom methods (which
    # declare just the fixed structural parameters) are therefore invoked
    # exactly as before — full backward compatibility, decided by the method's
    # own parameter list rather than by whether `state` was supplied.
    module CustomMethodCaller
      # Parameter kinds that occupy a positional slot.
      POSITIONAL_PARAM_TYPES = %i[req opt].freeze

      module_function

      # Invoke `method_name` on `receiver` with `base_args`, appending `state`
      # as a trailing positional argument when the method can accept it.
      #
      # @param receiver [Object] object the custom method is invoked on
      # @param method_name [Symbol] the custom method name
      # @param base_args [Array] the fixed positional args (model, value/doc, ...)
      # @param state [Object, nil] caller-supplied state, forwarded when accepted
      # @return [Object] the custom method's return value
      def call(receiver, method_name, *base_args, state: nil)
        args = base_args
        if accepts_state?(receiver.method(method_name), base_args.length)
          args = base_args + [state]
        end

        receiver.public_send(method_name, *args)
      end

      # Whether `meth` can accept one more positional argument than `base_count`
      # (i.e. has room for a trailing `state`). A rest/splat parameter always
      # has room.
      #
      # @param meth [Method] the resolved custom method
      # @param base_count [Integer] number of fixed positional args
      # @return [Boolean]
      def accepts_state?(meth, base_count)
        max_positional = 0
        meth.parameters.each do |param|
          type = param.first
          return true if type == :rest

          max_positional += 1 if POSITIONAL_PARAM_TYPES.include?(type)
        end

        max_positional >= base_count + 1
      end
    end
  end
end
