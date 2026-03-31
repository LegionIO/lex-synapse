# frozen_string_literal: true

require_relative '../helpers/challenge'
require_relative '../helpers/confidence'
require_relative '../data/models/synapse'
require_relative '../data/models/synapse_proposal'
require_relative '../data/models/synapse_challenge'
require_relative '../data/models/synapse_signal'
require_relative 'blast_radius'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Challenge
          include BlastRadius

          def pending_challenges
            Data::Model.define_synapse_proposal_model
            Data::Model::SynapseProposal.where(status: 'pending', challenge_state: nil)
                                        .order(Sequel.asc(:id)).all
          end

          def challenge_proposal(proposal_id:, transformer_client: nil)
            Data::Model.define_synapse_proposal_model
            Data::Model.define_synapse_challenge_model
            Data::Model.define_synapse_model
            Data::Model.define_synapse_signal_model

            return { success: true, skipped: true } unless Helpers::Challenge.enabled?

            proposal = Data::Model::SynapseProposal[proposal_id]
            return { success: false, error: 'proposal not found' } unless proposal
            return { success: false, error: 'proposal not challengeable' } unless proposal.status == 'pending' && proposal.challenge_state.nil?

            synapse = Data::Model::Synapse[proposal.synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse

            proposal.update(challenge_state: 'challenging')

            impact = calculate_impact_score(proposal, synapse)
            confidence_impact = estimate_confidence_impact(proposal, synapse)
            proposal.update(impact_score: impact, estimated_confidence_impact: confidence_impact)

            conflict_check(proposal)

            needs_llm = Helpers::Challenge.above_impact_threshold?(impact) ||
                        requires_llm_review?(synapse.blast_radius.to_s)
            llm_challenge(proposal, synapse, transformer_client) if needs_llm && transformer_client

            aggregate_challenges(proposal)
          end

          def resolve_challenge_outcomes(proposal_id:)
            Data::Model.define_synapse_proposal_model
            Data::Model.define_synapse_challenge_model
            Data::Model.define_synapse_signal_model

            proposal = Data::Model::SynapseProposal[proposal_id]
            return { success: false, error: 'proposal not found' } unless proposal
            return { success: false, error: 'proposal not applied' } unless proposal.status == 'applied'

            settings = Helpers::Challenge.settings
            window = settings[:outcome_observation_window] || 50

            signals = Data::Model::SynapseSignal.where(synapse_id: proposal.synapse_id)
                                                .order(Sequel.desc(:id)).limit(window).all
            return { success: false, error: 'insufficient signals' } if signals.size < window

            success_rate = signals.count(&:transform_success).to_f / signals.size
            proposal_succeeded = success_rate >= 0.7

            challenges = Data::Model::SynapseChallenge.where(proposal_id: proposal_id)
                                                      .exclude(verdict: 'abstain').all

            challenges.each do |challenge|
              supported = challenge.verdict == 'support'
              correct = (supported && proposal_succeeded) || (!supported && !proposal_succeeded)
              outcome = correct ? 'correct' : 'incorrect'

              adj = correct ? settings[:challenger_correct_adjustment] : settings[:challenger_incorrect_adjustment]
              new_conf = (challenge.challenger_confidence + adj).clamp(0.0, 1.0)

              challenge.update(outcome: outcome, challenger_confidence: new_conf, resolved_at: Time.now)
            end

            { success: true, proposal_id: proposal_id, success_rate: success_rate, resolved: challenges.size }
          end

          def run_challenge_cycle(transformer_client: nil)
            Data::Model.define_synapse_proposal_model
            Data::Model.define_synapse_challenge_model
            return { challenged: 0, resolved: 0 } unless Helpers::Challenge.enabled?

            settings = Helpers::Challenge.settings
            max = settings[:max_per_cycle] || 5

            challenged = 0
            pending_challenges.first(max).each do |proposal|
              challenge_proposal(proposal_id: proposal.id, transformer_client: transformer_client)
              challenged += 1
            end

            resolved = 0
            window = settings[:outcome_observation_window] || 50
            Data::Model.define_synapse_signal_model
            Data::Model::SynapseProposal.where(status: 'applied').each do |proposal|
              cutoff = proposal.respond_to?(:reviewed_at) && proposal.reviewed_at ? proposal.reviewed_at : proposal.created_at
              post_signals = Data::Model::SynapseSignal.where(synapse_id: proposal.synapse_id)
                                                       .where { created_at >= cutoff }.count
              next unless post_signals >= window

              unresolved = Data::Model::SynapseChallenge.where(proposal_id: proposal.id, outcome: nil)
                                                        .exclude(verdict: 'abstain')
              next unless unresolved.any?

              resolve_challenge_outcomes(proposal_id: proposal.id)
              resolved += 1
            end

            { challenged: challenged, resolved: resolved }
          end

          private

          def conflict_check(proposal)
            conflicts = Data::Model::SynapseProposal.where(
              synapse_id:    proposal.synapse_id,
              proposal_type: proposal.proposal_type,
              status:        'pending'
            ).exclude(id: proposal.id)

            if conflicts.any?
              Data::Model::SynapseChallenge.create(
                proposal_id: proposal.id, challenger_type: 'conflict',
                verdict: 'challenge',
                reasoning: "#{conflicts.count} conflicting #{proposal.proposal_type} proposal(s) pending on same synapse",
                challenger_confidence: Helpers::Challenge.settings[:challenger_starting_confidence]
              )
            else
              Data::Model::SynapseChallenge.create(
                proposal_id: proposal.id, challenger_type: 'conflict',
                verdict: 'support', reasoning: 'no conflicting proposals',
                challenger_confidence: Helpers::Challenge.settings[:challenger_starting_confidence]
              )
            end
          end

          def llm_challenge(proposal, synapse, transformer_client)
            prompt = build_challenge_prompt(proposal, synapse)
            engine_options = Helpers::Challenge.settings[:llm_engine_options]

            result = transformer_client.transform(
              transformation: prompt, payload: {}, engine: :llm, engine_options: engine_options
            )

            verdict, reasoning = parse_llm_verdict(result[:success] ? result[:result] : nil)

            llm_confidence = rolling_llm_confidence
            Data::Model::SynapseChallenge.create(
              proposal_id: proposal.id, challenger_type: 'llm',
              verdict: verdict, reasoning: reasoning,
              challenger_confidence: llm_confidence
            )
          rescue StandardError => e
            log.warn("Challenge LLM call failed: #{e.message}")
            Data::Model::SynapseChallenge.create(
              proposal_id: proposal.id, challenger_type: 'llm',
              verdict: 'abstain', reasoning: "LLM error: #{e.message}",
              challenger_confidence: Helpers::Challenge.settings[:challenger_starting_confidence]
            )
          end

          def aggregate_challenges(proposal)
            challenges = Data::Model::SynapseChallenge.where(proposal_id: proposal.id)
                                                      .exclude(verdict: 'abstain').all

            if challenges.empty?
              proposal.update(challenge_state: 'challenged', challenge_score: 0.5)
              return { success: true, challenge_score: 0.5, decision: 'challenged' }
            end

            support_weight = challenges.select { |c| c.verdict == 'support' }.sum(&:challenger_confidence)
            challenge_weight = challenges.select { |c| c.verdict == 'challenge' }.sum(&:challenger_confidence)
            total = support_weight + challenge_weight

            score = total.zero? ? 0.5 : support_weight / total

            settings = Helpers::Challenge.settings
            decision = if score >= settings[:auto_accept_threshold]
                         proposal.update(status: 'auto_accepted', challenge_state: 'challenged', challenge_score: score)
                         'auto_accepted'
                       elsif score <= settings[:auto_reject_threshold]
                         proposal.update(status: 'auto_rejected', challenge_state: 'challenged', challenge_score: score)
                         'auto_rejected'
                       else
                         proposal.update(challenge_state: 'challenged', challenge_score: score)
                         'challenged'
                       end

            { success: true, challenge_score: score, decision: decision }
          end

          def calculate_impact_score(proposal, synapse)
            base = Helpers::Challenge::IMPACT_WEIGHTS.fetch(proposal.proposal_type, 0.5)
            recent_signals = Data::Model::SynapseSignal.where(synapse_id: synapse.id).count
            baseline = [synapse.respond_to?(:baseline_throughput) && synapse.baseline_throughput ? synapse.baseline_throughput : 1.0, 1.0].max
            throughput_factor = [recent_signals.to_f / baseline, 2.0].min

            multiplier = blast_multiplier_for(synapse.blast_radius.to_s)
            (base * synapse.confidence * throughput_factor * multiplier).clamp(0.0, 1.0)
          end

          def estimate_confidence_impact(proposal, synapse)
            base = Helpers::Challenge::IMPACT_WEIGHTS.fetch(proposal.proposal_type, 0.5)
            multiplier = blast_multiplier_for(synapse.blast_radius.to_s)
            (base * multiplier * 0.1).clamp(0.0, 1.0)
          end

          def build_challenge_prompt(proposal, synapse)
            "Evaluate this proposed change to a cognitive routing synapse.\n\n" \
              "Synapse confidence: #{synapse.confidence}\n" \
              "Proposal type: #{proposal.proposal_type}\n" \
              "Rationale: #{proposal.rationale}\n" \
              "Proposed inputs: #{proposal.inputs}\n" \
              "Proposed output: #{proposal.output}\n\n" \
              "Is this change sound? Respond in exactly this format:\n" \
              "VERDICT: SUPPORT or CHALLENGE or ABSTAIN\n" \
              'REASONING: one sentence explanation'
          end

          def parse_llm_verdict(response)
            return ['abstain', 'no LLM response'] unless response.is_a?(String)

            text = response.to_s.strip
            verdict = if text.match?(/VERDICT:\s*SUPPORT/i)
                        'support'
                      elsif text.match?(/VERDICT:\s*CHALLENGE/i)
                        'challenge'
                      else
                        'abstain'
                      end

            reasoning_match = text.match(/REASONING:\s*(.+)/i)
            reasoning = reasoning_match ? reasoning_match[1].strip : text.slice(0, 200)

            [verdict, reasoning]
          end

          def rolling_llm_confidence
            recent = Data::Model::SynapseChallenge.where(challenger_type: 'llm')
                                                  .exclude(outcome: nil)
                                                  .order(Sequel.desc(:id)).limit(20).all
            return Helpers::Challenge.settings[:challenger_starting_confidence] if recent.empty?

            recent.first.challenger_confidence
          end

          include Legion::Extensions::Helpers::Lex if defined?(Legion::Extensions::Helpers::Lex)
        end
      end
    end
  end
end
