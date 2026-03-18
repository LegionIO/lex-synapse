# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/crystallize'

RSpec.describe Legion::Extensions::Synapse::Runners::Crystallize do
  subject(:crystallizer) { Object.new.extend(described_class) }

  after do
    Legion::Extensions::Synapse::Data::Model::Synapse.where(origin: 'emergent').delete
  end

  describe '#crystallize' do
    context 'with empty input' do
      it 'returns success with zero count' do
        result = crystallizer.crystallize(signal_pairs: [])
        expect(result[:success]).to be true
        expect(result[:count]).to eq(0)
        expect(result[:created]).to be_empty
      end
    end

    context 'with pairs below threshold' do
      let(:pairs) { [{ source_function_id: 101, target_function_id: 202, count: 5 }] }

      it 'skips pairs below threshold' do
        result = crystallizer.crystallize(signal_pairs: pairs, threshold: 20)
        expect(result[:count]).to eq(0)
      end
    end

    context 'with pairs meeting threshold' do
      let(:pairs) { [{ source_function_id: 201, target_function_id: 301, count: 25 }] }

      after do
        Legion::Extensions::Synapse::Data::Model::Synapse.where(
          source_function_id: 201, target_function_id: 301
        ).delete
      end

      it 'creates emergent synapse' do
        result = crystallizer.crystallize(signal_pairs: pairs, threshold: 20)
        expect(result[:count]).to eq(1)
        expect(result[:created].first[:source]).to eq(201)
        expect(result[:created].first[:target]).to eq(301)
      end

      it 'sets origin to emergent' do
        crystallizer.crystallize(signal_pairs: pairs, threshold: 20)
        synapse = Legion::Extensions::Synapse::Data::Model::Synapse.where(
          source_function_id: 201, target_function_id: 301
        ).first
        expect(synapse.origin).to eq('emergent')
      end

      it 'sets status to observing' do
        crystallizer.crystallize(signal_pairs: pairs, threshold: 20)
        synapse = Legion::Extensions::Synapse::Data::Model::Synapse.where(
          source_function_id: 201, target_function_id: 301
        ).first
        expect(synapse.status).to eq('observing')
      end

      it 'sets confidence to 0.3 (emergent starting score)' do
        crystallizer.crystallize(signal_pairs: pairs, threshold: 20)
        synapse = Legion::Extensions::Synapse::Data::Model::Synapse.where(
          source_function_id: 201, target_function_id: 301
        ).first
        expect(synapse.confidence).to eq(0.3)
      end
    end

    context 'when synapse already exists' do
      let(:pairs) { [{ source_function_id: 401, target_function_id: 501, count: 30 }] }

      let!(:existing) do
        Legion::Extensions::Synapse::Data::Model::Synapse.create(
          source_function_id:  401,
          target_function_id:  501,
          routing_strategy:    'direct',
          confidence:          0.5,
          baseline_throughput: 0.0,
          origin:              'explicit',
          status:              'active',
          version:             1
        )
      end

      after { existing.delete }

      it 'skips duplicate synapses' do
        result = crystallizer.crystallize(signal_pairs: pairs, threshold: 20)
        expect(result[:count]).to eq(0)
      end
    end

    context 'with multiple pairs' do
      let(:pairs) do
        [
          { source_function_id: 601, target_function_id: 701, count: 25 },
          { source_function_id: 602, target_function_id: 702, count: 5 },
          { source_function_id: 603, target_function_id: 703, count: 30 }
        ]
      end

      after do
        Legion::Extensions::Synapse::Data::Model::Synapse.where(
          source_function_id: [601, 603]
        ).delete
      end

      it 'creates only pairs that meet threshold' do
        result = crystallizer.crystallize(signal_pairs: pairs, threshold: 20)
        expect(result[:count]).to eq(2)
      end
    end
  end
end
