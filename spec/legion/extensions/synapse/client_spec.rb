# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/legion/extensions/synapse/client'

RSpec.describe Legion::Extensions::Synapse::Client do
  subject(:client) { described_class.new }

  after(:each) do
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  describe '#initialize' do
    it 'defaults conditioner_client to nil' do
      expect(client.conditioner_client).to be_nil
    end

    it 'defaults transformer_client to nil' do
      expect(client.transformer_client).to be_nil
    end

    it 'accepts injected conditioner_client' do
      conditioner = double('ConditionerClient')
      c = described_class.new(conditioner_client: conditioner)
      expect(c.conditioner_client).to eq(conditioner)
    end

    it 'accepts injected transformer_client' do
      transformer = double('TransformerClient')
      c = described_class.new(transformer_client: transformer)
      expect(c.transformer_client).to eq(transformer)
    end
  end

  describe '#create' do
    it 'creates a synapse with explicit origin and active status' do
      synapse = client.create(source_function_id: 1, target_function_id: 2)
      expect(synapse.status).to eq('active')
      expect(synapse.origin).to eq('explicit')
    end

    it 'sets confidence to 0.7 for explicit origin' do
      synapse = client.create(source_function_id: 1, target_function_id: 2)
      expect(synapse.confidence).to eq(0.7)
    end

    it 'sets confidence to 0.3 for emergent origin' do
      synapse = client.create(source_function_id: 1, target_function_id: 2, origin: 'emergent')
      expect(synapse.confidence).to eq(0.3)
    end

    it 'sets status to observing for emergent origin' do
      synapse = client.create(source_function_id: 1, target_function_id: 2, origin: 'emergent')
      expect(synapse.status).to eq('observing')
    end

    it 'persists source_function_id and target_function_id' do
      synapse = client.create(source_function_id: 10, target_function_id: 20)
      expect(synapse.source_function_id).to eq(10)
      expect(synapse.target_function_id).to eq(20)
    end

    it 'persists optional relationship_id' do
      synapse = client.create(source_function_id: 1, target_function_id: 2, relationship_id: 99)
      expect(synapse.relationship_id).to eq(99)
    end

    it 'persists attention and transform' do
      synapse = client.create(source_function_id: 1, target_function_id: 2,
                              attention: '{"field":"x"}', transform: '{"template":"y"}')
      expect(synapse.attention).to eq('{"field":"x"}')
      expect(synapse.transform).to eq('{"template":"y"}')
    end

    it 'defaults routing_strategy to direct' do
      synapse = client.create(source_function_id: 1, target_function_id: 2)
      expect(synapse.routing_strategy).to eq('direct')
    end
  end

  describe '#evaluate' do
    let(:synapse) do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy:    'direct',
        confidence:          0.7,
        baseline_throughput: 1.0,
        origin:              'explicit',
        status:              'active',
        version:             1
      )
    end

    it 'delegates to Runners::Evaluate and returns success' do
      result = client.evaluate(synapse_id: synapse.id, payload: { foo: 'bar' })
      expect(result[:success]).to be true
    end

    it 'uses injected conditioner_client' do
      conditioner = double('ConditionerClient')
      allow(conditioner).to receive(:evaluate).and_return({ valid: true, explanation: {} })
      c = described_class.new(conditioner_client: conditioner)
      synapse.update(attention: '{"field":"x"}')
      result = c.evaluate(synapse_id: synapse.id, payload: {})
      expect(conditioner).to have_received(:evaluate)
      expect(result[:passed]).to be true
    end

    it 'uses injected transformer_client' do
      transformer = double('TransformerClient')
      allow(transformer).to receive(:transform).and_return({ success: true, result: { transformed: true } })
      c = described_class.new(transformer_client: transformer)
      synapse.update(transform: '{"template":"hello"}')
      result = c.evaluate(synapse_id: synapse.id, payload: {})
      expect(transformer).to have_received(:transform)
      expect(result[:success]).to be true
    end

    it 'returns error for nonexistent synapse' do
      result = client.evaluate(synapse_id: 99_999)
      expect(result[:success]).to be false
      expect(result[:error]).to eq('synapse not found')
    end
  end

  describe '#handle_pain' do
    let(:synapse) do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy:    'direct',
        confidence:          0.7,
        baseline_throughput: 1.0,
        origin:              'explicit',
        status:              'active',
        version:             1
      )
    end

    it 'works through the client' do
      result = client.handle_pain(synapse_id: synapse.id)
      expect(result[:success]).to be true
    end

    it 'reduces confidence' do
      original = synapse.confidence
      client.handle_pain(synapse_id: synapse.id)
      synapse.reload
      expect(synapse.confidence).to be < original
    end
  end

  describe '#crystallize' do
    it 'works through the client' do
      result = client.crystallize(signal_pairs: [])
      expect(result[:success]).to be true
      expect(result[:created]).to eq([])
    end

    it 'creates emergent synapses above threshold' do
      pair = { source_function_id: 1, target_function_id: 2, count: 25 }
      result = client.crystallize(signal_pairs: [pair])
      expect(result[:count]).to eq(1)
      expect(result[:created].first[:source]).to eq(1)
    end
  end

  describe '#mutate' do
    let(:synapse) do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy:    'direct',
        confidence:          0.7,
        baseline_throughput: 1.0,
        origin:              'explicit',
        status:              'active',
        version:             1
      )
    end

    it 'works through the client' do
      result = client.mutate(synapse_id: synapse.id, mutation_type: 'confidence_changed',
                             changes: { confidence: 0.9 }, trigger: 'manual')
      expect(result[:success]).to be true
    end
  end

  describe '#revert' do
    let(:synapse) do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy:    'direct',
        confidence:          0.7,
        baseline_throughput: 1.0,
        origin:              'explicit',
        status:              'active',
        version:             1
      )
    end

    it 'works through client after a mutate' do
      client.mutate(synapse_id: synapse.id, mutation_type: 'confidence_changed',
                    changes: { confidence: 0.9 }, trigger: 'manual')
      synapse.reload
      result = client.revert(synapse_id: synapse.id)
      expect(result[:success]).to be true
      expect(result[:reverted_to]).to eq(1)
    end
  end

  describe '#report' do
    let(:synapse) do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy:    'direct',
        confidence:          0.7,
        baseline_throughput: 1.0,
        origin:              'explicit',
        status:              'active',
        version:             1
      )
    end

    it 'works through the client' do
      result = client.report(synapse_id: synapse.id)
      expect(result[:success]).to be true
      expect(result[:synapse_id]).to eq(synapse.id)
    end
  end

  describe '#proposals' do
    let!(:synapse) { client.create(source_function_id: 1, target_function_id: 2) }

    before do
      synapse.update(confidence: 0.85)
      Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: synapse.id, proposal_type: 'llm_transform', trigger: 'reactive',
        status: 'pending', inputs: '{}', output: '{}', rationale: 'test'
      )
      Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: synapse.id, proposal_type: 'attention_mutation', trigger: 'proactive',
        status: 'approved', inputs: '{}', output: '{}', rationale: 'test2'
      )
    end

    it 'returns all proposals for a synapse' do
      result = client.proposals(synapse_id: synapse.id)
      expect(result.size).to eq(2)
    end

    it 'filters by status' do
      result = client.proposals(synapse_id: synapse.id, status: 'pending')
      expect(result.size).to eq(1)
      expect(result.first.proposal_type).to eq('llm_transform')
    end

    it 'returns empty array when no proposals match' do
      result = client.proposals(synapse_id: synapse.id, status: 'rejected')
      expect(result).to be_empty
    end
  end

  describe '#review_proposal' do
    let!(:synapse) { client.create(source_function_id: 1, target_function_id: 2) }
    let!(:proposal) do
      Legion::Extensions::Synapse::Data::Model::SynapseProposal.create(
        synapse_id: synapse.id, proposal_type: 'llm_transform', trigger: 'reactive',
        status: 'pending', inputs: '{}', output: '{}', rationale: 'test'
      )
    end

    it 'updates the proposal status' do
      result = client.review_proposal(proposal_id: proposal.id, status: 'approved')
      expect(result[:success]).to be true
      proposal.reload
      expect(proposal.status).to eq('approved')
    end

    it 'sets reviewed_at timestamp' do
      client.review_proposal(proposal_id: proposal.id, status: 'rejected')
      proposal.reload
      expect(proposal.reviewed_at).not_to be_nil
    end

    it 'returns error for invalid status' do
      result = client.review_proposal(proposal_id: proposal.id, status: 'invalid')
      expect(result[:success]).to be false
      expect(result[:error]).to include('invalid status')
    end

    it 'returns error for nonexistent proposal' do
      result = client.review_proposal(proposal_id: 99_999, status: 'approved')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('proposal not found')
    end
  end
end
