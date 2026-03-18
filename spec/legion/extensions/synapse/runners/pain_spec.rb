# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/pain'

RSpec.describe Legion::Extensions::Synapse::Runners::Pain do
  subject(:handler) { Object.new.extend(described_class) }

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

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse.id).delete
    synapse.delete
  end

  describe '#handle_pain' do
    it 'returns error for nonexistent synapse' do
      result = handler.handle_pain(synapse_id: 99_999)
      expect(result[:success]).to be false
      expect(result[:error]).to eq('synapse not found')
    end

    it 'records a failed signal' do
      expect do
        handler.handle_pain(synapse_id: synapse.id)
      end.to change { Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse.id).count }.by(1)

      signal = Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse.id).first
      expect(signal.downstream_outcome).to eq('failed')
    end

    it 'records signal with task_id when provided' do
      handler.handle_pain(synapse_id: synapse.id, task_id: 42)
      signal = Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse.id).first
      expect(signal.task_id).to eq(42)
    end

    it 'adjusts confidence down on failure' do
      original = synapse.confidence
      handler.handle_pain(synapse_id: synapse.id)
      synapse.reload
      expect(synapse.confidence).to be < original
    end

    it 'returns the new confidence' do
      result = handler.handle_pain(synapse_id: synapse.id)
      synapse.reload
      expect(result[:confidence]).to eq(synapse.confidence)
    end

    it 'returns consecutive failure count' do
      result = handler.handle_pain(synapse_id: synapse.id)
      expect(result[:consecutive_failures]).to eq(1)
    end

    it 'returns current autonomy mode' do
      result = handler.handle_pain(synapse_id: synapse.id)
      expect(result[:mode]).to be_a(Symbol)
    end

    context 'with 3 consecutive failures' do
      before do
        3.times do
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id:         synapse.id,
            passed_attention:   true,
            transform_success:  true,
            downstream_outcome: 'failed'
          )
        end
      end

      it 'triggers auto_revert' do
        result = handler.handle_pain(synapse_id: synapse.id)
        expect(result[:action]).to eq(:auto_revert)
        expect(result[:reverted]).to be true
      end
    end

    context 'when failure rate is extreme' do
      before do
        # More than baseline_signals * 2 failures in last 5 minutes
        # baseline_throughput=1.0, baseline_signals=max(5,5)=5, threshold=10
        11.times do
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id:         synapse.id,
            passed_attention:   true,
            transform_success:  true,
            downstream_outcome: 'failed'
          )
        end
      end

      it 'dampens the synapse' do
        result = handler.handle_pain(synapse_id: synapse.id)
        expect(result[:dampened]).to be true
        synapse.reload
        expect(synapse.status).to eq('dampened')
      end
    end
  end
end
