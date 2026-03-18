# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/gaia_report'

RSpec.describe Legion::Extensions::Synapse::Runners::GaiaReport do
  subject(:reporter) { Object.new.extend(described_class) }

  def make_synapse(status: 'active', confidence: 0.7, origin: 'explicit')
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
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

  describe '#gaia_summary' do
    context 'with no synapses' do
      it 'returns success true' do
        result = reporter.gaia_summary
        expect(result[:success]).to be true
      end

      it 'returns zero counts' do
        result = reporter.gaia_summary
        expect(result[:total_synapses]).to eq(0)
        expect(result[:active_count]).to eq(0)
        expect(result[:dampened_count]).to eq(0)
        expect(result[:observing_count]).to eq(0)
      end

      it 'returns zero avg_confidence' do
        result = reporter.gaia_summary
        expect(result[:avg_confidence]).to eq(0.0)
      end

      it 'returns zero elevated_pain_count' do
        result = reporter.gaia_summary
        expect(result[:elevated_pain_count]).to eq(0)
      end

      it 'returns health_score of 1.0 when no synapses' do
        result = reporter.gaia_summary
        expect(result[:health_score]).to eq(1.0)
      end
    end

    context 'with mixed status synapses' do
      before do
        make_synapse(status: 'active', confidence: 0.8)
        make_synapse(status: 'active', confidence: 0.6)
        make_synapse(status: 'dampened', confidence: 0.4)
        make_synapse(status: 'observing', confidence: 0.3)
      end

      it 'returns correct total_synapses count' do
        result = reporter.gaia_summary
        expect(result[:total_synapses]).to eq(4)
      end

      it 'returns correct active_count' do
        result = reporter.gaia_summary
        expect(result[:active_count]).to eq(2)
      end

      it 'returns correct dampened_count' do
        result = reporter.gaia_summary
        expect(result[:dampened_count]).to eq(1)
      end

      it 'returns correct observing_count' do
        result = reporter.gaia_summary
        expect(result[:observing_count]).to eq(1)
      end

      it 'returns emergent_candidates equal to observing_count' do
        result = reporter.gaia_summary
        expect(result[:emergent_candidates]).to eq(1)
      end

      it 'calculates avg_confidence over active synapses only' do
        result = reporter.gaia_summary
        expect(result[:avg_confidence]).to eq(0.7)
      end
    end

    context 'elevated pain detection' do
      before do
        make_synapse(status: 'active', confidence: 0.2)
        make_synapse(status: 'active', confidence: 0.8)
      end

      it 'counts active synapses with confidence < 0.3 as elevated pain' do
        result = reporter.gaia_summary
        expect(result[:elevated_pain_count]).to eq(1)
      end
    end

    context 'health_score computation' do
      before do
        make_synapse(status: 'active', confidence: 0.8)
        make_synapse(status: 'active', confidence: 0.8)
        make_synapse(status: 'dampened', confidence: 0.4)
      end

      it 'computes health_score as healthy_active / (active + dampened)' do
        result = reporter.gaia_summary
        # 2 active, 0 elevated pain, 1 dampened => 2/3
        expect(result[:health_score]).to eq(0.6667)
      end
    end

    context 'health_score with all active synapses in pain' do
      before do
        make_synapse(status: 'active', confidence: 0.1)
        make_synapse(status: 'active', confidence: 0.2)
      end

      it 'clamps health_score to 0.0' do
        result = reporter.gaia_summary
        expect(result[:health_score]).to eq(0.0)
      end
    end
  end

  describe '#gaia_reflection' do
    let(:synapse) { make_synapse }

    it 'returns success true' do
      result = reporter.gaia_reflection
      expect(result[:success]).to be true
    end

    it 'includes summary' do
      result = reporter.gaia_reflection
      expect(result[:summary]).to be_a(Hash)
      expect(result[:summary][:success]).to be true
    end

    it 'includes mutations_1h count' do
      result = reporter.gaia_reflection
      expect(result[:mutations_1h]).to be_a(Integer)
    end

    it 'includes mutation_types tally' do
      result = reporter.gaia_reflection
      expect(result[:mutation_types]).to be_a(Hash)
    end

    it 'includes mutation_triggers tally' do
      result = reporter.gaia_reflection
      expect(result[:mutation_triggers]).to be_a(Hash)
    end

    context 'with recent mutations' do
      before do
        2.times do
          Legion::Extensions::Synapse::Data::Model::SynapseMutation.create(
            synapse_id:    synapse.id,
            version:       2,
            mutation_type: 'confidence_changed',
            trigger:       'manual',
            outcome:       nil
          )
        end
        Legion::Extensions::Synapse::Data::Model::SynapseMutation.create(
          synapse_id:    synapse.id,
          version:       3,
          mutation_type: 'route_changed',
          trigger:       'gaia',
          outcome:       nil
        )
      end

      it 'counts recent mutations' do
        result = reporter.gaia_reflection
        expect(result[:mutations_1h]).to eq(3)
      end

      it 'tallies mutation types' do
        result = reporter.gaia_reflection
        expect(result[:mutation_types]['confidence_changed']).to eq(2)
        expect(result[:mutation_types]['route_changed']).to eq(1)
      end

      it 'tallies mutation triggers' do
        result = reporter.gaia_reflection
        expect(result[:mutation_triggers]['manual']).to eq(2)
        expect(result[:mutation_triggers]['gaia']).to eq(1)
      end
    end
  end
end
