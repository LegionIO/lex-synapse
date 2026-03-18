# frozen_string_literal: true

require_relative '../data/models/synapse'
require_relative 'confidence'

module Legion
  module Extensions
    module Synapse
      module Helpers
        module RelationshipWrapper
          class << self
            def wrap(relationship)
              existing = Data::Model::Synapse.where(relationship_id: relationship[:id]).first
              return existing if existing

              Data::Model::Synapse.create(
                source_function_id: relationship[:trigger_function_id],
                target_function_id: relationship[:function_id],
                relationship_id:    relationship[:id],
                attention:          relationship[:conditions],
                transform:          relationship[:transformation],
                routing_strategy:   'direct',
                origin:             'explicit',
                confidence:         Confidence.starting_score(:explicit),
                status:             'active'
              )
            end

            def unwrap(synapse_id)
              synapse = Data::Model::Synapse[synapse_id]
              return { success: false, error: 'synapse not found' } unless synapse
              return { success: false, error: 'not a wrapped relationship' } unless synapse.relationship_id

              synapse.destroy
              { success: true, relationship_id: synapse.relationship_id }
            end
          end
        end
      end
    end
  end
end
