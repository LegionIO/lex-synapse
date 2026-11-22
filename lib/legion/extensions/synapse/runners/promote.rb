# frozen_string_literal: true

require 'legion/extensions/synapse/data/models/synapse'
require 'legion/extensions/synapse/helpers/knowledge'
require 'legion/extensions/synapse/data/models/synapse_mutation'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Promote
          include Legion::Extensions::Synapse::Helpers::Knowledge

          CONFIDENCE_THRESHOLD = 0.9
          STABILITY_HOURS = 24

          def promote(synapse_id: nil, apollo_client: nil, publish: true, **)
            Data::Model.define_synapse_model
            Data::Model.define_synapse_mutation_model
            candidates = if synapse_id
                           s = Data::Model::Synapse[synapse_id]
                           s ? [s] : []
                         else
                           find_promotable
                         end

            entries = candidates.select { |synapse| promotable?(synapse) }.map { |synapse| build_knowledge_entry(synapse) }
            result = { success: true, candidates: entries, candidate_count: entries.size, promoted: [], submitted: [], errors: [] }
            if publish && !entries.empty?
              provider = knowledge_provider(client: apollo_client)
              return result.merge(success: false, count: 0, error: 'Apollo unavailable') unless provider

              entries.each do |entry|
                response = publish_pattern(provider: provider, entry: entry)
                if response[:success] != true
                  result[:errors] << { synapse_id: entry[:synapse_id], error: response[:error] || 'publication not confirmed' }
                elsif response[:mode].to_s == 'async'
                  result[:submitted] << entry
                elsif response[:entry_id] || response[:id] || response[:mode].to_s == 'deduplicated'
                  result[:promoted] << entry
                else
                  result[:errors] << { synapse_id: entry[:synapse_id], error: 'publication not confirmed' }
                end
              end
            end
            result.merge(success: result[:errors].empty?, count: result[:promoted].size)
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

            cutoff = Time.now - (STABILITY_HOURS * 3600)
            return false if synapse.created_at > cutoff

            synapse.mutations_dataset.where { created_at > cutoff }.none?
          end

          def build_knowledge_entry(synapse)
            {
              content_type: 'synapse_pattern',
              content:      Legion::JSON.dump({
                                                format:             Legion::Extensions::Synapse::Helpers::Knowledge::PATTERN_FORMAT,
                                                schema_version:     1,
                                                source_function_id: synapse.source_function_id,
                                                target_function_id: synapse.target_function_id,
                                                attention:          synapse.attention,
                                                transform:          synapse.transform,
                                                routing_strategy:   synapse.routing_strategy,
                                                confidence:         synapse.confidence,
                                                origin:             synapse.origin,
                                                version:            synapse.version
                                              }),
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
