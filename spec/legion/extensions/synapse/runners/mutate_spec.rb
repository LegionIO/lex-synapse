# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/mutate'

RSpec.describe Legion::Extensions::Synapse::Runners::Mutate do
  subject(:mutator) { Object.new.extend(described_class) }

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
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.where(synapse_id: synapse.id).delete
    synapse.delete
  end

  describe '#mutate' do
    context 'with nonexistent synapse' do
      it 'returns error' do
        result = mutator.mutate(synapse_id: 99_999, mutation_type: 'confidence_changed',
                                changes: { confidence: 0.8 }, trigger: 'manual')
        expect(result[:success]).to be false
        expect(result[:error]).to eq('synapse not found')
      end
    end

    context 'with invalid mutation_type' do
      it 'returns error' do
        result = mutator.mutate(synapse_id: synapse.id, mutation_type: 'invalid_type',
                                changes: {}, trigger: 'manual')
        expect(result[:success]).to be false
        expect(result[:error]).to include('invalid mutation_type')
      end
    end

    context 'with invalid trigger' do
      it 'returns error' do
        result = mutator.mutate(synapse_id: synapse.id, mutation_type: 'confidence_changed',
                                changes: { confidence: 0.8 }, trigger: 'unknown')
        expect(result[:success]).to be false
        expect(result[:error]).to include('invalid trigger')
      end
    end

    context 'with valid attention_adjusted mutation' do
      let(:attention_json) { '{"field":"value"}' }

      it 'applies attention changes' do
        mutator.mutate(synapse_id: synapse.id, mutation_type: 'attention_adjusted',
                       changes: { attention: attention_json }, trigger: 'manual')
        synapse.reload
        expect(synapse.attention).to eq(attention_json)
      end

      it 'increments synapse version' do
        mutator.mutate(synapse_id: synapse.id, mutation_type: 'attention_adjusted',
                       changes: { attention: attention_json }, trigger: 'manual')
        synapse.reload
        expect(synapse.version).to eq(2)
      end

      it 'creates mutation record' do
        expect do
          mutator.mutate(synapse_id: synapse.id, mutation_type: 'attention_adjusted',
                         changes: { attention: attention_json }, trigger: 'manual')
        end.to change { Legion::Extensions::Synapse::Data::Model::SynapseMutation.where(synapse_id: synapse.id).count }.by(1)
      end

      it 'stores before and after state in mutation record' do
        mutator.mutate(synapse_id: synapse.id, mutation_type: 'attention_adjusted',
                       changes: { attention: attention_json }, trigger: 'manual')
        mutation = Legion::Extensions::Synapse::Data::Model::SynapseMutation.where(synapse_id: synapse.id).first
        before_state = Legion::JSON.load(mutation.before_state)
        after_state = Legion::JSON.load(mutation.after_state)
        expect(before_state[:attention]).to be_nil
        expect(after_state[:attention]).to eq(attention_json)
      end

      it 'returns success with new version' do
        result = mutator.mutate(synapse_id: synapse.id, mutation_type: 'attention_adjusted',
                                changes: { attention: attention_json }, trigger: 'manual')
        expect(result[:success]).to be true
        expect(result[:version]).to eq(2)
      end
    end

    context 'with transform_adjusted mutation' do
      let(:transform_json) { '{"template":"hello"}' }

      it 'applies transform changes' do
        mutator.mutate(synapse_id: synapse.id, mutation_type: 'transform_adjusted',
                       changes: { transform: transform_json }, trigger: 'hebbian')
        synapse.reload
        expect(synapse.transform).to eq(transform_json)
      end
    end

    context 'with route_changed mutation' do
      it 'applies routing strategy changes' do
        mutator.mutate(synapse_id: synapse.id, mutation_type: 'route_changed',
                       changes: { routing_strategy: 'weighted' }, trigger: 'gaia')
        synapse.reload
        expect(synapse.routing_strategy).to eq('weighted')
      end
    end

    context 'with confidence_changed mutation' do
      it 'applies confidence changes' do
        mutator.mutate(synapse_id: synapse.id, mutation_type: 'confidence_changed',
                       changes: { confidence: 0.9 }, trigger: 'dream')
        synapse.reload
        expect(synapse.confidence).to eq(0.9)
      end
    end
  end
end
