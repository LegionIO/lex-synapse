# frozen_string_literal: true

require 'legion/settings'
require 'legion/settings/helper'

module Legion
  module Extensions
    module Synapse
      module Settings
        extend Legion::Settings::Helper

        PROPOSALS = {
          enabled:                 true,
          reactive:                true,
          proactive:               true,
          proactive_interval:      300,
          max_per_run:             3,
          llm_engine_options:      { temperature: 0.3, max_tokens: 1024 },
          success_rate_threshold:  0.8,
          payload_drift_threshold: 0.2,
          dedup_window_hours:      24
        }.freeze

        CHALLENGE = {
          enabled:                         true,
          impact_threshold:                0.3,
          auto_accept_threshold:           0.85,
          auto_reject_threshold:           0.15,
          llm_engine_options:              { temperature: 0.2, max_tokens: 512 },
          outcome_observation_window:      50,
          max_per_cycle:                   5,
          review_max_attempts:             3,
          review_retry_seconds:            300,
          review_max_retry_seconds:        3600,
          challenger_starting_confidence:  0.5,
          challenger_correct_adjustment:   0.05,
          challenger_incorrect_adjustment: -0.08
        }.freeze

        def self.segments = [:synapse]

        def self.section(name:, **)
          defaults = Legion::Extensions::Synapse.default_settings.fetch(name)
          defaults.merge(settings.fetch(name, {}))
        end
      end

      def self.default_settings
        { proposals: Settings::PROPOSALS.dup, challenge: Settings::CHALLENGE.dup }
      end
    end
  end
end
