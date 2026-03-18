# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/promote'

RSpec.describe Legion::Extensions::Synapse::Runners::Promote do
  subject(:promoter) { Object.new.extend(described_class) }

  def make_synapse(confidence: 0.95, status: 'active', origin: 'explicit')
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
      source_function_id:  10,
      target_function_id:  20,
      routing_strategy:    'direct',
      confidence:          confidence,
      baseline_throughput: 1.0,
      origin:              origin,
      status:              status,
      version:             1
    )
  end

  after(:each) do
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  describe '#promote' do
    context 'with no promotable synapses' do
      it 'returns success true' do
        result = promoter.promote
        expect(result[:success]).to be true
      end

      it 'returns empty promoted list' do
        result = promoter.promote
        expect(result[:promoted]).to eq([])
        expect(result[:count]).to eq(0)
      end
    end

    context 'with a high-confidence active synapse' do
      let(:synapse) { make_synapse(confidence: 0.95) }

      before { synapse }

      it 'promotes the synapse' do
        result = promoter.promote
        expect(result[:count]).to eq(1)
      end

      it 'builds correct knowledge entry format' do
        result = promoter.promote
        entry = result[:promoted].first
        expect(entry[:content_type]).to eq('synapse_pattern')
        expect(entry[:source_agent]).to eq('lex-synapse')
        expect(entry[:synapse_id]).to eq(synapse.id)
        expect(entry[:tags]).to include('synapse')
      end

      it 'includes routing_strategy in tags' do
        result = promoter.promote
        expect(result[:promoted].first[:tags]).to include('route:direct')
      end

      it 'includes origin in tags' do
        result = promoter.promote
        expect(result[:promoted].first[:tags]).to include('origin:explicit')
      end

      it 'content is a JSON string' do
        result = promoter.promote
        content = result[:promoted].first[:content]
        parsed = Legion::JSON.load(content)
        expect(parsed[:confidence]).to eq(0.95)
        expect(parsed[:routing_strategy]).to eq('direct')
      end
    end

    context 'with a low-confidence synapse' do
      before { make_synapse(confidence: 0.5) }

      it 'skips low-confidence synapses' do
        result = promoter.promote
        expect(result[:count]).to eq(0)
      end
    end

    context 'with a dampened synapse' do
      before { make_synapse(confidence: 0.95, status: 'dampened') }

      it 'skips non-active synapses' do
        result = promoter.promote
        expect(result[:count]).to eq(0)
      end
    end

    context 'with a synapse that has recent reverts' do
      let(:synapse) { make_synapse(confidence: 0.95) }

      before do
        synapse
        Legion::Extensions::Synapse::Data::Model::SynapseMutation.create(
          synapse_id:    synapse.id,
          version:       2,
          mutation_type: 'confidence_changed',
          trigger:       'manual',
          outcome:       'reverted'
        )
      end

      it 'skips synapse with recent reverts' do
        result = promoter.promote
        expect(result[:count]).to eq(0)
      end
    end

    context 'promote by specific synapse_id' do
      let(:synapse) { make_synapse(confidence: 0.95) }

      it 'promotes when given a valid synapse_id' do
        result = promoter.promote(synapse_id: synapse.id)
        expect(result[:count]).to eq(1)
        expect(result[:promoted].first[:synapse_id]).to eq(synapse.id)
      end

      it 'returns empty for nonexistent synapse_id' do
        result = promoter.promote(synapse_id: 99_999)
        expect(result[:count]).to eq(0)
      end

      it 'returns empty when synapse_id references a low-confidence synapse' do
        low = make_synapse(confidence: 0.5)
        result = promoter.promote(synapse_id: low.id)
        expect(result[:count]).to eq(0)
      end
    end

    context 'with multiple synapses, some promotable' do
      before do
        make_synapse(confidence: 0.95)
        make_synapse(confidence: 0.3)
        make_synapse(confidence: 0.92, status: 'dampened')
      end

      it 'promotes only high-confidence active synapses' do
        result = promoter.promote
        expect(result[:count]).to eq(1)
      end
    end
  end
end
