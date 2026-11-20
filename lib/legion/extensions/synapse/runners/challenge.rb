# frozen_string_literal: true

require 'legion/logging/helper'

require_relative '../helpers/challenge'
require_relative '../helpers/confidence'
require_relative '../data/models/synapse'
require_relative '../data/models/synapse_proposal'
require_relative '../data/models/synapse_challenge'
require_relative '../data/models/synapse_signal'
require_relative 'blast_radius'
require_relative 'mutate'

module Legion
  module Extensions
    module Synapse
      module Runners
        module Challenge
          include Legion::Logging::Helper
          include BlastRadius

          def pending_challenges
            Data::Model.define_synapse_proposal_model
            Data::Model::SynapseProposal.where(status: 'pending')
                                        .where(Sequel.|({ challenge_state: nil }, { challenge_state: 'deferred' }))
                                        .where(Sequel.|({ next_review_at: nil }, Sequel[:next_review_at] <= Time.now))
                                        .order(Sequel.case({ { challenge_state: nil } => 0 }, 1), Sequel.asc(:id)).all
          end

          def challenge_proposal(proposal_id:, transformer_client: nil, **)
            Data::Model.define_synapse_proposal_model
            Data::Model.define_synapse_challenge_model
            Data::Model.define_synapse_model
            Data::Model.define_synapse_signal_model

            return { success: true, skipped: true } unless Helpers::Challenge.enabled?

            proposal = Data::Model::SynapseProposal[proposal_id]
            return { success: false, error: 'proposal not found' } unless proposal

            challengeable = proposal.status == 'pending' && [nil, 'deferred'].include?(proposal.challenge_state)
            return { success: false, error: 'proposal not challengeable' } unless challengeable

            synapse = Data::Model::Synapse[proposal.synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse

            if proposal.next_review_at && proposal.next_review_at > Time.now
              return { success: false, deferred: true, proposal_id: proposal.id, reason: :review_backoff }
            end

            claimed = Data::Model::SynapseProposal.where(id: proposal.id, status: 'pending',
                                                         challenge_state: proposal.challenge_state,
                                                         review_attempts: proposal.review_attempts).update(challenge_state: 'challenging')
            return { success: false, error: 'proposal already claimed' } if claimed.zero?

            proposal.refresh

            impact = calculate_impact_score(proposal, synapse)
            confidence_impact = estimate_confidence_impact(proposal, synapse)
            proposal.update(impact_score: impact, estimated_confidence_impact: confidence_impact)

            if review_required?(impact: impact, synapse: synapse)
              return defer_review(proposal: proposal, reason: :reviewer_unavailable) unless transformer_client

              review = llm_challenge(proposal, synapse, transformer_client)
              return defer_review(proposal: proposal, reason: :review_incomplete) if review.verdict == 'abstain'
            end

            conflict_check(proposal)
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

          def apply_proposal(proposal_id:, **)
            Data::Model.define_synapse_signal_model
            Data::Model.define_synapse_challenge_model
            Data::Model.define_synapse_proposal_model
            Data::Model.define_synapse_model

            proposal = Data::Model::SynapseProposal[proposal_id]
            return { success: false, error: 'proposal not found' } unless proposal
            return { success: false, error: 'proposal not approved' } unless %w[approved auto_accepted].include?(proposal.status)
            return { success: false, error: 'proposal output missing' } if proposal.output.nil? || proposal.output.to_s.strip.empty?

            synapse = Data::Model::Synapse[proposal.synapse_id]
            return { success: false, error: 'synapse not found' } unless synapse

            if proposal.status == 'auto_accepted' && review_required?(impact: calculate_impact_score(proposal, synapse), synapse: synapse)
              reviewed = Data::Model::SynapseChallenge.where(proposal_id: proposal.id, challenger_type: 'llm', verdict: %w[support challenge]).any?
              return defer_review(proposal: proposal, reason: :reviewer_unavailable) unless reviewed
            end

            mutation = mutation_for_proposal(proposal)
            return { success: false, error: "unsupported proposal_type: #{proposal.proposal_type}" } unless mutation

            result = Object.new.extend(Mutate).mutate(
              synapse_id:    proposal.synapse_id,
              mutation_type: mutation[:mutation_type],
              changes:       mutation[:changes],
              trigger:       'gaia'
            )
            return result unless result[:success]

            proposal.update(status: 'applied', reviewed_at: Time.now)
            result.merge(proposal_id: proposal.id, status: 'applied', decision: 'applied')
          end

          def run_challenge_cycle(transformer_client: nil, **)
            Data::Model.define_synapse_proposal_model
            Data::Model.define_synapse_challenge_model
            return { challenged: 0, deferred: 0, applied: 0, resolved: 0 } unless Helpers::Challenge.enabled?

            settings = Helpers::Challenge.settings
            max = settings[:max_per_cycle] || 5

            challenged = 0
            deferred = 0
            pending_challenges.first(max).each do |proposal|
              result = challenge_proposal(proposal_id: proposal.id, transformer_client: transformer_client)
              result[:deferred] ? deferred += 1 : challenged += 1
            end

            applied = 0
            Data::Model::SynapseProposal.where(status: 'auto_accepted').order(Sequel.asc(:id)).limit(max).each do |proposal|
              result = apply_proposal(proposal_id: proposal.id)
              applied += 1 if result[:success]
              deferred += 1 if result[:deferred]
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

            { challenged: challenged, deferred: deferred, applied: applied, resolved: resolved }
          end

          private

          def review_required?(impact:, synapse:)
            Legion::Extensions::Synapse::Helpers::Challenge.above_impact_threshold?(impact) ||
              requires_llm_review?(synapse.blast_radius.to_s)
          end

          def defer_review(proposal:, reason:)
            settings = Legion::Extensions::Synapse::Helpers::Challenge.settings
            attempts = proposal.review_attempts + 1
            expired = attempts >= settings[:review_max_attempts]
            delay = [settings[:review_retry_seconds] * (2**(attempts - 1)), settings[:review_max_retry_seconds]].min
            proposal.update(status: expired ? 'expired' : 'pending', challenge_state: 'deferred', challenge_score: nil,
                            review_attempts: attempts, next_review_at: expired ? nil : Time.now + delay)
            { success: false, deferred: !expired, expired: expired, proposal_id: proposal.id,
              decision: expired ? 'expired' : 'deferred', reason: reason }
          end

          def mutation_for_proposal(proposal)
            case proposal.proposal_type
            when 'llm_transform', 'transform_mutation'
              { mutation_type: 'transform_adjusted', changes: { transform: proposal.output } }
            when 'attention_mutation'
              { mutation_type: 'attention_adjusted', changes: { attention: proposal.output } }
            when 'route_change'
              { mutation_type: 'route_changed', changes: { routing_strategy: proposal.output } }
            end
          end

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
            handle_exception(e, level: :warn, operation: :challenge_llm, proposal_id: proposal.id)
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
              proposal.update(status: 'auto_accepted', challenge_state: 'challenged', challenge_score: 0.0)
              return { success: true, challenge_score: 0.0, decision: 'auto_accepted' }
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
              'Is this change sound? Respond with a JSON object containing "verdict" ("support", "challenge", or "abstain") ' \
              'and "reasoning" (one sentence explanation).'
          end

          def parse_llm_verdict(response)
            if response.is_a?(Hash)
              verdict = response[:verdict].to_s.downcase
              verdict = 'abstain' unless Legion::Extensions::Synapse::Helpers::Challenge::VALID_VERDICTS.include?(verdict)
              return [verdict, response[:reasoning].to_s.slice(0, 200)]
            end
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

            recent.sum(&:challenger_confidence).to_f / recent.size
          end

          include Legion::Extensions::Helpers::Lex if defined?(Legion::Extensions::Helpers::Lex)
        end
      end
    end
  end
end
