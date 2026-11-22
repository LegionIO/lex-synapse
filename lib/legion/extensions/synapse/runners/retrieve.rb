# frozen_string_literal: true

require 'legion/logging/helper'
require 'legion/extensions/synapse/helpers/knowledge'

require 'legion/extensions/synapse/data/models/synapse'
require 'legion/extensions/synapse/helpers/confidence'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Retrieve
          include Legion::Logging::Helper
          include Legion::Extensions::Synapse::Helpers::Knowledge

          SEED_CONFIDENCE_THRESHOLD = 0.7

          def retrieve_and_seed(knowledge_entries: nil, apollo_client: nil, query: 'synapse routing patterns', limit: 100, **)
            Data::Model.define_synapse_model
            if knowledge_entries.nil?
              provider = knowledge_provider(client: apollo_client)
              return { success: false, error: 'Apollo unavailable', seeded: [], count: 0 } unless provider

              response = fetch_patterns(provider: provider, query: query, limit: limit)
              unless response[:success] == true && response[:entries].is_a?(Array)
                return { success: false, error: response[:error] || 'retrieval not complete', seeded: [], count: 0 }
              end

              knowledge_entries = response[:entries]
            end
            seeded = []

            knowledge_entries.each do |entry|
              pattern = eligible_pattern(entry: entry)
              next unless pattern
              next if synapse_exists?(pattern[:source_function_id], pattern[:target_function_id])

              synapse = Data::Model::Synapse.create(
                source_function_id: pattern[:source_function_id],
                target_function_id: pattern[:target_function_id],
                attention:          pattern[:attention],
                transform:          pattern[:transform],
                routing_strategy:   pattern[:routing_strategy] || 'direct',
                origin:             'seeded',
                confidence:         Helpers::Confidence.starting_score(:seeded),
                status:             'active'
              )
              seeded << { id: synapse.id, source: pattern[:source_function_id], target: pattern[:target_function_id] }
            end

            { success: true, seeded: seeded, count: seeded.size }
          end

          private

          def eligible_pattern(entry:)
            return unless entry[:confidence] && entry[:confidence] >= SEED_CONFIDENCE_THRESHOLD

            pattern = parse_pattern(entry)
            return unless pattern.is_a?(Hash)

            tagged = pattern[:format] == Legion::Extensions::Synapse::Helpers::Knowledge::PATTERN_FORMAT && pattern[:schema_version] == 1
            return unless tagged || (entry[:content_type] == 'synapse_pattern' && !pattern.key?(:format))
            return unless pattern[:source_function_id].is_a?(Integer) && pattern[:source_function_id].positive?
            return unless pattern[:target_function_id].is_a?(Integer) && pattern[:target_function_id].positive?

            pattern
          end

          def parse_pattern(entry)
            content = entry[:raw_content] || entry[:content]
            return nil unless content

            content.is_a?(String) ? Legion::JSON.load(content) : content
          rescue StandardError => e
            raise if e.is_a?(NoMethodError) || e.is_a?(ArgumentError) || e.is_a?(TypeError)

            handle_exception(e, level: :warn, operation: :parse_synapse_pattern)
            nil
          end

          def synapse_exists?(source_id, target_id)
            Data::Model::Synapse.where(
              source_function_id: source_id,
              target_function_id: target_id
            ).any?
          end
        end
      end
    end
  end
end
