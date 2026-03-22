# frozen_string_literal: true

require_relative '../helpers/confidence'
require_relative '../data/models/synapse'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Crystallize
          EMERGENCE_THRESHOLD = 20

          def crystallize(signal_pairs: [], threshold: EMERGENCE_THRESHOLD)
            Data::Model.define_synapse_model
            created = []

            signal_pairs.each do |pair|
              next if pair[:count] < threshold
              next if synapse_exists?(pair[:source_function_id], pair[:target_function_id])

              synapse = Data::Model::Synapse.create(
                source_function_id: pair[:source_function_id],
                target_function_id: pair[:target_function_id],
                origin:             'emergent',
                confidence:         Helpers::Confidence.starting_score(:emergent),
                status:             'observing'
              )
              created << { id: synapse.id, source: pair[:source_function_id], target: pair[:target_function_id] }
            end

            { success: true, created: created, count: created.size }
          end

          private

          def synapse_exists?(source_id, target_id)
            Data::Model::Synapse.where(
              source_function_id: source_id,
              target_function_id: target_id
            ).any?
          end

          include Legion::Extensions::Helpers::Lex if defined?(Legion::Extensions::Helpers::Lex)
        end
      end
    end
  end
end
