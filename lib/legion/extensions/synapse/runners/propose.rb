# frozen_string_literal: true

require_relative '../helpers/confidence'
require_relative '../helpers/proposals'
require_relative '../data/models/synapse'
require_relative '../data/models/synapse_signal'
require_relative '../data/models/synapse_proposal'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Propose
          PAIN_CORRELATION_THRESHOLD = 3

          def propose_reactive(synapse:, payload:, signal_id:, attention_result:, transform_result:,
                               transformer_client: nil)
            Data::Model.define_synapse_proposal_model
            return { proposals: [] } unless Helpers::Proposals.reactive?
            return { proposals: [] } unless transformer_client

            proposals = []

            # Trigger 1: No transform template exists
            if synapse.transform.nil? || synapse.transform.to_s.strip.empty?
              proposals << propose_llm_transform(synapse, payload, signal_id, transformer_client)
            end

            # Trigger 2: Transform failed
            if transform_result[:success] == false && synapse.transform && !synapse.transform.to_s.strip.empty?
              proposals << propose_transform_fix(synapse, payload, signal_id, transform_result, transformer_client)
            end

            # Trigger 3: Pain correlation — attention passed but recent downstream failures
            if attention_result[:passed] && pain_pattern?(synapse)
              proposals << propose_attention_adjustment(synapse, payload, signal_id, transformer_client)
            end

            { proposals: proposals.compact }
          end

          def propose_proactive
            Data::Model.define_synapse_model
            Data::Model.define_synapse_proposal_model
            Data::Model.define_synapse_signal_model
            return { proposals: [] } unless Helpers::Proposals.proactive?

            settings = Helpers::Proposals.settings
            max_per_run = settings[:max_per_run] || 3
            all_proposals = []

            Data::Model::Synapse.where(status: 'active').all.each do |synapse|
              next unless Helpers::Confidence.can_self_modify?(synapse.confidence)

              count = 0
              proposal = analyze_success_rate(synapse, settings)
              if proposal
                all_proposals << proposal
                count += 1
              end

              if count < max_per_run
                proposal = analyze_payload_drift(synapse, settings)
                if proposal
                  all_proposals << proposal
                  count += 1
                end
              end

              if count < max_per_run
                proposal = analyze_routing(synapse)
                all_proposals << proposal if proposal
              end
            end

            { proposals: all_proposals }
          end

          private

          def propose_llm_transform(synapse, payload, signal_id, transformer_client)
            source_schema = infer_schema(payload)
            target_schema = lookup_target_schema(synapse)
            prompt = build_transform_prompt(source_schema, target_schema)

            llm_result = call_llm(transformer_client, prompt)
            create_proposal(
              synapse: synapse, signal_id: signal_id, proposal_type: 'llm_transform',
              trigger: 'reactive',
              inputs: Legion::JSON.dump({ source_schema: source_schema, target_schema: target_schema }),
              output: llm_result[:output],
              rationale: 'no transform template exists for this synapse'
            )
          end

          def propose_transform_fix(synapse, payload, signal_id, transform_result, transformer_client)
            source_schema = infer_schema(payload)
            current_transform = synapse.transform
            errors = transform_result[:error]
            prompt = build_fix_prompt(current_transform, source_schema, errors)

            llm_result = call_llm(transformer_client, prompt)
            create_proposal(
              synapse: synapse, signal_id: signal_id, proposal_type: 'transform_mutation',
              trigger: 'reactive',
              inputs: Legion::JSON.dump({ current_transform: current_transform, errors: errors, payload_schema: source_schema }),
              output: llm_result[:output],
              rationale: "transform failed: #{Array(errors).first}"
            )
          end

          def propose_attention_adjustment(synapse, payload, signal_id, transformer_client)
            recent_failures = recent_failed_signals(synapse, 10)
            prompt = build_attention_prompt(synapse.attention, payload, recent_failures)

            llm_result = call_llm(transformer_client, prompt)
            create_proposal(
              synapse: synapse, signal_id: signal_id, proposal_type: 'attention_mutation',
              trigger: 'reactive',
              inputs: Legion::JSON.dump({ current_attention: synapse.attention, recent_failures: recent_failures.size }),
              output: llm_result[:output],
              rationale: "#{recent_failures.size} recent downstream failures despite attention passing"
            )
          end

          def analyze_success_rate(synapse, settings)
            threshold = settings[:success_rate_threshold] || 0.8
            signals = Data::Model::SynapseSignal.where(synapse_id: synapse.id).order(Sequel.desc(:id)).limit(100).all
            return nil if signals.size < 10

            success_count = signals.count { |s| s.transform_success }
            rate = success_count.to_f / signals.size
            return nil if rate >= threshold
            return nil if dedup_exists?(synapse.id, 'transform_mutation', 'proactive', settings)

            create_proposal(
              synapse: synapse, signal_id: nil, proposal_type: 'transform_mutation',
              trigger: 'proactive',
              inputs: Legion::JSON.dump({ success_rate: rate.round(3), sample_size: signals.size, threshold: threshold }),
              output: nil,
              rationale: "success rate #{(rate * 100).round(1)}% below threshold #{(threshold * 100).round(1)}%"
            )
          end

          def analyze_payload_drift(synapse, settings)
            return nil if synapse.transform.nil? || synapse.transform.to_s.strip.empty?

            drift_threshold = settings[:payload_drift_threshold] || 0.2
            signals = Data::Model::SynapseSignal.where(synapse_id: synapse.id).order(Sequel.desc(:id)).limit(50).all
            return nil if signals.size < 10

            failed = signals.count { |s| !s.transform_success }
            drift_rate = failed.to_f / signals.size
            return nil if drift_rate < drift_threshold
            return nil if dedup_exists?(synapse.id, 'transform_mutation', 'proactive', settings)

            create_proposal(
              synapse: synapse, signal_id: nil, proposal_type: 'transform_mutation',
              trigger: 'proactive',
              inputs: Legion::JSON.dump({ drift_rate: drift_rate.round(3), sample_size: signals.size }),
              output: nil,
              rationale: "payload drift detected: #{(drift_rate * 100).round(1)}% transform failures in recent signals"
            )
          end

          def analyze_routing(synapse)
            return nil if dedup_exists?(synapse.id, 'route_change', 'proactive', Helpers::Proposals.settings)

            signals = Data::Model::SynapseSignal.where(synapse_id: synapse.id).order(Sequel.desc(:id)).limit(50).all
            return nil if signals.size < 10

            nil
          end

          def pain_pattern?(synapse)
            recent = recent_failed_signals(synapse, 20)
            recent.size >= PAIN_CORRELATION_THRESHOLD
          end

          def recent_failed_signals(synapse, limit)
            Data::Model::SynapseSignal.where(
              synapse_id: synapse.id, downstream_outcome: 'failed'
            ).order(Sequel.desc(:id)).limit(limit).all
          end

          def dedup_exists?(synapse_id, proposal_type, trigger, settings)
            window = settings[:dedup_window_hours] || 24
            cutoff = Time.now - (window * 3600)
            Data::Model::SynapseProposal.where(
              synapse_id: synapse_id, proposal_type: proposal_type,
              trigger: trigger, status: 'pending'
            ).where(Sequel.lit('created_at >= ?', cutoff)).any?
          end

          def create_proposal(synapse:, signal_id:, proposal_type:, trigger:, inputs:, output:, rationale:)
            Data::Model::SynapseProposal.create(
              synapse_id: synapse.id,
              signal_id: signal_id,
              proposal_type: proposal_type,
              trigger: trigger,
              inputs: inputs,
              output: output,
              rationale: rationale,
              status: 'pending'
            )
          end

          def call_llm(transformer_client, prompt)
            return { output: nil } unless transformer_client

            engine_options = Helpers::Proposals.llm_engine_options
            result = transformer_client.transform(
              transformation: prompt, payload: {}, engine: :llm, engine_options: engine_options
            )
            { output: result[:success] ? Legion::JSON.dump(result[:result]) : nil }
          rescue StandardError => e
            Legion::Logging.warn("Proposal LLM call failed: #{e.message}")
            { output: nil }
          end

          def infer_schema(payload)
            return {} unless payload.is_a?(Hash)

            payload.transform_values { |v| v.class.name }
          end

          def lookup_target_schema(synapse)
            return {} unless synapse.target_function_id
            return {} unless defined?(Legion::Extensions::Lex)

            {}
          end

          def build_transform_prompt(source_schema, target_schema)
            "Given a payload with schema: #{Legion::JSON.dump(source_schema)}, " \
              "generate a JSON transform template that maps it to target schema: #{Legion::JSON.dump(target_schema)}. " \
              'Return only the JSON template string, no explanation.'
          end

          def build_fix_prompt(current_transform, source_schema, errors)
            "The current transform template is: #{current_transform}. " \
              "It failed with errors: #{Array(errors).join(', ')}. " \
              "The payload schema is: #{Legion::JSON.dump(source_schema)}. " \
              'Suggest a corrected transform template. Return only the JSON template string.'
          end

          def build_attention_prompt(current_attention, payload, recent_failures)
            "The current attention rules are: #{current_attention}. " \
              "Recent payload example: #{Legion::JSON.dump(payload)}. " \
              "There have been #{recent_failures.size} downstream failures despite attention passing. " \
              'Suggest refined attention rules as a JSON condition object. Return only JSON.'
          end
        end
      end
    end
  end
end
