# frozen_string_literal: true

# Opal shim: moxml 0.6's NativeAttachment::Native registers GC
# finalizers through ObjectSpace; JS has no finalization hook, and the
# Opal runtime does not carry an ObjectSpace at all (the constant is
# simply absent, so the call site NameErrors). A stubbed ObjectSpace
# degrades finalizer cleanup — attachments live for the process
# lifetime, which on the single-threaded JS runtime is the page's
# lifetime anyway. Existing runtimes that do define ObjectSpace are
# left untouched.
unless defined?(ObjectSpace)
  module ObjectSpace
    class << self
      def define_finalizer(_obj, _proc = nil)
        nil
      end

      def undefine_finalizer(_obj)
        nil
      end
    end
  end
end
