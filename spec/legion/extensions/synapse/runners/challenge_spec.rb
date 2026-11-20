# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/actors/challenge'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/challenge'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/confidence'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/proposals'
require_relative '../../../../../lib/legion/extensions/synapse/runners/mutate'
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
    Legion::Extensions::Synapse::Data::Model.define_synapse_mutation_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_proposal_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_challenge_model
    Legion::Extensions::Synapse::Data::Model.define_synapse_signal_model
  end

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseChallenge.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
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

  describe '#apply_proposal' do
    it 'rolls back the proposal claim and live state if history cannot be written' do
      proposal.update(status: 'approved')
      allow(Legion::Extensions::Synapse::Data::Model::SynapseMutation).to receive(:create).and_raise(Sequel::Error, 'history unavailable')

      expect { runner.apply_proposal(proposal_id: proposal.id) }.to raise_error(Sequel::Error, 'history unavailable')
      expect(proposal.refresh.status).to eq('approved')
      expect(synapse.refresh.version).to eq(1)
      expect(synapse.transform).to be_nil
      expect(synapse.mutations_dataset.count).to eq(0)
    end

    it 'does not apply an already applied proposal again' do
      proposal.update(status: 'approved')
      expect(runner.apply_proposal(proposal_id: proposal.id)[:success]).to be(true)
      expect(runner.apply_proposal(proposal_id: proposal.id)[:success]).to be(false)
      expect(synapse.mutations_dataset.count).to eq(1)
    end

    it 'applies an auto-accepted transform proposal through the mutate runner' do
      proposal.update(status: 'auto_accepted', output: '{"template":"new"}')

      result = runner.apply_proposal(proposal_id: proposal.id)

      proposal.refresh
      synapse.refresh
      expect(result[:success]).to be true
      expect(result[:decision]).to eq('applied')
      expect(proposal.status).to eq('applied')
      expect(synapse.transform).to eq('{"template":"new"}')
    end

    it 'rejects proposals that are not approved or auto-accepted' do
      result = runner.apply_proposal(proposal_id: proposal.id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('proposal not approved')
    end
  end

  describe '#rolling_llm_confidence' do
    it 'averages recent resolved LLM challenger confidence' do
      [0.2, 0.4, 0.8].each do |confidence|
        Legion::Extensions::Synapse::Data::Model::SynapseChallenge.create(
          proposal_id:           proposal.id,
          challenger_type:       'llm',
          verdict:               'support',
          outcome:               'correct',
          challenger_confidence: confidence,
          reasoning:             'resolved',
          resolved_at:           Time.now.utc
        )
      end

      expect(runner.send(:rolling_llm_confidence)).to be_within(0.001).of(0.466)
    end
  end

  describe 'when challenge is disabled' do
    let(:settings_default) { { 'enabled' => false } }

    it 'returns skip result' do
      result = runner.challenge_proposal(proposal_id: proposal.id)
      expect(result[:skipped]).to be true
    end
  end

  describe 'blast radius multiplier on impact score' do
    it 'applies LOW multiplier (1.0) when blast_radius is LOW' do
      synapse.update(blast_radius: 'LOW', confidence: 0.5, baseline_throughput: 1.0)
      runner.challenge_proposal(proposal_id: proposal.id)
      proposal.refresh
      expect(proposal.impact_score).not_to be_nil
    end

    it 'applies CRITICAL multiplier (3.0) raising estimated_confidence_impact higher than LOW' do
      synapse_low = Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy: 'direct', confidence: 0.5, status: 'active',
        origin: 'explicit', version: 1, baseline_throughput: 1.0, blast_radius: 'LOW'
      )
      synapse_critical = Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy: 'direct', confidence: 0.5, status: 'active',
        origin: 'explicit', version: 1, baseline_throughput: 1.0, blast_radius: 'CRITICAL'
      )

      proposal_low = Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: synapse_low.id, proposal_type: 'transform_mutation',
        trigger: 'proactive', status: 'pending'
      )
      proposal_critical = Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: synapse_critical.id, proposal_type: 'transform_mutation',
        trigger: 'proactive', status: 'pending'
      )

      runner.challenge_proposal(proposal_id: proposal_low.id)
      runner.challenge_proposal(proposal_id: proposal_critical.id)

      proposal_low.refresh
      proposal_critical.refresh

      # estimated_confidence_impact = base * multiplier * 0.1, not dependent on signals
      expect(proposal_critical.estimated_confidence_impact).to be > proposal_low.estimated_confidence_impact
    end
  end

  describe 'estimated_confidence_impact population' do
    it 'populates estimated_confidence_impact on proposal' do
      runner.challenge_proposal(proposal_id: proposal.id)
      proposal.refresh
      expect(proposal.estimated_confidence_impact).not_to be_nil
      expect(proposal.estimated_confidence_impact).to be_between(0.0, 1.0)
    end

    it 'scales estimated_confidence_impact with blast radius' do
      synapse.update(blast_radius: 'CRITICAL')
      proposal2 = Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: synapse.id, proposal_type: 'transform_mutation',
        trigger: 'proactive', status: 'pending'
      )

      synapse_low = Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy: 'direct', confidence: 0.5, status: 'active',
        origin: 'explicit', version: 1, baseline_throughput: 1.0, blast_radius: 'LOW'
      )
      proposal_low = Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: synapse_low.id, proposal_type: 'transform_mutation',
        trigger: 'proactive', status: 'pending'
      )

      runner.challenge_proposal(proposal_id: proposal2.id)
      runner.challenge_proposal(proposal_id: proposal_low.id)

      proposal2.refresh
      proposal_low.refresh

      expect(proposal2.estimated_confidence_impact).to be > proposal_low.estimated_confidence_impact
    end
  end

  describe 'CRITICAL synapse requires LLM review' do
    it 'triggers LLM challenge for CRITICAL synapse even when below impact threshold' do
      # Low confidence/signals means impact < 0.3, but CRITICAL tier forces LLM review
      synapse.update(confidence: 0.1, baseline_throughput: 1000.0, blast_radius: 'CRITICAL')
      transformer = double('transformer_client')
      allow(transformer).to receive(:transform).and_return(
        { success: true, result: 'VERDICT: SUPPORT\nREASONING: sound change' }
      )

      runner.challenge_proposal(proposal_id: proposal.id, transformer_client: transformer)

      llm_challenges = Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(
        proposal_id: proposal.id, challenger_type: 'llm'
      )
      expect(llm_challenges.count).to eq(1)
    end

    it 'triggers LLM challenge for HIGH synapse even when below impact threshold' do
      synapse.update(confidence: 0.1, baseline_throughput: 1000.0, blast_radius: 'HIGH')
      transformer = double('transformer_client')
      allow(transformer).to receive(:transform).and_return(
        { success: true, result: 'VERDICT: SUPPORT\nREASONING: sound change' }
      )

      runner.challenge_proposal(proposal_id: proposal.id, transformer_client: transformer)

      llm_challenges = Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(
        proposal_id: proposal.id, challenger_type: 'llm'
      )
      expect(llm_challenges.count).to eq(1)
    end
  end

  describe 'required review availability' do
    let(:transformer) { double('transformer_client') }

    before do
      synapse.update(blast_radius: 'HIGH')
      allow(runner).to receive(:log).and_return(double('logger', warn: nil))
    end

    %w[HIGH CRITICAL].each do |tier|
      it "defers #{tier} proposals when the scheduled cycle has no reviewer" do
        synapse.update(blast_radius: tier)
        proposal
        expect(runner.run_challenge_cycle).to include(deferred: 1, applied: 0, challenged: 0)
        expect(proposal.refresh.status).to eq('pending')
        expect(proposal.challenge_state).to eq('deferred')
        expect(synapse.refresh.transform).to be_nil
        expect(runner.pending_challenges.map(&:id)).not_to include(proposal.id)
      end
    end

    [
      { success: false },
      { success: true, result: 'VERDICT: ABSTAIN' },
      { success: true, result: 'not a review' }
    ].each do |response|
      it "defers incomplete review #{response.inspect} and permits a later retry" do
        allow(transformer).to receive(:transform).and_return(response)
        result = runner.challenge_proposal(proposal_id: proposal.id, transformer_client: transformer)
        expect(result).to include(deferred: true, reason: :review_incomplete)
        expect(proposal.refresh.status).to eq('pending')

        proposal.update(next_review_at: Time.now - 1)
        allow(transformer).to receive(:transform).and_return(success: true, result: 'VERDICT: SUPPORT')
        expect(runner.run_challenge_cycle(transformer_client: transformer)).to include(applied: 1, deferred: 0)
        expect(synapse.refresh.transform).to eq(proposal.output)
        expect(Legion::Extensions::Synapse::Data::Model::SynapseChallenge.where(
          proposal_id: proposal.id, challenger_type: 'conflict'
        ).count).to eq(1)
      end
    end

    it 'uses the scheduled actor reviewer through the real transformer JSON engine' do
      llm = Module.new do
        def self.started? = true
        def self.chat(**) = nil
      end
      stub_const('Legion::LLM', llm)
      expect(llm).to receive(:chat).with(hash_including(message: include('JSON object')))
                                   .and_return(Struct.new(:content).new('{"verdict":"support","reasoning":"sound"}'))
      proposal
      actor = Legion::Extensions::Synapse::Actor::Challenge.allocate
      result = actor.public_send(actor.runner_function, **actor.args)
      expect(result).to include(applied: 1, deferred: 0)
      expect(proposal.refresh.status).to eq('applied')
    end

    it 'processes new low-impact proposals ahead of a full deferred queue' do
      5.times do
        older = Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
          synapse_id: synapse.id, proposal_type: 'transform_mutation', trigger: 'proactive', status: 'pending'
        )
        runner.challenge_proposal(proposal_id: older.id)
        older.update(next_review_at: Time.now - 1)
      end
      quiet = Legion::Extensions::Synapse::Data::Model::Synapse.create(confidence: 0.5, status: 'active')
      fresh = Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: quiet.id, proposal_type: 'transform_mutation', trigger: 'proactive', status: 'pending', output: '{}'
      )
      expect(runner.run_challenge_cycle).to include(applied: 1)
      expect(fresh.refresh.status).to eq('applied')
    end

    it 'persists exponential retry backoff and expires repeated reviewer failures' do
      allow(transformer).to receive(:transform).and_return(success: true, result: 'unparseable')
      runner.challenge_proposal(proposal_id: proposal.id, transformer_client: transformer)
      expect(proposal.refresh.review_attempts).to eq(1)
      expect(proposal.next_review_at - Time.now).to be_between(298, 301)
      10.times { runner.run_challenge_cycle(transformer_client: transformer) }
      expect(transformer).to have_received(:transform).once
      proposal.update(next_review_at: Time.now - 1)
      runner.run_challenge_cycle(transformer_client: transformer)
      expect(proposal.refresh.next_review_at - Time.now).to be_between(598, 601)
      proposal.update(next_review_at: Time.now - 1)
      runner.run_challenge_cycle(transformer_client: transformer)
      expect(proposal.refresh.status).to eq('expired')
      expect(proposal.review_attempts).to eq(3)
      runner.run_challenge_cycle(transformer_client: transformer)
      expect(transformer).to have_received(:transform).exactly(3).times
    end

    it 'keeps a reviewer exception deferred and does not mutate routing' do
      allow(transformer).to receive(:transform).and_raise(StandardError, 'review unavailable')
      expect(runner.challenge_proposal(proposal_id: proposal.id, transformer_client: transformer)).to include(deferred: true)
      expect(proposal.refresh.challenge_state).to eq('deferred')
      expect(synapse.refresh.transform).to be_nil
    end

    it 'defers previously auto-accepted proposals lacking required review' do
      proposal.update(status: 'auto_accepted', challenge_state: 'challenged')
      expect(runner.run_challenge_cycle).to include(deferred: 1, applied: 0)
      expect(proposal.refresh.status).to eq('pending')
      expect(synapse.refresh.transform).to be_nil
    end

    it 'preserves lower-impact automatic application without an LLM review' do
      synapse.update(blast_radius: 'LOW')
      proposal
      expect(runner.run_challenge_cycle).to include(applied: 1, deferred: 0)
    end

    it 'requires review for high impact even at LOW blast radius' do
      synapse.update(blast_radius: 'LOW', baseline_throughput: 1.0)
      2.times { Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(synapse_id: synapse.id) }
      expect(runner.challenge_proposal(proposal_id: proposal.id)).to include(deferred: true, reason: :reviewer_unavailable)
    end
  end
end
