# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/blast_radius'

RSpec.describe Legion::Extensions::Synapse::Runners::BlastRadius do
  let(:test_class) { Class.new { include Legion::Extensions::Synapse::Runners::BlastRadius } }
  let(:runner) { test_class.new }

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    allow(Legion::Settings).to receive(:dig).with(:data, :connected).and_return(true)

    Legion::Extensions::Synapse::Data::Model.define_synapse_model
  end

  after do
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  def make_synapse(source_id: nil, target_id: nil, status: 'active', throughput: 1.0, confidence: 0.7)
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
      source_function_id:  source_id,
      target_function_id:  target_id,
      routing_strategy:    'direct',
      confidence:          confidence,
      baseline_throughput: throughput,
      origin:              'explicit',
      status:              status,
      version:             1
    )
  end

  describe '#compute' do
    context 'with no active synapses' do
      it 'returns success with zero updated count' do
        result = runner.compute
        expect(result[:success]).to be true
        expect(result[:updated]).to eq(0)
      end
    end

    context 'with a disconnected synapse (no source/target)' do
      let!(:synapse) { make_synapse }

      it 'assigns LOW tier to disconnected synapse' do
        runner.compute
        synapse.refresh
        expect(synapse.blast_radius).to eq('LOW')
      end

      it 'sets propagation_depth to 0' do
        runner.compute
        synapse.refresh
        expect(synapse.propagation_depth).to eq(0)
      end

      it 'sets downstream_count to 0' do
        runner.compute
        synapse.refresh
        expect(synapse.downstream_count).to eq(0)
      end

      it 'sets blast_radius_updated_at' do
        runner.compute
        synapse.refresh
        expect(synapse.blast_radius_updated_at).not_to be_nil
      end

      it 'counts updated synapse' do
        result = runner.compute
        expect(result[:updated]).to eq(1)
      end
    end

    context 'with a simple chain (depth 1, downstream 1)' do
      let!(:s1) { make_synapse(source_id: 100, target_id: 200) }
      let!(:s2) { make_synapse(source_id: 200, target_id: 300) }

      it 'assigns MED tier to the root synapse with depth > 1' do
        runner.compute
        s1.refresh
        # s1 source=100: can reach 200 (depth 1), then 300 (depth 2) => depth 2 > 1 => MED
        expect(s1.blast_radius).to eq('MED')
      end

      it 'assigns LOW tier to leaf synapse' do
        runner.compute
        s2.refresh
        # s2 source=200: reaches 300 (depth 1) only => depth 1, downstream 1, throughput 1 => LOW
        expect(s2.blast_radius).to eq('LOW')
      end
    end

    context 'propagation depth computation via BFS' do
      it 'computes depth correctly for a 3-level chain' do
        # 1 -> 2 -> 3 -> 4
        s1 = make_synapse(source_id: 1, target_id: 2)
        make_synapse(source_id: 2, target_id: 3)
        make_synapse(source_id: 3, target_id: 4)

        runner.compute
        s1.refresh
        # from 1: reach 2(d1), 3(d2), 4(d3) => max_depth=3, downstream=3
        expect(s1.propagation_depth).to eq(3)
        expect(s1.downstream_count).to eq(3)
      end

      it 'does not traverse inactive synapses as graph edges' do
        s_active = make_synapse(source_id: 10, target_id: 20)
        make_synapse(source_id: 20, target_id: 30, status: 'dampened')

        runner.compute
        s_active.refresh
        # inactive synapses are not in graph, so from 10 we reach 20 (d1) then stop
        expect(s_active.propagation_depth).to eq(1)
        expect(s_active.downstream_count).to eq(1)
      end
    end

    context 'tier classification' do
      it 'assigns CRITICAL for high throughput synapse' do
        s = make_synapse(source_id: 50, target_id: 51, throughput: 600.0)
        runner.compute
        s.refresh
        expect(s.blast_radius).to eq('CRITICAL')
      end

      it 'assigns HIGH for throughput > 100' do
        s = make_synapse(source_id: 60, target_id: 61, throughput: 150.0)
        runner.compute
        s.refresh
        expect(s.blast_radius).to eq('HIGH')
      end
    end
  end

  describe '#classify_tier (via private send)' do
    it 'returns LOW for depth=0, downstream=0, throughput=0' do
      result = runner.send(:classify_tier, depth: 0, downstream: 0, throughput: 0.0)
      expect(result).to eq('LOW')
    end

    it 'returns LOW for depth=1, downstream=3, throughput=9' do
      result = runner.send(:classify_tier, depth: 1, downstream: 3, throughput: 9.0)
      expect(result).to eq('LOW')
    end

    it 'returns MED for depth=2' do
      result = runner.send(:classify_tier, depth: 2, downstream: 1, throughput: 0.0)
      expect(result).to eq('MED')
    end

    it 'returns MED for downstream=5' do
      result = runner.send(:classify_tier, depth: 0, downstream: 5, throughput: 0.0)
      expect(result).to eq('MED')
    end

    it 'returns HIGH for depth=4' do
      result = runner.send(:classify_tier, depth: 4, downstream: 0, throughput: 0.0)
      expect(result).to eq('HIGH')
    end

    it 'returns HIGH for downstream=15' do
      result = runner.send(:classify_tier, depth: 0, downstream: 15, throughput: 0.0)
      expect(result).to eq('HIGH')
    end

    it 'returns HIGH for throughput=200' do
      result = runner.send(:classify_tier, depth: 0, downstream: 0, throughput: 200.0)
      expect(result).to eq('HIGH')
    end

    it 'returns CRITICAL for depth=6' do
      result = runner.send(:classify_tier, depth: 6, downstream: 0, throughput: 0.0)
      expect(result).to eq('CRITICAL')
    end

    it 'returns CRITICAL for downstream=30' do
      result = runner.send(:classify_tier, depth: 0, downstream: 30, throughput: 0.0)
      expect(result).to eq('CRITICAL')
    end

    it 'returns CRITICAL for throughput=600' do
      result = runner.send(:classify_tier, depth: 0, downstream: 0, throughput: 600.0)
      expect(result).to eq('CRITICAL')
    end
  end

  describe '#blast_multiplier_for' do
    it 'returns 1.0 for LOW' do
      expect(runner.blast_multiplier_for('LOW')).to eq(1.0)
    end

    it 'returns 1.5 for MED' do
      expect(runner.blast_multiplier_for('MED')).to eq(1.5)
    end

    it 'returns 2.0 for HIGH' do
      expect(runner.blast_multiplier_for('HIGH')).to eq(2.0)
    end

    it 'returns 3.0 for CRITICAL' do
      expect(runner.blast_multiplier_for('CRITICAL')).to eq(3.0)
    end

    it 'returns 1.0 for unknown tier' do
      expect(runner.blast_multiplier_for('unknown')).to eq(1.0)
    end

    it 'is case-insensitive' do
      expect(runner.blast_multiplier_for('critical')).to eq(3.0)
    end
  end

  describe '#requires_llm_review?' do
    it 'returns false for LOW' do
      expect(runner.requires_llm_review?('LOW')).to be false
    end

    it 'returns false for MED' do
      expect(runner.requires_llm_review?('MED')).to be false
    end

    it 'returns true for HIGH' do
      expect(runner.requires_llm_review?('HIGH')).to be true
    end

    it 'returns true for CRITICAL' do
      expect(runner.requires_llm_review?('CRITICAL')).to be true
    end

    it 'is case-insensitive' do
      expect(runner.requires_llm_review?('high')).to be true
    end
  end

  describe '#blast_tier' do
    let!(:synapse) { make_synapse }

    before do
      synapse.update(blast_radius: 'HIGH')
    end

    it 'returns the blast_radius tier for a known synapse' do
      expect(runner.blast_tier(synapse_id: synapse.id)).to eq('HIGH')
    end

    it 'returns nil for unknown synapse' do
      expect(runner.blast_tier(synapse_id: 99_999)).to be_nil
    end
  end
end
