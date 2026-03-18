# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/evaluate'

RSpec.describe Legion::Extensions::Synapse::Runners::Evaluate do
  subject(:evaluator) { Object.new.extend(described_class) }

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

  let(:conditioner_client) { double('ConditionerClient') }
  let(:transformer_client) { double('TransformerClient') }

  before do
    allow(conditioner_client).to receive(:evaluate).and_return({ valid: true, explanation: {} })
    allow(transformer_client).to receive(:transform).and_return({ success: true, result: { key: 'value' } })
  end

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse.id).delete
    synapse.delete
  end

  describe '#evaluate' do
    context 'with no attention or transform rules' do
      it 'returns success' do
        result = evaluator.evaluate(synapse_id: synapse.id, payload: { foo: 'bar' })
        expect(result[:success]).to be true
      end

      it 'passes attention' do
        result = evaluator.evaluate(synapse_id: synapse.id, payload: { foo: 'bar' })
        expect(result[:passed]).to be true
      end

      it 'records a signal' do
        expect do
          evaluator.evaluate(synapse_id: synapse.id, payload: { foo: 'bar' })
        end.to change { Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse.id).count }.by(1)
      end

      it 'adjusts confidence upward on success' do
        original = synapse.confidence
        evaluator.evaluate(synapse_id: synapse.id, payload: { foo: 'bar' })
        synapse.reload
        expect(synapse.confidence).to be > original
      end

      it 'includes latency_ms in result' do
        result = evaluator.evaluate(synapse_id: synapse.id, payload: {})
        expect(result[:latency_ms]).to be_a(Numeric)
      end
    end

    context 'with attention rules and conditioner client' do
      before { synapse.update(attention: '{"field":"value"}') }

      it 'passes when conditioner returns valid: true' do
        allow(conditioner_client).to receive(:evaluate).and_return({ valid: true, explanation: {} })
        result = evaluator.evaluate(synapse_id: synapse.id, payload: {}, conditioner_client: conditioner_client)
        expect(result[:passed]).to be true
      end

      it 'suppresses signal when conditioner returns valid: false in filter mode' do
        synapse.update(confidence: 0.5) # filter mode: 0.3..0.6
        allow(conditioner_client).to receive(:evaluate).and_return({ valid: false, explanation: {} })
        result = evaluator.evaluate(synapse_id: synapse.id, payload: {}, conditioner_client: conditioner_client)
        expect(result[:passed]).to be false
        expect(result[:success]).to be false
      end
    end

    context 'in OBSERVE mode' do
      before { synapse.update(confidence: 0.1, attention: '{"field":"value"}') } # observe mode: 0.0..0.3

      it 'always passes through even when conditioner returns false' do
        allow(conditioner_client).to receive(:evaluate).and_return({ valid: false, explanation: {} })
        result = evaluator.evaluate(synapse_id: synapse.id, payload: {}, conditioner_client: conditioner_client)
        expect(result[:passed]).to be true
        expect(result[:mode]).to eq(:observe)
      end
    end

    context 'with transform and transformer client' do
      before do
        synapse.update(confidence: 0.7, transform: '{"template":"hello"}')
        allow(transformer_client).to receive(:transform).and_return({ success: true, result: { transformed: true } })
      end

      it 'returns transformed result' do
        result = evaluator.evaluate(synapse_id: synapse.id, payload: { a: 1 }, transformer_client: transformer_client)
        expect(result[:result]).to eq({ transformed: true })
      end

      it 'returns success true' do
        result = evaluator.evaluate(synapse_id: synapse.id, payload: {}, transformer_client: transformer_client)
        expect(result[:success]).to be true
      end
    end

    context 'when transform validation fails' do
      before do
        synapse.update(confidence: 0.7, transform: '{"template":"bad"}')
        allow(transformer_client).to receive(:transform).and_return({ success: false, errors: ['schema mismatch'] })
      end

      it 'returns success false' do
        result = evaluator.evaluate(synapse_id: synapse.id, payload: {}, transformer_client: transformer_client)
        expect(result[:success]).to be false
      end

      it 'adjusts confidence downward' do
        original = synapse.confidence
        evaluator.evaluate(synapse_id: synapse.id, payload: {}, transformer_client: transformer_client)
        synapse.reload
        expect(synapse.confidence).to be < original
      end
    end

    context 'with nonexistent synapse' do
      it 'returns error' do
        result = evaluator.evaluate(synapse_id: 99_999)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('synapse not found')
      end
    end

    context 'with inactive synapse' do
      before { synapse.update(status: 'dampened') }

      it 'returns error' do
        result = evaluator.evaluate(synapse_id: synapse.id)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('synapse not active')
      end
    end
  end
end
