# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/challenge'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/confidence'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/proposals'
require_relative '../../../../../lib/legion/extensions/synapse/runners/challenge'

RSpec.describe Legion::Extensions::Synapse::Runners::Challenge do
  let(:test_class) { Class.new { include Legion::Extensions::Synapse::Runners::Challenge } }
  let(:runner) { test_class.new }
  let(:settings_default) { nil }

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'challenge').and_return(settings_default)
    allow(Legion::Settings).to receive(:dig).with('lex-synapse', 'proposals').and_return(nil)
    allow(Legion::Settings).to receive(:dig).with(:data, :connected).and_return(true)

    Legion::Extensions::Synapse::Data::Model.define_synapse_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_proposal_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_challenge_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_signal_model
  end

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseChallenge.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  let(:synapse) do
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
      routing_strategy: 'direct', confidence: 0.85, status: 'active',
      origin: 'explicit', version: 1, baseline_throughput: 10.0
    )
  end

  let(:proposal) do
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
      synapse_id: synapse.id, proposal_type: 'transform_mutation',
      trigger: 'proactive', status: 'pending',
      rationale: 'success rate 60% below threshold 80%',
      inputs: '{"success_rate":0.6}', output: '{"template":"new"}'
    )
  end

  describe '#pending_challenges' do
    it 'returns proposals with pending status and no challenge_state' do
      proposal
      results = runner.pending_challenges
      expect(results.size).to eq(1)
      expect(results.first.id).to eq(proposal.id)
    end

    it 'excludes proposals already in challenging state' do
      proposal.update(challenge_state: 'challenging')
      expect(runner.pending_challenges).to be_empty
    end
  end

  describe '#challenge_proposal' do
    it 'transitions proposal to challenging then to challenged' do
      runner.challenge_proposal(proposal_id: proposal.id)
      proposal.refresh
      expect(proposal.challenge_state).to eq('challenged')
      expect(proposal.impact_score).not_to be_nil
      expect(proposal.challenge_score).not_to be_nil
    end

    it 'creates a conflict challenge record' do
      runner.challenge_proposal(proposal_id: proposal.id)
      challenges = Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(proposal_id: proposal.id)
      expect(challenges.any? { |c| c.challenger_type == 'conflict' }).to be true
    end

    it 'skips LLM challenge when below impact threshold' do
      synapse.update(confidence: 0.1)
      runner.challenge_proposal(proposal_id: proposal.id)
      challenges = Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(
        proposal_id: proposal.id, challenger_type: 'llm'
      )
      expect(challenges.count).to eq(0)
    end

    it 'runs LLM challenge when above impact threshold' do
      # Add signals to drive throughput_factor above 0, pushing impact above 0.3 threshold
      # baseline_throughput=10.0, need recent_signals/baseline >= threshold/base/confidence
      # impact = base(0.5) * confidence(0.85) * throughput_factor; need >= 0.3
      # throughput_factor = signals/10.0; need >= 0.3/(0.5*0.85) ~= 0.71; so 8+ signals
      8.times do
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id: synapse.id, passed_attention: true,
          transform_success: true, latency_ms: 5
        )
      end
      transformer = double('transformer_client')
      allow(transformer).to receive(:transform).and_return(
        { success: true, result: 'VERDICT: SUPPORT\nREASONING: solid rationale' }
      )
      runner.challenge_proposal(proposal_id: proposal.id, transformer_client: transformer)
      challenges = Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(
        proposal_id: proposal.id, challenger_type: 'llm'
      )
      expect(challenges.count).to eq(1)
    end

    it 'returns error for nonexistent proposal' do
      result = runner.challenge_proposal(proposal_id: 99_999)
      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/)
    end

    it 'returns error for already-challenged proposal' do
      proposal.update(challenge_state: 'challenged')
      result = runner.challenge_proposal(proposal_id: proposal.id)
      expect(result[:success]).to be false
    end
  end

  describe 'conflict detection' do
    it 'detects conflicting proposals on same synapse' do
      proposal
      Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: synapse.id, proposal_type: 'transform_mutation',
        trigger: 'reactive', status: 'pending'
      )
      runner.challenge_proposal(proposal_id: proposal.id)
      conflicts = Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(
        proposal_id: proposal.id, challenger_type: 'conflict', verdict: 'challenge'
      )
      expect(conflicts.count).to eq(1)
    end

    it 'supports when no conflicting proposals exist' do
      runner.challenge_proposal(proposal_id: proposal.id)
      supports = Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(
        proposal_id: proposal.id, challenger_type: 'conflict', verdict: 'support'
      )
      expect(supports.count).to eq(1)
    end
  end

  describe 'aggregation and auto-decisions' do
    it 'auto-accepts on unanimous support above threshold' do
      runner.challenge_proposal(proposal_id: proposal.id)
      proposal.refresh
      expect(proposal.status).to eq('auto_accepted')
    end

    it 'auto-rejects when all challenges' do
      Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: synapse.id, proposal_type: 'transform_mutation',
        trigger: 'reactive', status: 'pending'
      )
      runner.challenge_proposal(proposal_id: proposal.id)
      proposal.refresh
      expect(proposal.status).to eq('auto_rejected')
    end
  end

  describe '#resolve_challenge_outcomes' do
    before do
      proposal.update(status: 'applied', challenge_state: 'challenged')
      Legion::Extensions::Synapse::Data::Model::SynapseChallenge.create(
        proposal_id: proposal.id, challenger_type: 'llm',
        verdict: 'support', challenger_confidence: 0.5
      )
    end

    it 'marks challenger correct when proposal improved outcomes' do
      55.times do
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id: synapse.id, passed_attention: true,
          transform_success: true, latency_ms: 10
        )
      end

      runner.resolve_challenge_outcomes(proposal_id: proposal.id)
      challenge = Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(
        proposal_id: proposal.id
      ).first
      expect(challenge.outcome).to eq('correct')
      expect(challenge.challenger_confidence).to be > 0.5
      expect(challenge.resolved_at).not_to be_nil
    end

    it 'marks challenger incorrect when proposal worsened outcomes' do
      55.times do
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id: synapse.id, passed_attention: true,
          transform_success: false, latency_ms: 10
        )
      end

      runner.resolve_challenge_outcomes(proposal_id: proposal.id)
      challenge = Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(
        proposal_id: proposal.id
      ).first
      expect(challenge.outcome).to eq('incorrect')
      expect(challenge.challenger_confidence).to be < 0.5
    end
  end

  describe 'when challenge is disabled' do
    let(:settings_default) { { 'enabled' => false } }

    it 'returns skip result' do
      result = runner.challenge_proposal(proposal_id: proposal.id)
      expect(result[:skipped]).to be true
    end
  end
end
