# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Helpers
        module Challenge
          VALID_VERDICTS = %w[support challenge abstain].freeze
          VALID_CHALLENGER_TYPES = %w[conflict llm].freeze
          VALID_OUTCOMES = %w[correct incorrect].freeze
          VALID_CHALLENGE_STATES = %w[challenging challenged].freeze

          IMPACT_WEIGHTS = {
            'llm_transform'      => 0.7,
            'transform_mutation' => 0.5,
            'attention_mutation' => 0.6,
            'route_change'       => 0.8
          }.freeze

          DEFAULT_SETTINGS = {
            enabled:                         true,
            impact_threshold:                0.3,
            auto_accept_threshold:           0.85,
            auto_reject_threshold:           0.15,
            llm_engine_options:              { temperature: 0.2, max_tokens: 512 },
            outcome_observation_window:      50,
            max_per_cycle:                   5,
            challenger_starting_confidence:  0.5,
            challenger_correct_adjustment:   0.05,
            challenger_incorrect_adjustment: -0.08
          }.freeze

          class << self
            def settings
              raw = Legion::Settings.dig('lex-synapse', 'challenge')
              return DEFAULT_SETTINGS.dup unless raw.is_a?(Hash)

              merged = DEFAULT_SETTINGS.dup
              raw.each { |k, v| merged[k.to_sym] = v unless v.nil? }
              merged
            end

            def enabled?
              settings[:enabled] == true
            end

            def above_impact_threshold?(impact_score)
              impact_score >= settings[:impact_threshold]
            end
          end
        end
      end
    end
  end
end
