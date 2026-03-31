# frozen_string_literal: true

require_relative '../data/models/synapse'
require_relative '../data/models/synapse_proposal'

module Legion
  module Extensions
    module Synapse
      module Runners
        module BlastRadius
          TIER_CRITICAL = 'CRITICAL'
          TIER_HIGH     = 'HIGH'
          TIER_MED      = 'MED'
          TIER_LOW      = 'LOW'

          BLAST_MULTIPLIERS = {
            TIER_LOW      => 1.0,
            TIER_MED      => 1.5,
            TIER_HIGH     => 2.0,
            TIER_CRITICAL => 3.0
          }.freeze

          def compute(**_opts)
            Data::Model.define_synapse_model
            return { success: false, error: 'data unavailable' } unless data_available?

            synapses = Data::Model::Synapse.where(status: 'active').all
            return { success: true, updated: 0, skipped: 0 } if synapses.empty?

            graph = build_graph(synapses)
            updated = 0
            skipped = 0

            synapses.each do |synapse|
              depth, count = bfs_reachable(synapse.id, graph)
              tier = classify_tier(
                depth:      depth,
                downstream: count,
                throughput: synapse.baseline_throughput.to_f
              )

              synapse.update(
                propagation_depth:       depth,
                downstream_count:        count,
                blast_radius:            tier,
                blast_radius_updated_at: Time.now
              )
              updated += 1
            rescue StandardError => e
              log.warn("blast_radius update failed for synapse #{synapse.id}: #{e.message}")
              skipped += 1
            end

            { success: true, updated: updated, skipped: skipped }
          end

          def blast_tier(synapse_id:)
            Data::Model.define_synapse_model
            synapse = Data::Model::Synapse[synapse_id]
            return nil unless synapse

            synapse.blast_radius
          end

          def blast_multiplier_for(blast_radius_tier)
            BLAST_MULTIPLIERS.fetch(blast_radius_tier.to_s.upcase, 1.0)
          end

          def requires_llm_review?(blast_radius_tier)
            tier = blast_radius_tier.to_s.upcase
            [TIER_HIGH, TIER_CRITICAL].include?(tier)
          end

          private

          def data_available?
            defined?(Legion::Data) && Legion::Settings.dig(:data, :connected)
          end

          def build_graph(synapses)
            graph = Hash.new { |h, k| h[k] = [] }
            synapses.each do |s|
              next unless s.source_function_id && s.target_function_id

              graph[s.source_function_id] << s.target_function_id
            end
            graph
          end

          def bfs_reachable(synapse_id, graph)
            synapse = Data::Model::Synapse[synapse_id]
            return [0, 0] unless synapse&.source_function_id && synapse.target_function_id

            start = synapse.source_function_id
            visited = {}
            queue = [[start, 0]]
            max_depth = 0
            reachable = 0

            until queue.empty?
              node, depth = queue.shift
              next if visited[node]

              visited[node] = true

              if depth.positive?
                reachable += 1
                max_depth = depth if depth > max_depth
              end

              graph[node].each do |neighbor|
                queue << [neighbor, depth + 1] unless visited[neighbor]
              end
            end

            [max_depth, reachable]
          end

          def classify_tier(depth:, downstream:, throughput:)
            if depth > 5 || downstream > 25 || throughput > 500
              TIER_CRITICAL
            elsif depth > 3 || downstream > 10 || throughput > 100
              TIER_HIGH
            elsif depth > 1 || downstream > 3
              TIER_MED
            else
              TIER_LOW
            end
          end

          def log_warn(message)
            log.warn(message)
          end
        end
      end
    end
  end
end
