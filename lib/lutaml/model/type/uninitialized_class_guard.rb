# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # Module that handles UninitializedClass sentinel value.
      #
      # This module should be prepended to Type::Value so that ALL type
      # subclasses automatically handle UninitializedClass without needing
      # to call super or add explicit checks.
      #
      # This ensures custom types that override cast() completely still
      # receive the UninitializedClass check automatically.
      module UninitializedClassGuard
        # Intercept cast to handle UninitializedClass before any
        # subclass-specific logic runs.
        #
        # The prepend ensures this method runs BEFORE the subclass's
        # cast implementation, even if the subclass doesn't call super.
        def cast(value, *args, **kwargs, &)
          # Return UninitializedClass unchanged - don't transform it
          return value if Utils.uninitialized?(value)

          super
        end

        # Also guard serialize for consistency
        def serialize(value)
          return value if Utils.uninitialized?(value)

          super
        end
      end
    end
  end
end
