# frozen_string_literal: true

require 'legion/extensions/synapse/settings'

module Legion
  module Extensions
    module Synapse
      module Helpers
        module Proposals
          VALID_PROPOSAL_TYPES = %w[llm_transform attention_mutation transform_mutation route_change].freeze
          VALID_TRIGGERS = %w[reactive proactive].freeze
          VALID_STATUSES = %w[pending challenging challenged approved rejected applied expired auto_accepted auto_rejected].freeze

          DEFAULT_SETTINGS = Legion::Extensions::Synapse::Settings::PROPOSALS

          class << self
            def settings
              Legion::Extensions::Synapse::Settings.section(name: :proposals)
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
