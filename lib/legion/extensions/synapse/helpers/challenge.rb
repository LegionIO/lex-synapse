# frozen_string_literal: true

require 'legion/extensions/synapse/settings'

module Legion
  module Extensions
    module Synapse
      module Helpers
        module Challenge
          VALID_VERDICTS = %w[support challenge abstain].freeze
          VALID_CHALLENGER_TYPES = %w[conflict llm].freeze
          VALID_OUTCOMES = %w[correct incorrect].freeze
          VALID_CHALLENGE_STATES = %w[challenging challenged deferred].freeze

          IMPACT_WEIGHTS = {
            'llm_transform'      => 0.7,
            'transform_mutation' => 0.5,
            'attention_mutation' => 0.6,
            'route_change'       => 0.8
          }.freeze

          DEFAULT_SETTINGS = Legion::Extensions::Synapse::Settings::CHALLENGE

          class << self
            def settings
              Legion::Extensions::Synapse::Settings.section(name: :challenge)
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
