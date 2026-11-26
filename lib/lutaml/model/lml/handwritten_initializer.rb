# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      # The integration point of a materialized class whose bundle model
      # carries `custom_initialize: true` (lutaml-model#1033): the source
      # model has hand-written application construction the document does
      # not declare. No body is translated or run.
      #
      # Declared DATA construction is a different thing and is unchanged:
      # `Klass.new(attributes)` and every from_* deserializer still build and
      # validate the declared members. `Klass.construct` is the application
      # entry; it needs an implementation supplied explicitly, by hand, and
      # raises a named custom_initialize error until then.
      module HandwrittenInitializer
        def lml_custom_initialize?
          true
        end

        # @return [#call, nil] the supplied implementation
        def lml_initializer
          @lml_initializer
        end

        # Supplies the hand-written implementation: a callable (or block)
        # receiving (klass, *args, **kwargs) and returning a klass instance.
        # @return [self]
        def implement_initializer(callable = nil, &block)
          implementation = callable || block
          unless implementation.respond_to?(:call)
            raise ArgumentError, "implement_initializer needs a callable or a block"
          end

          @lml_initializer = implementation
          self
        end

        # Application construction through the implementation. The result
        # must be an instance of this class and passes the declared data
        # validation.
        # @raise [RejectedError] :custom_initialize when no implementation
        #   was supplied or it returned something else
        def construct(*args, **kwargs)
          implementation = lml_initializer
          if implementation.nil?
            raise RejectedError.new(:custom_initialize, self,
                                    "the hand-written initializer is not implemented; " \
                                    "supply it with implement_initializer")
          end

          instance = implementation.call(self, *args, **kwargs)
          unless instance.is_a?(self)
            raise RejectedError.new(:custom_initialize, self,
                                    "the hand-written initializer returned #{instance.class}, not a #{self}")
          end

          instance.validate!
          instance
        end
      end
    end
  end
end
