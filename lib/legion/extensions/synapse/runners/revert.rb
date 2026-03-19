# frozen_string_literal: true

require_relative '../data/models/synapse'
require_relative '../data/models/synapse_mutation'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Revert
          def revert(synapse_id:, to_version: nil, trigger: 'pain')
            Data::Model.define_synapse_model
            Data::Model.define_synapse_mutation_model
            synapse = Data::Model::Synapse[synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse

            # to_version specifies which mutation record to look up (by version number).
            # Reverting mutation at version N restores its before_state, landing at N-1.
            mutation_version = to_version || synapse.version
            return { success: false, error: 'no previous version' } if mutation_version < 2

            mutation = Data::Model::SynapseMutation.where(
              synapse_id: synapse.id,
              version:    mutation_version
            ).first

            return { success: false, error: "mutation version #{mutation_version} not found" } unless mutation

            restored_version = mutation_version - 1
            before_state = Legion::JSON.load(mutation.before_state)
            synapse.update(
              attention:        before_state[:attention],
              transform:        before_state[:transform],
              routing_strategy: before_state[:routing_strategy],
              confidence:       before_state[:confidence] || synapse.confidence,
              status:           before_state[:status] || synapse.status,
              version:          restored_version
            )

            # Mark the reverted mutation
            mutation.update(outcome: 'reverted')

            # Record the revert as a new mutation
            Data::Model::SynapseMutation.create(
              synapse_id:    synapse.id,
              version:       restored_version,
              mutation_type: 'confidence_changed',
              before_state:  mutation.after_state,
              after_state:   mutation.before_state,
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
