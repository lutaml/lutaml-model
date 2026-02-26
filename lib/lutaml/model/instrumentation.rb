# frozen_string_literal: true

module Lutaml
  module Model
    # Instrumentation module for performance monitoring and profiling
    #
    # This module provides hooks for tracking serialization performance,
    # memory usage, and operation timing. It can be enabled/disabled globally
    # or per-operation.
    #
    # @example Enable instrumentation globally
    #   Lutaml::Model::Instrumentation.enabled = true
    #
    # @example Subscribe to events
    #   Lutaml::Model::Instrumentation.subscribe(:serialization) do |event|
    #     puts "#{event[:name]} took #{event[:duration]}ms"
    #   end
    #
    # @example Instrument a block
    #   Lutaml::Model::Instrumentation.instrument(:parse, model: MyClass) do
    #     MyClass.from_xml(xml_string)
    #   end
    #
    module Instrumentation
      class << self
        attr_accessor :enabled
        attr_reader :subscribers, :events

        # Enable or disable instrumentation
        #
        # @param value [Boolean] true to enable, false to disable
        # @return [Boolean] the current enabled state
        def enabled=(value)
          @enabled = value
          @subscribers ||= {} if value
        end

        # Check if instrumentation is enabled
        #
        # @return [Boolean]
        def enabled?
          @enabled == true
        end

        # Subscribe to instrumentation events
        #
        # @param event_name [Symbol, Array<Symbol>] the event name(s) to subscribe to
        # @yield [Hash] the event payload
        # @return [Proc] the subscriber block
        def subscribe(*event_names, &block)
          return unless enabled?

          @subscribers ||= {}
          event_names.each do |name|
            @subscribers[name] ||= []
            @subscribers[name] << block
          end
          block
        end

        # Unsubscribe from instrumentation events
        #
        # @param event_name [Symbol] the event name
        # @param block [Proc] the subscriber block to remove
        # @return [void]
        def unsubscribe(event_name, block)
          return unless @subscribers

          @subscribers[event_name]&.delete(block)
        end

        # Clear all subscribers
        #
        # @return [void]
        def clear_subscribers
          @subscribers&.clear
        end

        # Instrument a block of code
        #
        # @param name [Symbol] the operation name
        # @param payload [Hash] additional payload data
        # @yield the block to instrument
        # @return [Object] the block's return value
        def instrument(name, payload = {})
          return yield unless enabled?

          start_time = monotonic_time
          start_mem = memory_usage if payload[:track_memory]

          result = yield

          end_time = monotonic_time
          end_mem = memory_usage if payload[:track_memory]

          event = {
            name: name,
            duration: ((end_time - start_time) * 1000).round(2), # ms
            payload: payload,
          }

          if payload[:track_memory]
            event[:memory_before] = start_mem
            event[:memory_after] = end_mem
            event[:memory_delta] = end_mem - start_mem if end_mem && start_mem
          end

          notify(name, event)

          result
        end

        # Get all recorded events (when recording is enabled)
        #
        # @return [Array<Hash>] the recorded events
        def recorded_events
          @recorded_events ||= []
        end

        # Start recording events
        #
        # @return [void]
        def start_recording
          @recording = true
          @events = []
        end

        # Stop recording events
        #
        # @return [Array<Hash>] the recorded events
        def stop_recording
          @recording = false
          @events || []
        end

        # Check if recording is active
        #
        # @return [Boolean]
        def recording?
          @recording == true
        end

        # Reset all instrumentation state
        #
        # @return [void]
        def reset!
          @enabled = false
          @subscribers = nil
          @events = nil
          @recording = false
        end

        private

        # Get monotonic time for accurate duration measurement
        #
        # @return [Float] the current monotonic time in seconds
        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        # Get current memory usage
        #
        # @return [Integer, nil] memory in bytes, or nil if not available
        def memory_usage
          return nil unless defined?(GC)

          GC.start if GC.respond_to?(:compact)
          `ps -o rss= -p #{Process.pid}`.to_i * 1024
        rescue StandardError
          nil
        end

        # Notify subscribers of an event
        #
        # @param name [Symbol] the event name
        # @param event [Hash] the event data
        # @return [void]
        def notify(name, event)
          return unless @subscribers

          # Notify specific event subscribers
          @subscribers[name]&.each do |subscriber|
            subscriber.call(event)
          rescue StandardError
            nil
          end

          # Notify global subscribers
          @subscribers[:all]&.each do |subscriber|
            subscriber.call(event)
          rescue StandardError
            nil
          end

          # Record event if recording is active
          recorded_events << event if recording?
        end
      end
    end

    # Performance statistics collector
    #
    # Collects and aggregates performance metrics across operations
    #
    # @example
    #   stats = Lutaml::Model::PerformanceStats.new
    #   stats.record(:parse, 12.5)
    #   stats.record(:parse, 15.2)
    #   stats.average(:parse) #=> 13.85
    #
    class PerformanceStats
      def initialize
        @metrics = Hash.new { |h, k| h[k] = [] }
      end

      # Record a metric value
      #
      # @param name [Symbol] the metric name
      # @param value [Numeric] the value to record
      # @return [void]
      def record(name, value)
        @metrics[name] << value
      end

      # Get all recorded values for a metric
      #
      # @param name [Symbol] the metric name
      # @return [Array<Numeric>]
      def values(name)
        @metrics[name].dup
      end

      # Calculate average for a metric
      #
      # @param name [Symbol] the metric name
      # @return [Float, nil]
      def average(name)
        vals = @metrics[name]
        return nil if vals.empty?

        vals.sum / vals.size.to_f
      end

      # Get minimum value for a metric
      #
      # @param name [Symbol] the metric name
      # @return [Numeric, nil]
      def min(name)
        @metrics[name].min
      end

      # Get maximum value for a metric
      #
      # @param name [Symbol] the metric name
      # @return [Numeric, nil]
      def max(name)
        @metrics[name].max
      end

      # Get count of recordings for a metric
      #
      # @param name [Symbol] the metric name
      # @return [Integer]
      def count(name)
        @metrics[name].size
      end

      # Get summary statistics for a metric
      #
      # @param name [Symbol] the metric name
      # @return [Hash]
      def summary(name)
        vals = @metrics[name]
        return {} if vals.empty?

        {
          count: vals.size,
          min: vals.min,
          max: vals.max,
          average: (vals.sum / vals.size.to_f).round(2),
          total: vals.sum.round(2),
        }
      end

      # Get all metric names
      #
      # @return [Array<Symbol>]
      def metric_names
        @metrics.keys
      end

      # Clear all recorded metrics
      #
      # @return [void]
      def clear
        @metrics.clear
      end
    end
  end
end
