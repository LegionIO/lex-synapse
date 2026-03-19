# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/proposals'
require_relative '../../../../../lib/legion/extensions/synapse/runners/propose'

RSpec.describe Legion::Extensions::Synapse::Runners::Propose do
  subject(:proposer) { Object.new.extend(described_class) }

  let(:transformer_client) { double('TransformerClient') }
  let(:synapse) do
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
      routing_strategy: 'direct', confidence: 0.85, baseline_throughput: 1.0,
      origin: 'explicit', status: 'active', version: 1
    )
  end
  let(:signal) do
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
      synapse_id: synapse.id, passed_attention: true, transform_success: true, latency_ms: 10
    )
  end

  before do
    allow(transformer_client).to receive(:transform).and_return(
      { success: true, result: { template: '{"mapped":"<%= input %>"}'} }
    )
    allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:reactive?).and_return(true)
    allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:llm_engine_options).and_return(
      { temperature: 0.3, max_tokens: 1024 }
    )
  end

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(synapse_id: synapse.id).delete
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse.id).delete
    synapse.delete
  end

  describe '#propose_reactive' do
    context 'when synapse has no transform template' do
      it 'creates an llm_transform proposal' do
        expect do
          proposer.propose_reactive(
            synapse: synapse, payload: { foo: 'bar' }, signal_id: signal.id,
            attention_result: { passed: true }, transform_result: { success: true, result: { foo: 'bar' } },
            transformer_client: transformer_client
          )
        end.to change { Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(synapse_id: synapse.id).count }.by(1)
      end

      it 'sets proposal_type to llm_transform' do
        proposer.propose_reactive(
          synapse: synapse, payload: { foo: 'bar' }, signal_id: signal.id,
          attention_result: { passed: true }, transform_result: { success: true, result: { foo: 'bar' } },
          transformer_client: transformer_client
        )
        proposal = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(synapse_id: synapse.id).first
        expect(proposal.proposal_type).to eq('llm_transform')
      end

      it 'sets trigger to reactive' do
        proposer.propose_reactive(
          synapse: synapse, payload: { foo: 'bar' }, signal_id: signal.id,
          attention_result: { passed: true }, transform_result: { success: true, result: { foo: 'bar' } },
          transformer_client: transformer_client
        )
        proposal = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(synapse_id: synapse.id).first
        expect(proposal.trigger).to eq('reactive')
      end

      it 'stores LLM output in the output field' do
        proposer.propose_reactive(
          synapse: synapse, payload: { foo: 'bar' }, signal_id: signal.id,
          attention_result: { passed: true }, transform_result: { success: true, result: { foo: 'bar' } },
          transformer_client: transformer_client
        )
        proposal = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(synapse_id: synapse.id).first
        expect(proposal.output).not_to be_nil
      end

      it 'links to the triggering signal' do
        proposer.propose_reactive(
          synapse: synapse, payload: { foo: 'bar' }, signal_id: signal.id,
          attention_result: { passed: true }, transform_result: { success: true, result: { foo: 'bar' } },
          transformer_client: transformer_client
        )
        proposal = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(synapse_id: synapse.id).first
        expect(proposal.signal_id).to eq(signal.id)
      end
    end

    context 'when transform failed' do
      before { synapse.update(transform: '{"template":"bad","engine":"erb"}') }

      it 'creates a transform_mutation proposal' do
        proposer.propose_reactive(
          synapse: synapse, payload: { foo: 'bar' }, signal_id: signal.id,
          attention_result: { passed: true },
          transform_result: { success: false, result: { foo: 'bar' }, error: ['schema mismatch'] },
          transformer_client: transformer_client
        )
        proposal = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(synapse_id: synapse.id).first
        expect(proposal.proposal_type).to eq('transform_mutation')
      end
    end

    context 'when attention passed but downstream failed (pain correlation)' do
      before do
        synapse.update(attention: '{"all":[{"fact":"status","operator":"equal","value":"open"}]}')
        3.times do
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id: synapse.id, passed_attention: true, transform_success: true,
            downstream_outcome: 'failed', latency_ms: 5
          )
        end
      end

      it 'creates an attention_mutation proposal' do
        proposer.propose_reactive(
          synapse: synapse, payload: { status: 'open' }, signal_id: signal.id,
          attention_result: { passed: true }, transform_result: { success: true, result: {} },
          transformer_client: transformer_client
        )
        proposals = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(
          synapse_id: synapse.id, proposal_type: 'attention_mutation'
        )
        expect(proposals.count).to be >= 1
      end
    end

    context 'when proposals are disabled' do
      before do
        allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:reactive?).and_return(false)
      end

      it 'creates no proposals' do
        expect do
          proposer.propose_reactive(
            synapse: synapse, payload: {}, signal_id: signal.id,
            attention_result: { passed: true }, transform_result: { success: true, result: {} },
            transformer_client: transformer_client
          )
        end.not_to(change { Legion::Extensions::Synapse::Data::Model::SynapseProposal.count })
      end
    end

    context 'when transformer_client is nil' do
      it 'skips LLM proposals gracefully' do
        result = proposer.propose_reactive(
          synapse: synapse, payload: {}, signal_id: signal.id,
          attention_result: { passed: true }, transform_result: { success: true, result: {} },
          transformer_client: nil
        )
        expect(result[:proposals]).to eq([])
      end
    end
  end

  describe '#propose_proactive' do
    before do
      allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:proactive?).and_return(true)
      allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:settings).and_return(
        Legion::Extensions::Synapse::Helpers::Proposals::DEFAULT_SETTINGS
      )
    end

    context 'with degraded success rate' do
      before do
        synapse.update(confidence: 0.85)
        12.times do |i|
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id: synapse.id, passed_attention: true,
            transform_success: i < 6, latency_ms: 5
          )
        end
      end

      it 'creates a transform_mutation proposal' do
        proposer.propose_proactive
        proposals = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(
          synapse_id: synapse.id, trigger: 'proactive'
        )
        expect(proposals.count).to be >= 1
      end

      it 'includes success rate in inputs' do
        proposer.propose_proactive
        proposal = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(
          synapse_id: synapse.id, trigger: 'proactive'
        ).first
        inputs = Legion::JSON.load(proposal.inputs)
        expect(inputs[:success_rate]).to be < 0.8
      end
    end

    context 'with healthy success rate' do
      before do
        synapse.update(confidence: 0.85)
        12.times do
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id: synapse.id, passed_attention: true, transform_success: true, latency_ms: 5
          )
        end
      end

      it 'creates no proposals' do
        expect do
          proposer.propose_proactive
        end.not_to(change { Legion::Extensions::Synapse::Data::Model::SynapseProposal.count })
      end
    end

    context 'with synapse below autonomous threshold' do
      before { synapse.update(confidence: 0.5) }

      it 'skips the synapse' do
        expect do
          proposer.propose_proactive
        end.not_to(change { Legion::Extensions::Synapse::Data::Model::SynapseProposal.count })
      end
    end

    context 'respects max_per_run' do
      before do
        allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:settings).and_return(
          Legion::Extensions::Synapse::Helpers::Proposals::DEFAULT_SETTINGS.merge(max_per_run: 1)
        )
        synapse.update(confidence: 0.85, transform: '{"template":"x"}')
        12.times do |i|
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id: synapse.id, passed_attention: true,
            transform_success: i < 4, latency_ms: 5
          )
        end
      end

      it 'creates at most max_per_run proposals per synapse' do
        proposer.propose_proactive
        proposals = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(
          synapse_id: synapse.id, trigger: 'proactive'
        )
        expect(proposals.count).to be <= 1
      end
    end

    context 'deduplicates pending proposals' do
      before do
        synapse.update(confidence: 0.85)
        12.times do |i|
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id: synapse.id, passed_attention: true,
            transform_success: i < 4, latency_ms: 5
          )
        end
      end

      it 'does not create duplicate proposals within window' do
        proposer.propose_proactive
        initial_count = Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(synapse_id: synapse.id).count
        proposer.propose_proactive
        expect(Legion::Extensions::Synapse::Data::Model::SynapseProposal.where(synapse_id: synapse.id).count).to eq(initial_count)
      end
    end

    context 'when proactive is disabled' do
      before do
        allow(Legion::Extensions::Synapse::Helpers::Proposals).to receive(:proactive?).and_return(false)
      end

      it 'returns empty proposals' do
        result = proposer.propose_proactive
        expect(result[:proposals]).to eq([])
      end
    end
  end
end
