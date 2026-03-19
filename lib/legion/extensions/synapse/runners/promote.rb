# frozen_string_literal: true

require_relative '../data/models/synapse'
require_relative '../data/models/synapse_mutation'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Promote
          CONFIDENCE_THRESHOLD = 0.9
          STABILITY_HOURS = 24

          def promote(synapse_id: nil, **)
            Data::Model.define_synapse_model
            Data::Model.define_synapse_mutation_model
            candidates = if synapse_id
                           s = Data::Model::Synapse[synapse_id]
                           s ? [s] : []
                         else
                           find_promotable
                         end

            promoted = []
            candidates.each do |synapse|
              next unless promotable?(synapse)

              entry = build_knowledge_entry(synapse)
              promoted << entry
            end

            {
              success:  true,
              promoted: promoted,
              count:    promoted.size
            }
          end

          private

          def find_promotable
            Data::Model::Synapse
              .where { confidence >= CONFIDENCE_THRESHOLD }
              .where(status: 'active')
              .all
          end

          def promotable?(synapse)
            return false if synapse.confidence < CONFIDENCE_THRESHOLD
            return false unless synapse.status == 'active'

            recent_reverts = synapse.mutations_dataset
                                    .where(outcome: 'reverted')
                                    .where { created_at >= Time.now - (STABILITY_HOURS * 3600) }
                                    .count
            recent_reverts.zero?
          end

          def build_knowledge_entry(synapse)
            {
              content_type: 'synapse_pattern',
              content:      Legion::JSON.dump(
                source_function_id: synapse.source_function_id,
                target_function_id: synapse.target_function_id,
                attention:          synapse.attention,
                transform:          synapse.transform,
                routing_strategy:   synapse.routing_strategy,
                confidence:         synapse.confidence,
                origin:             synapse.origin,
                version:            synapse.version
              ),
              tags:         ['synapse', "origin:#{synapse.origin}", "route:#{synapse.routing_strategy}"],
              source_agent: 'lex-synapse',
              synapse_id:   synapse.id
            }
          end
        end
      end
    end
  end
end
