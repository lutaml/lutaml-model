# frozen_string_literal: true

module Lutaml
  module Model
    module Liquid
      # Module for Lutaml::Model objects that support bracket-based
      # lookup in Liquid templates (e.g., collections with index or key access).
      #
      # Include this module in any Serializable subclass that supports
      # +self[key]+ so that its auto-generated Liquid drop can delegate
      # +drop[key]+ through to the underlying object.
      #
      # Example:
      #   class Glossarist::Collections::LocalizationCollection
      #     include Lutaml::Model::Liquid::IndexedAccess
      #     # ...
      #   end
      #
      #   drop['eng']  #=> calls drop.liquid_method_missing('eng')
      #               #=> calls @object.liquid_fetch('eng')
      #               #=> calls @object['eng']
      #               #=> returns the localized concept drop
      module IndexedAccess
        # Called by the auto-generated Liquid drop via +liquid_method_missing+.
        # Delegates to +self[key]+ by default. Override in specific classes
        # for custom lookup behavior.
        def liquid_fetch(key)
          self[key]
        end
      end
    end
  end
end
