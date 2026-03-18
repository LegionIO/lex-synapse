# frozen_string_literal: true

require_relative '../data/models/synapse'
require_relative '../data/models/synapse_mutation'
require_relative '../helpers/confidence'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Dream
          def dream_replay(synapse_id: nil, **)
            synapses = if synapse_id
                         s = Data::Model::Synapse[synapse_id]
                         s ? [s] : []
                       else
                         Data::Model::Synapse.where { version > 1 }.all
                       end

            replays = synapses.map { |s| replay_mutations(s) }

            {
              success: true,
              replays: replays,
              count:   replays.size
            }
          end

          def dream_simulate(synapse_id:, mutation_type:, changes:, **)
            synapse = Data::Model::Synapse[synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse

            before = snapshot_state(synapse)
            simulated = apply_simulated_changes(before, mutation_type, changes)
            simulated_confidence = Helpers::Confidence.adjust(
              simulated[:confidence] || synapse.confidence,
              :success
            )
            simulated_mode = Helpers::Confidence.autonomy_mode(simulated_confidence)

            {
              success:              true,
              synapse_id:           synapse.id,
              before:               before,
              simulated:            simulated,
              simulated_confidence: simulated_confidence,
              simulated_mode:       simulated_mode,
              recommendation:       simulated_confidence > synapse.confidence ? :apply : :skip
            }
          end

          private

          def replay_mutations(synapse)
            mutations = synapse.mutations_dataset.order(:version).all
            timeline = mutations.map do |m|
              {
                version:       m.version,
                mutation_type: m.mutation_type,
                trigger:       m.trigger,
                outcome:       m.outcome,
                created_at:    m.created_at
              }
            end

            {
              synapse_id:      synapse.id,
              current_version: synapse.version,
              origin:          synapse.origin,
              confidence:      synapse.confidence,
              mutation_count:  mutations.size,
              timeline:        timeline,
              reverts:         mutations.count { |m| m.outcome == 'reverted' },
              net_trend:       synapse.confidence >= 0.5 ? :improving : :declining
            }
          end

          def snapshot_state(synapse)
            {
              attention:        synapse.attention,
              transform:        synapse.transform,
              routing_strategy: synapse.routing_strategy,
              confidence:       synapse.confidence,
              status:           synapse.status
            }
          end

          def apply_simulated_changes(state, mutation_type, changes)
            simulated = state.dup
            case mutation_type
            when 'attention_adjusted'
              simulated[:attention] = changes[:attention] if changes[:attention]
            when 'transform_adjusted'
              simulated[:transform] = changes[:transform] if changes[:transform]
            when 'route_changed'
              simulated[:routing_strategy] = changes[:routing_strategy] if changes[:routing_strategy]
            when 'confidence_changed'
              simulated[:confidence] = changes[:confidence] if changes[:confidence]
            end
            simulated
          end
        end
      end
    end
  end
end
