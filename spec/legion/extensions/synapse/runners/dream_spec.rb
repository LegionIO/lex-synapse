# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/dream'

RSpec.describe Legion::Extensions::Synapse::Runners::Dream do
  subject(:dreamer) { Object.new.extend(described_class) }

  def make_synapse(version: 1, confidence: 0.7, origin: 'explicit')
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
      routing_strategy:    'direct',
      confidence:          confidence,
      baseline_throughput: 1.0,
      origin:              origin,
      status:              'active',
      version:             version
    )
  end

  def make_mutation(synapse, version: 2, mutation_type: 'confidence_changed', trigger: 'manual', outcome: nil)
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.create(
      synapse_id:    synapse.id,
      version:       version,
      mutation_type: mutation_type,
      trigger:       trigger,
      outcome:       outcome
    )
  end

  after(:each) do
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  describe '#dream_replay' do
    context 'with no synapses having mutations' do
      before { make_synapse(version: 1) }

      it 'returns success true' do
        result = dreamer.dream_replay
        expect(result[:success]).to be true
      end

      it 'returns empty replays (version == 1 excluded)' do
        result = dreamer.dream_replay
        expect(result[:replays]).to eq([])
        expect(result[:count]).to eq(0)
      end
    end

    context 'with synapses that have mutations (version > 1)' do
      let(:synapse) { make_synapse(version: 2, confidence: 0.75) }

      before do
        make_mutation(synapse, version: 2, mutation_type: 'route_changed', trigger: 'gaia')
      end

      it 'includes replays for synapses with version > 1' do
        result = dreamer.dream_replay
        expect(result[:count]).to eq(1)
      end

      it 'includes synapse_id in replay' do
        result = dreamer.dream_replay
        expect(result[:replays].first[:synapse_id]).to eq(synapse.id)
      end

      it 'includes current_version in replay' do
        result = dreamer.dream_replay
        expect(result[:replays].first[:current_version]).to eq(2)
      end

      it 'includes timeline with mutation entries' do
        result = dreamer.dream_replay
        timeline = result[:replays].first[:timeline]
        expect(timeline.size).to eq(1)
        expect(timeline.first[:mutation_type]).to eq('route_changed')
        expect(timeline.first[:trigger]).to eq('gaia')
      end

      it 'counts reverts' do
        make_mutation(synapse, version: 3, mutation_type: 'route_changed', trigger: 'gaia', outcome: 'reverted')
        result = dreamer.dream_replay
        expect(result[:replays].first[:reverts]).to eq(1)
      end

      it 'returns net_trend :improving when confidence >= 0.5' do
        result = dreamer.dream_replay
        expect(result[:replays].first[:net_trend]).to eq(:improving)
      end

      it 'returns net_trend :declining when confidence < 0.5' do
        synapse.update(confidence: 0.4)
        result = dreamer.dream_replay
        expect(result[:replays].first[:net_trend]).to eq(:declining)
      end

      it 'returns mutation_count' do
        result = dreamer.dream_replay
        expect(result[:replays].first[:mutation_count]).to eq(1)
      end
    end

    context 'with a specific synapse_id' do
      let(:synapse1) { make_synapse(version: 2) }
      let(:synapse2) { make_synapse(version: 2) }

      before do
        make_mutation(synapse1, version: 2)
        make_mutation(synapse2, version: 2)
      end

      it 'returns only the specified synapse replay' do
        result = dreamer.dream_replay(synapse_id: synapse1.id)
        expect(result[:count]).to eq(1)
        expect(result[:replays].first[:synapse_id]).to eq(synapse1.id)
      end

      it 'returns empty when synapse not found' do
        result = dreamer.dream_replay(synapse_id: 99_999)
        expect(result[:count]).to eq(0)
        expect(result[:replays]).to eq([])
      end
    end

    context 'with a synapse having no mutations' do
      let(:synapse) { make_synapse(version: 2) }

      it 'returns replay with empty timeline' do
        result = dreamer.dream_replay(synapse_id: synapse.id)
        expect(result[:replays].first[:timeline]).to eq([])
        expect(result[:replays].first[:mutation_count]).to eq(0)
      end
    end
  end

  describe '#dream_simulate' do
    let(:synapse) { make_synapse(confidence: 0.7) }

    context 'with nonexistent synapse' do
      it 'returns error' do
        result = dreamer.dream_simulate(synapse_id: 99_999, mutation_type: 'confidence_changed', changes: {})
        expect(result[:success]).to be false
        expect(result[:error]).to eq('synapse not found')
      end
    end

    context 'with attention_adjusted simulation' do
      it 'returns success' do
        result = dreamer.dream_simulate(
          synapse_id:    synapse.id,
          mutation_type: 'attention_adjusted',
          changes:       { attention: '{"field":"x"}' }
        )
        expect(result[:success]).to be true
      end

      it 'includes before state' do
        result = dreamer.dream_simulate(
          synapse_id:    synapse.id,
          mutation_type: 'attention_adjusted',
          changes:       { attention: '{"field":"x"}' }
        )
        expect(result[:before][:confidence]).to eq(0.7)
      end

      it 'includes simulated state with changed attention' do
        result = dreamer.dream_simulate(
          synapse_id:    synapse.id,
          mutation_type: 'attention_adjusted',
          changes:       { attention: '{"field":"x"}' }
        )
        expect(result[:simulated][:attention]).to eq('{"field":"x"}')
      end

      it 'does not modify the real synapse' do
        dreamer.dream_simulate(
          synapse_id:    synapse.id,
          mutation_type: 'attention_adjusted',
          changes:       { attention: '{"field":"x"}' }
        )
        synapse.reload
        expect(synapse.attention).to be_nil
      end
    end

    context 'with confidence_changed simulation that improves confidence' do
      it 'recommends :apply' do
        result = dreamer.dream_simulate(
          synapse_id:    synapse.id,
          mutation_type: 'confidence_changed',
          changes:       { confidence: 0.95 }
        )
        expect(result[:recommendation]).to eq(:apply)
      end
    end

    context 'with confidence_changed simulation that does not improve confidence' do
      it 'recommends :skip when simulated confidence is lower' do
        synapse.update(confidence: 0.9)
        result = dreamer.dream_simulate(
          synapse_id:    synapse.id,
          mutation_type: 'confidence_changed',
          changes:       { confidence: 0.1 }
        )
        expect(result[:recommendation]).to eq(:skip)
      end
    end

    context 'returns autonomy mode' do
      it 'includes simulated_mode' do
        result = dreamer.dream_simulate(
          synapse_id:    synapse.id,
          mutation_type: 'confidence_changed',
          changes:       { confidence: 0.9 }
        )
        expect(result[:simulated_mode]).to be_a(Symbol)
      end
    end

    context 'with route_changed simulation' do
      it 'changes routing_strategy in simulated state' do
        result = dreamer.dream_simulate(
          synapse_id:    synapse.id,
          mutation_type: 'route_changed',
          changes:       { routing_strategy: 'weighted' }
        )
        expect(result[:simulated][:routing_strategy]).to eq('weighted')
      end
    end

    context 'with transform_adjusted simulation' do
      it 'changes transform in simulated state' do
        result = dreamer.dream_simulate(
          synapse_id:    synapse.id,
          mutation_type: 'transform_adjusted',
          changes:       { transform: '{"template":"hello"}' }
        )
        expect(result[:simulated][:transform]).to eq('{"template":"hello"}')
      end
    end
  end
end
