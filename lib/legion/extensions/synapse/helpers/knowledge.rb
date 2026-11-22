# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module Extensions
    module Synapse
      module Helpers
        module Knowledge
          include Legion::Logging::Helper

          PATTERN_FORMAT = 'legion.synapse_pattern'

          private

          def knowledge_provider(client:)
            # Apollo is an optional host plugin. Standalone callers can inject its public client API.
            client || (Legion::Apollo if defined?(Legion::Apollo))
          end

          def publish_pattern(provider:, entry:)
            provider.ingest(content: entry.fetch(:content), raw_content: entry.fetch(:content),
                            content_type: :procedure, tags: entry.fetch(:tags), source_agent: 'lex-synapse', scope: :global)
          rescue StandardError => e
            raise if e.is_a?(NoMethodError) || e.is_a?(ArgumentError) || e.is_a?(TypeError)

            handle_exception(e, level: :warn, operation: :publish_synapse_pattern, synapse_id: entry[:synapse_id])
            { success: false, error: e.message }
          end

          def fetch_patterns(provider:, query:, limit:)
            provider.retrieve(text: query, limit: limit, scope: :global, tags: ['synapse'],
                              min_confidence: 0.7, status: %i[confirmed candidate])
          rescue StandardError => e
            raise if e.is_a?(NoMethodError) || e.is_a?(ArgumentError) || e.is_a?(TypeError)

            handle_exception(e, level: :warn, operation: :retrieve_synapse_patterns)
            { success: false, error: e.message }
          end
        end
      end
    end
  end
end
