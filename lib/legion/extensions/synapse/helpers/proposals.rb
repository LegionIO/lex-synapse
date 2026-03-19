# frozen_string_literal: true

module Legion
  module Extensions
    module Synapse
      module Helpers
        module Proposals
          VALID_PROPOSAL_TYPES = %w[llm_transform attention_mutation transform_mutation route_change].freeze
          VALID_TRIGGERS = %w[reactive proactive].freeze
          VALID_STATUSES = %w[pending approved rejected applied expired].freeze

          DEFAULT_SETTINGS = {
            enabled: true,
            reactive: true,
            proactive: true,
            proactive_interval: 300,
            max_per_run: 3,
            llm_engine_options: { temperature: 0.3, max_tokens: 1024 },
            success_rate_threshold: 0.8,
            payload_drift_threshold: 0.2,
            dedup_window_hours: 24
          }.freeze

          class << self
            def settings
              raw = Legion::Settings.dig('lex-synapse', 'proposals')
              return DEFAULT_SETTINGS.dup unless raw.is_a?(Hash)

              merged = DEFAULT_SETTINGS.dup
              raw.each { |k, v| merged[k.to_sym] = v unless v.nil? }
              merged
            end

            def enabled?
              settings[:enabled] == true
            end

            def reactive?
              s = settings
              s[:enabled] == true && s[:reactive] == true
            end

            def proactive?
              s = settings
              s[:enabled] == true && s[:proactive] == true
            end

            def llm_engine_options
              s = settings
              opts = s[:llm_engine_options]
              opts.is_a?(Hash) ? opts.transform_keys(&:to_sym) : DEFAULT_SETTINGS[:llm_engine_options].dup
            end
          end
        end
      end
    end
  end
end
