# frozen_string_literal: true

require_relative '../data/models/synapse'
require_relative '../data/models/synapse_mutation'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Mutate
          VALID_MUTATION_TYPES = %w[attention_adjusted transform_adjusted route_changed confidence_changed].freeze
          VALID_TRIGGERS = %w[hebbian pain dream gaia manual].freeze

          def mutate(synapse_id:, mutation_type:, changes:, trigger:)
            Data::Model.define_synapse_model
            Data::Model.define_synapse_mutation_model
            synapse = Data::Model::Synapse[synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse
            return { success: false, error: "invalid mutation_type: #{mutation_type}" } unless VALID_MUTATION_TYPES.include?(mutation_type)
            return { success: false, error: "invalid trigger: #{trigger}" } unless VALID_TRIGGERS.include?(trigger)

            before_state = snapshot(synapse)
            apply_changes(synapse, mutation_type, changes)
            after_state = snapshot(synapse)

            new_version = synapse.version + 1
            synapse.update(version: new_version)

            Data::Model::SynapseMutation.create(
              synapse_id:    synapse.id,
              version:       new_version,
              mutation_type: mutation_type,
              before_state:  Legion::JSON.dump(before_state),
              after_state:   Legion::JSON.dump(after_state),
              trigger:       trigger
            )

            { success: true, version: new_version, synapse_id: synapse.id }
          end

          private

          def snapshot(synapse)
            {
              attention:        synapse.attention,
              transform:        synapse.transform,
              routing_strategy: synapse.routing_strategy,
              confidence:       synapse.confidence,
              status:           synapse.status
            }
          end

          def apply_changes(synapse, mutation_type, changes)
            case mutation_type
            when 'attention_adjusted'
              synapse.update(attention: changes[:attention]) if changes[:attention]
            when 'transform_adjusted'
              synapse.update(transform: changes[:transform]) if changes[:transform]
            when 'route_changed'
              synapse.update(routing_strategy: changes[:routing_strategy]) if changes[:routing_strategy]
            when 'confidence_changed'
              synapse.update(confidence: changes[:confidence]) if changes[:confidence]
            end
          end
        end
      end
    end
  end
end
