# frozen_string_literal: true

# Opal shim: the monitor stdlib (MonitorMixin) is not packaged for
# Opal, and moxml 0.6's NativeAttachment requires it at load time.
# The JS runtime is single-threaded, so the monitor contract reduces
# to pass-through: synchronize yields, lock/try_lock succeed, unlock
# is a no-op. Aliases cover the MonitorMixin spellings.
#
class Monitor # rubocop:disable Naming/PredicateMethod -- stdlib spellings
  def synchronize
    yield
  end

  def lock; end

  def try_lock
    true
  end

  def unlock; end

  def locked?
    false
  end

  alias mon_enter lock
  alias mon_exit unlock
  alias mon_synchronize synchronize
  alias mon_locked? locked?
  alias mon_try_lock try_lock
end
