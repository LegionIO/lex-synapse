# frozen_string_literal: true

require 'legion/extensions/synapse/data/models/synapse'
require 'legion/extensions/synapse/data/models/synapse_mutation'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Revert
          def revert(synapse_id:, to_version: nil, mutation_id: nil, trigger: 'pain', **)
            Data::Model.define_synapse_model
            Data::Model.define_synapse_mutation_model
            synapse = Data::Model::Synapse[synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse

            return { success: false, error: 'provide mutation_id or to_version, not both' } if mutation_id && to_version

            synapse.db.transaction do
              synapse.lock!
              mutation_version = to_version || synapse.version
              next { success: false, error: 'no previous version' } if !mutation_id && mutation_version < 2

              history = Data::Model::SynapseMutation.where(synapse_id: synapse.id)
              candidates = (mutation_id ? history.where(id: mutation_id) : history.where(version: mutation_version)).limit(2).all
              next { success: false, error: "mutation version or ID not found: #{mutation_id || mutation_version}" } if candidates.empty?
              next { success: false, error: 'ambiguous mutation version; provide mutation_id' } if candidates.size > 1

              mutation = candidates.first
              mutation_version = mutation.version
              before_state = Legion::JSON.load(mutation.before_state)
              restored_version = before_state[:version] || (mutation_version - 1)
              revert_version = [synapse.version, synapse.mutations_dataset.max(:version) || 1].max + 1
              current_state = synapse.values.slice(:attention, :transform, :routing_strategy, :confidence, :status, :version)
              synapse.update(
                attention:        before_state[:attention],
                transform:        before_state[:transform],
                routing_strategy: before_state[:routing_strategy],
                confidence:       before_state[:confidence] || synapse.confidence,
                status:           before_state[:status] || synapse.status,
                version:          restored_version
              )

              mutation.update(outcome: 'reverted')
              restored_state = synapse.values.slice(:attention, :transform, :routing_strategy, :confidence, :status, :version)
              Data::Model::SynapseMutation.create(
                synapse_id:    synapse.id,
                version:       revert_version,
                mutation_type: 'confidence_changed',
                before_state:  Legion::JSON.dump(current_state),
                after_state:   Legion::JSON.dump(restored_state),
                trigger:       trigger,
                outcome:       'reverted'
              )

              { success: true, reverted_to: restored_version, synapse_id: synapse.id }
            end
          end
        end
      end
    end
  end
end
