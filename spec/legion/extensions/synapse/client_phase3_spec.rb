# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/legion/extensions/synapse/client'

RSpec.describe Legion::Extensions::Synapse::Client do
  subject(:client) { described_class.new }

  after(:each) do
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.delete
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  describe 'phase 3 runner method availability' do
    it 'responds to gaia_summary' do
      expect(client).to respond_to(:gaia_summary)
    end

    it 'responds to gaia_reflection' do
      expect(client).to respond_to(:gaia_reflection)
    end

    it 'responds to dream_replay' do
      expect(client).to respond_to(:dream_replay)
    end

    it 'responds to dream_simulate' do
      expect(client).to respond_to(:dream_simulate)
    end

    it 'responds to promote' do
      expect(client).to respond_to(:promote)
    end

    it 'responds to retrieve_and_seed' do
      expect(client).to respond_to(:retrieve_and_seed)
    end
  end

  describe '#gaia_summary via client' do
    it 'returns success with no synapses' do
      result = client.gaia_summary
      expect(result[:success]).to be true
      expect(result[:total_synapses]).to eq(0)
    end

    it 'counts active synapses' do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy:    'direct',
        confidence:          0.8,
        baseline_throughput: 0.0,
        origin:              'explicit',
        status:              'active',
        version:             1
      )
      result = client.gaia_summary
      expect(result[:active_count]).to eq(1)
    end
  end

  describe '#gaia_reflection via client' do
    it 'returns success' do
      result = client.gaia_reflection
      expect(result[:success]).to be true
    end

    it 'includes summary key' do
      result = client.gaia_reflection
      expect(result).to have_key(:summary)
    end
  end

  describe '#dream_replay via client' do
    it 'returns success with no synapses' do
      result = client.dream_replay
      expect(result[:success]).to be true
      expect(result[:count]).to eq(0)
    end
  end

  describe '#dream_simulate via client' do
    let(:synapse) do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy:    'direct',
        confidence:          0.7,
        baseline_throughput: 0.0,
        origin:              'explicit',
        status:              'active',
        version:             1
      )
    end

    it 'returns success for valid synapse' do
      result = client.dream_simulate(
        synapse_id:    synapse.id,
        mutation_type: 'confidence_changed',
        changes:       { confidence: 0.9 }
      )
      expect(result[:success]).to be true
    end

    it 'returns error for nonexistent synapse' do
      result = client.dream_simulate(synapse_id: 99_999, mutation_type: 'confidence_changed', changes: {})
      expect(result[:success]).to be false
    end
  end

  describe '#promote via client' do
    it 'returns success with no promotable synapses' do
      result = client.promote
      expect(result[:success]).to be true
      expect(result[:count]).to eq(0)
    end

    it 'promotes high-confidence active synapse' do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        source_function_id:  1,
        target_function_id:  2,
        routing_strategy:    'direct',
        confidence:          0.95,
        baseline_throughput: 0.0,
        origin:              'explicit',
        status:              'active',
        version:             1
      )
      result = client.promote
      expect(result[:count]).to eq(1)
    end
  end

  describe '#retrieve_and_seed via client' do
    it 'returns success with empty entries' do
      result = client.retrieve_and_seed(knowledge_entries: [])
      expect(result[:success]).to be true
      expect(result[:count]).to eq(0)
    end

    it 'seeds a valid entry' do
      entry = {
        confidence:   0.8,
        content_type: 'synapse_pattern',
        content:      Legion::JSON.dump({
                                          source_function_id: 50,
                                          target_function_id: 60,
                                          routing_strategy:   'direct'
                                        })
      }
      result = client.retrieve_and_seed(knowledge_entries: [entry])
      expect(result[:count]).to eq(1)
    end
  end
end
