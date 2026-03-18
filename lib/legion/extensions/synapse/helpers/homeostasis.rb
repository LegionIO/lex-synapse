# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Helpers
        module Homeostasis
          SPIKE_MULTIPLIER = 3.0
          SPIKE_DURATION_SECONDS = 60
          DROUGHT_MULTIPLIER = 10.0

          class << self
            def spike?(current_throughput, baseline_throughput, duration_seconds: 0)
              return false if baseline_throughput <= 0

              current_throughput > (baseline_throughput * SPIKE_MULTIPLIER) &&
                duration_seconds >= SPIKE_DURATION_SECONDS
            end

            def drought?(current_throughput, baseline_throughput, silent_seconds: 0)
              return false if baseline_throughput <= 0

              avg_interval = 60.0 / baseline_throughput
              current_throughput.zero? && silent_seconds >= (avg_interval * DROUGHT_MULTIPLIER)
            end

            def update_baseline(current_baseline, new_sample, alpha: 0.1)
              ((1 - alpha) * current_baseline) + (alpha * new_sample)
            end

            def should_dampen?(current_throughput, baseline_throughput, duration_seconds: 0)
              spike?(current_throughput, baseline_throughput, duration_seconds: duration_seconds)
            end

            def should_flag_for_review?(current_throughput, baseline_throughput, silent_seconds: 0)
              drought?(current_throughput, baseline_throughput, silent_seconds: silent_seconds)
            end
          end
        end
      end
    end
  end
end
