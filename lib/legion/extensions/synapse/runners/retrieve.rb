# frozen_string_literal: true

require_relative '../data/models/synapse'
require_relative '../helpers/confidence'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Retrieve
          SEED_CONFIDENCE_THRESHOLD = 0.7

          def retrieve_and_seed(knowledge_entries:, **)
            seeded = []

            knowledge_entries.each do |entry|
              next unless entry[:confidence] && entry[:confidence] >= SEED_CONFIDENCE_THRESHOLD
              next unless entry[:content_type] == 'synapse_pattern'

              pattern = parse_pattern(entry)
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

          def parse_pattern(entry)
            content = entry[:content]
            return nil unless content

            content.is_a?(String) ? Legion::JSON.load(content) : content
          rescue StandardError
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
