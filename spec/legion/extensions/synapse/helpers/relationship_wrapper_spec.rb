# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/helpers/relationship_wrapper'

RSpec.describe Legion::Extensions::Synapse::Helpers::RelationshipWrapper do
  after(:each) do
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  let(:relationship) do
    {
      id:                  42,
      trigger_function_id: 10,
      function_id:         20,
      conditions:          '{"field":"x"}',
      transformation:      '{"template":"y"}'
    }
  end

  describe '.wrap' do
    it 'creates a synapse from the relationship hash' do
      synapse = described_class.wrap(relationship)
      expect(synapse).not_to be_nil
      expect(synapse.id).not_to be_nil
    end

    it 'maps trigger_function_id to source_function_id' do
      synapse = described_class.wrap(relationship)
      expect(synapse.source_function_id).to eq(10)
    end

    it 'maps function_id to target_function_id' do
      synapse = described_class.wrap(relationship)
      expect(synapse.target_function_id).to eq(20)
    end

    it 'sets relationship_id from relationship[:id]' do
      synapse = described_class.wrap(relationship)
      expect(synapse.relationship_id).to eq(42)
    end

    it 'sets attention from relationship conditions' do
      synapse = described_class.wrap(relationship)
      expect(synapse.attention).to eq('{"field":"x"}')
    end

    it 'sets transform from relationship transformation' do
      synapse = described_class.wrap(relationship)
      expect(synapse.transform).to eq('{"template":"y"}')
    end

    it 'sets origin to explicit' do
      synapse = described_class.wrap(relationship)
      expect(synapse.origin).to eq('explicit')
    end

    it 'sets confidence to 0.7 (explicit starting score)' do
      synapse = described_class.wrap(relationship)
      expect(synapse.confidence).to eq(0.7)
    end

    it 'sets status to active' do
      synapse = described_class.wrap(relationship)
      expect(synapse.status).to eq('active')
    end

    it 'returns existing synapse if already wrapped' do
      first  = described_class.wrap(relationship)
      second = described_class.wrap(relationship)
      expect(second.id).to eq(first.id)
    end

    it 'does not create a duplicate when wrapping again' do
      described_class.wrap(relationship)
      expect do
        described_class.wrap(relationship)
      end.not_to(change { Legion::Extensions::Synapse::Data::Model::Synapse.count })
    end
  end

  describe '.unwrap' do
    context 'with a wrapped synapse' do
      let(:synapse) { described_class.wrap(relationship) }

      before { synapse }

      it 'destroys the synapse' do
        expect do
          described_class.unwrap(synapse.id)
        end.to change { Legion::Extensions::Synapse::Data::Model::Synapse.count }.by(-1)
      end

      it 'returns success true' do
        result = described_class.unwrap(synapse.id)
        expect(result[:success]).to be true
      end

      it 'returns the relationship_id' do
        result = described_class.unwrap(synapse.id)
        expect(result[:relationship_id]).to eq(42)
      end
    end

    context 'with a nonexistent synapse' do
      it 'returns error for nonexistent synapse' do
        result = described_class.unwrap(99_999)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('synapse not found')
      end
    end

    context 'with a synapse that has no relationship_id' do
      let(:plain_synapse) do
        Legion::Extensions::Synapse::Data::Model::Synapse.create(
          routing_strategy:    'direct',
          confidence:          0.7,
          baseline_throughput: 1.0,
          origin:              'explicit',
          status:              'active',
          version:             1
        )
      end

      before { plain_synapse }

      it 'returns error for synapse without relationship_id' do
        result = described_class.unwrap(plain_synapse.id)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('not a wrapped relationship')
      end
    end
  end
end
