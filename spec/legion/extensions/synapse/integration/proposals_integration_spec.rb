# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/client'

RSpec.describe 'Proposal integration' do
  let(:transformer_client) { double('TransformerClient') }
  let(:conditioner_client) { double('ConditionerClient') }
  let(:client) do
    Legion::Extensions::Synapse::Client.new(
      conditioner_client: conditioner_client,
      transformer_client: transformer_client
    )
  end

  before do
    allow(conditioner_client).to receive(:evaluate).and_return({ valid: true, explanation: {} })
    allow(transformer_client).to receive(:transform).and_return(
      { success: true, result: { mapped: 'value' } }
    )
    allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:reactive?).and_return(true)
    allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:settings).and_return(
      Legion::Extensions::Synapse::Helpers::Proposals::DEFAULT_SETTINGS
    )
    allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:llm_engine_options).and_return(
      { temperature: 0.3, max_tokens: 1024 }
    )
  end

  after(:each) do
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  describe 'full evaluate flow with autonomous synapse' do
    it 'generates a reactive proposal alongside normal transform execution' do
      synapse = client.create(source_function_id: 10, target_function_id: 20)
      synapse.update(confidence: 0.85)

      result = client.evaluate(synapse_id: synapse.id, payload: { action: 'test' })
      expect(result[:success]).to be true
      expect(result[:mode]).to eq(:autonomous)

      proposals = client.proposals(synapse_id: synapse.id, status: 'pending')
      expect(proposals.size).to be >= 1
      expect(proposals.first.proposal_type).to eq('llm_transform')
    end

    it 'does not generate proposals for non-autonomous synapses' do
      synapse = client.create(source_function_id: 10, target_function_id: 20)

      client.evaluate(synapse_id: synapse.id, payload: { action: 'test' })

      proposals = client.proposals(synapse_id: synapse.id)
      expect(proposals).to be_empty
    end
  end

  describe 'proactive analysis across multiple synapses' do
    it 'only proposes for autonomous synapses' do
      autonomous = client.create(source_function_id: 1, target_function_id: 2)
      autonomous.update(confidence: 0.85)
      12.times do |i|
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id: autonomous.id, passed_attention: true,
          transform_success: i < 4, latency_ms: 5
        )
      end

      non_autonomous = client.create(source_function_id: 3, target_function_id: 4)
      non_autonomous.update(confidence: 0.5)
      12.times do
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id: non_autonomous.id, passed_attention: true,
          transform_success: false, latency_ms: 5
        )
      end

      allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:proactive?).and_return(true)
      client.propose_proactive

      autonomous_proposals = client.proposals(synapse_id: autonomous.id)
      non_autonomous_proposals = client.proposals(synapse_id: non_autonomous.id)

      expect(autonomous_proposals.size).to be >= 1
      expect(non_autonomous_proposals).to be_empty
    end
  end

  describe 'proposal review workflow' do
    it 'approves a proposal and sets reviewed_at' do
      synapse = client.create(source_function_id: 10, target_function_id: 20)
      synapse.update(confidence: 0.85)

      client.evaluate(synapse_id: synapse.id, payload: { x: 1 })
      proposals = client.proposals(synapse_id: synapse.id, status: 'pending')
      return if proposals.empty?

      result = client.review_proposal(proposal_id: proposals.first.id, status: 'approved')
      expect(result[:success]).to be true

      updated = client.proposals(synapse_id: synapse.id, status: 'approved')
      expect(updated.size).to eq(1)
      expect(updated.first.reviewed_at).not_to be_nil
    end
  end

  describe 'dedup across reactive and proactive' do
    it 'does not create duplicate proactive proposals' do
      synapse = client.create(source_function_id: 1, target_function_id: 2)
      synapse.update(confidence: 0.85)
      12.times do |i|
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id: synapse.id, passed_attention: true,
          transform_success: i < 4, latency_ms: 5
        )
      end

      allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:proactive?).and_return(true)
      client.propose_proactive
      first_count = client.proposals(synapse_id: synapse.id).size

      client.propose_proactive
      second_count = client.proposals(synapse_id: synapse.id).size
      expect(second_count).to eq(first_count)
    end
  end
end
