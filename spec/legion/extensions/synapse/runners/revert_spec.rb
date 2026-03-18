# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/mutate'
require_relative '../../../../../lib/legion/extensions/synapse/runners/revert'

RSpec.describe Legion::Extensions::Synapse::Runners::Revert do
  subject(:reverter) { Object.new.extend(described_class) }

  let(:mutator) { Object.new.extend(Legion::Extensions::Synapse::Runners::Mutate) }

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

  describe '#revert' do
    context 'with nonexistent synapse' do
      it 'returns error' do
        result = reverter.revert(synapse_id: 99_999)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('synapse not found')
      end
    end

    context 'with no previous version' do
      it 'returns error when version is 1 and to_version is nil' do
        result = reverter.revert(synapse_id: synapse.id)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('no previous version')
      end
    end

    context 'with a prior mutation' do
      before do
        mutator.mutate(
          synapse_id:    synapse.id,
          mutation_type: 'confidence_changed',
          changes:       { confidence: 0.9 },
          trigger:       'manual'
        )
        synapse.reload
      end

      # to_version is the mutation version to look up; reverted_to is one less (the restored version)
      it 'reverts to the restored version when to_version specifies the mutation version' do
        result = reverter.revert(synapse_id: synapse.id, to_version: 2)
        expect(result[:success]).to be true
        expect(result[:reverted_to]).to eq(1)
      end

      it 'reverts to previous version by default' do
        # synapse.version == 2 after mutate; default looks up mutation at version 2, restores to version 1
        result = reverter.revert(synapse_id: synapse.id)
        expect(result[:success]).to be true
        expect(result[:reverted_to]).to eq(synapse.version - 1)
      end

      it 'restores before_state from mutation record' do
        original_confidence = 0.7
        reverter.revert(synapse_id: synapse.id, to_version: 2)
        synapse.reload
        expect(synapse.confidence).to eq(original_confidence)
      end

      it 'marks mutation as reverted' do
        reverter.revert(synapse_id: synapse.id, to_version: 2)
        mutation = Legion::Extensions::Synapse::Data::Model::SynapseMutation.where(
          synapse_id: synapse.id,
          version:    2
        ).first
        expect(mutation.outcome).to eq('reverted')
      end

      it 'creates a revert mutation record' do
        expect do
          reverter.revert(synapse_id: synapse.id, to_version: 2)
        end.to change { Legion::Extensions::Synapse::Data::Model::SynapseMutation.where(synapse_id: synapse.id).count }.by(1)
      end

      it 'returns synapse_id' do
        result = reverter.revert(synapse_id: synapse.id, to_version: 2)
        expect(result[:synapse_id]).to eq(synapse.id)
      end
    end

    context 'when mutation version does not exist' do
      it 'returns error' do
        result = reverter.revert(synapse_id: synapse.id, to_version: 5)
        expect(result[:success]).to be false
        expect(result[:error]).to include('mutation version')
        expect(result[:error]).to include('not found')
      end
    end
  end
end
