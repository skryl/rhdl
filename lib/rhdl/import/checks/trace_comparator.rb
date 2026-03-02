# frozen_string_literal: true

module RHDL
  module Import
    module Checks
      class TraceComparator
        class << self
          def compare(expected:, actual:, keys: nil)
            new.compare(expected: expected, actual: actual, keys: keys)
          end
        end

        def compare(expected:, actual:, keys: nil)
          selected_keys = normalize_keys(keys)
          expected_events = normalize_events(expected, keys: selected_keys)
          actual_events = normalize_events(actual, keys: selected_keys)
          event_count = [expected_events.length, actual_events.length].max
          mismatches = []
          pass_count = 0

          event_count.times do |index|
            expected_event = expected_events[index]
            actual_event = actual_events[index]

            if canonicalize(expected_event) == canonicalize(actual_event)
              pass_count += 1
            else
              mismatches << {
                index: index,
                expected: expected_event,
                actual: actual_event
              }
            end
          end

          {
            passed: mismatches.empty?,
            summary: {
              events_compared: event_count,
              pass_count: pass_count,
              fail_count: mismatches.length,
              keys: selected_keys.empty? ? nil : selected_keys,
              first_mismatch: mismatches.first
            },
            mismatches: mismatches
          }
        end

        private

        def normalize_keys(keys)
          Array(keys).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
        end

        def normalize_events(events, keys:)
          Array(events).map { |event| normalize_event(event, keys: keys) }
        end

        def normalize_event(event, keys:)
          case event
          when Hash
            filtered = if keys.empty?
              event
            else
              event.each_with_object({}) do |(key, value), memo|
                key_name = key.to_s
                memo[key_name] = value if keys.include?(key_name)
              end
            end

            filtered.each_with_object({}) do |(key, value), memo|
              memo[key.to_s] = normalize_event(value, keys: [])
            end
          when Array
            event.map { |entry| normalize_event(entry, keys: []) }
          else
            event
          end
        end

        def canonicalize(value)
          case value
          when Hash
            value.keys.sort.each_with_object({}) do |key, memo|
              memo[key] = canonicalize(value[key])
            end
          when Array
            value.map { |entry| canonicalize(entry) }
          else
            value
          end
        end
      end
    end
  end
end
