# frozen_string_literal: true

require 'legion/extensions/synapse/helpers/confidence'
require 'legion/extensions/synapse/data/models/synapse'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Crystallize
          EMERGENCE_THRESHOLD = 20

          TRAFFIC_SAMPLE_LIMIT = 1000

          def crystallize(signal_pairs: nil, threshold: EMERGENCE_THRESHOLD, **)
            Data::Model.define_synapse_model
            signal_pairs ||= observed_task_pairs
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

          def observed_task_pairs
            db = Data::Model::Synapse.db
            return [] unless db.table_exists?(:tasks)

            children = db[:tasks].where(status: 'task.completed').exclude(parent_id: nil)
                                 .exclude(function_id: nil).reverse_order(:id).limit(TRAFFIC_SAMPLE_LIMIT).all
            parents = db[:tasks].where(id: children.map { |child| child[:parent_id] })
                                .select_map(%i[id function_id]).to_h
            counts = Hash.new(0)
            children.each do |child|
              source = parents[child[:parent_id]]
              counts[[source, child[:function_id]]] += 1 if source
            end
            counts.map do |(source, target), count|
              { source_function_id: source, target_function_id: target, count: count }
            end
          end

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
