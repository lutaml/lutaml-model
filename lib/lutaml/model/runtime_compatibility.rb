# frozen_string_literal: true

module Lutaml
  module Model
    module RuntimeCompatibility
      def self.opal?
        return @opal if defined?(@opal)

        @opal = RUBY_ENGINE == "opal"
      end

      def self.windows?
        defined?(Gem) &&
          Gem.win_platform?
      end

      def self.native?
        !opal?
      end

      def self.autoload_native(namespace, constant_paths)
        return unless native?

        constant_paths.each do |constant_name, path|
          namespace.autoload(constant_name, path)
        end
      end

      def self.require_native(*paths)
        return unless native?

        paths.each { |path| require path }
      end

      def self.define_native_aliases(namespace, constant_targets)
        return unless native?

        constant_targets.each do |constant_name, target_name|
          namespace.const_set(constant_name, constantize(target_name))
        end
      end

      def self.safe_constantize(name)
        parts = constant_parts(name)
        return nil if parts.empty?
        return nil unless Object.const_defined?(parts.first)

        parts.inject(Object) do |mod, part|
          mod.const_get(part)
        end
      rescue NameError
        nil
      end

      def self.constantize(name)
        constant_parts(name).inject(Object) do |mod, part|
          mod.const_get(part, false)
        end
      end
      private_class_method :constantize

      def self.constant_parts(name)
        name.to_s.split("::").reject(&:empty?)
      end
      private_class_method :constant_parts
    end
  end
end

if Lutaml::Model::RuntimeCompatibility.opal?
  unless defined?(Mutex)
    class ::Mutex
      def synchronize
        yield
      end
    end
  end

  unless defined?(ConditionVariable)
    class ::ConditionVariable
      def wait(*); end

      def broadcast; end
    end
  end

  unless defined?(Thread)
    class ::Thread
      def self.current
        @current ||= {}
      end
    end
  end

  # Opal has no `weakref` stdlib. Store uses WeakRef to let go of
  # registered instances automatically once they go out of scope.
  # Under Opal (browser JS GC) we substitute a strong reference —
  # correct behavior, weaker memory profile, no API surface change.
  unless defined?(WeakRef)
    class ::WeakRef
      class RefError < ::StandardError; end

      def initialize(obj)
        @__target__ = obj
      end

      def __getobj__
        @__target__
      end

      def weakref_alive?
        true
      end

      # Minimal method_missing so the WeakRef quacks like its target
      # for the Store's index lookups.
      def method_missing(name, *, &)
        @__target__.public_send(name, *, &)
      end

      def respond_to_missing?(name, include_private = false)
        @__target__.respond_to?(name, include_private)
      end
    end
  end
end
