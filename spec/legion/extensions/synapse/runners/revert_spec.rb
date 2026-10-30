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

      it 'allows mutation and reversion again after history has branched' do
        reverter.revert(synapse_id: synapse.id)
        synapse.refresh.update(confidence: 0.75)
        next_mutation = mutator.mutate(synapse_id: synapse.id, mutation_type: 'confidence_changed',
                                       changes: { confidence: 0.6 }, trigger: 'manual')

        expect(next_mutation[:success]).to be true
        expect(synapse.refresh.confidence).to eq(0.6)
        result = reverter.revert(synapse_id: synapse.id)

        expect(result).to include(success: true, reverted_to: 1)
        expect(synapse.refresh.confidence).to eq(0.75)
        versions = synapse.mutations_dataset.order(:version).select_map(:version)
        expect(versions).to eq([2, 3, 4, 5])
      end

      it 'records the actual state being reverted rather than a stale mutation snapshot' do
        synapse.update(confidence: 0.4)
        reverter.revert(synapse_id: synapse.id)
        audit = synapse.mutations_dataset.order(Sequel.desc(:id)).first

        expect(Legion::JSON.load(audit.before_state)[:confidence]).to eq(0.4)
        expect(Legion::JSON.load(audit.after_state)[:confidence]).to eq(0.7)
      end

      it 'rolls back restored state and outcome if the revert history cannot be saved' do
        allow(Legion::Extensions::Synapse::Data::Model::SynapseMutation).to receive(:create).and_raise(Sequel::DatabaseError, 'write failed')

        expect { reverter.revert(synapse_id: synapse.id) }.to raise_error(Sequel::DatabaseError)

        expect(synapse.refresh.confidence).to eq(0.9)
        expect(synapse.version).to eq(2)
        expect(synapse.mutations_dataset.first.outcome).not_to eq('reverted')
        expect(synapse.mutations_dataset.count).to eq(1)
      end

      # to_version identifies the mutation whose before_state should be restored.
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
