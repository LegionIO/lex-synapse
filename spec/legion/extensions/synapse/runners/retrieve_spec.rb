# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/retrieve'

RSpec.describe Legion::Extensions::Synapse::Runners::Retrieve do
  subject(:retriever) { Object.new.extend(described_class) }

  def valid_entry(source: 100, target: 200, confidence: 0.8, content_type: 'synapse_pattern')
    {
      confidence:   confidence,
      content_type: content_type,
      content:      Legion::JSON.dump(
        source_function_id: source,
        target_function_id: target,
        attention:          nil,
        transform:          nil,
        routing_strategy:   'direct',
        confidence:         confidence,
        origin:             'explicit',
        version:            1
      )
    }
  end

  after(:each) do
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  describe '#retrieve_and_seed' do
    context 'with empty knowledge_entries' do
      it 'returns success true' do
        result = retriever.retrieve_and_seed(knowledge_entries: [])
        expect(result[:success]).to be true
      end

      it 'returns zero count' do
        result = retriever.retrieve_and_seed(knowledge_entries: [])
        expect(result[:count]).to eq(0)
        expect(result[:seeded]).to eq([])
      end
    end

    context 'with a valid entry above confidence threshold' do
      it 'creates a synapse' do
        expect do
          retriever.retrieve_and_seed(knowledge_entries: [valid_entry])
        end.to change { Legion::Extensions::Synapse::Data::Model::Synapse.count }.by(1)
      end

      it 'sets origin to seeded' do
        retriever.retrieve_and_seed(knowledge_entries: [valid_entry])
        synapse = Legion::Extensions::Synapse::Data::Model::Synapse.last
        expect(synapse.origin).to eq('seeded')
      end

      it 'sets confidence to seeded starting score (0.5)' do
        retriever.retrieve_and_seed(knowledge_entries: [valid_entry])
        synapse = Legion::Extensions::Synapse::Data::Model::Synapse.last
        expect(synapse.confidence).to eq(0.5)
      end

      it 'sets status to active' do
        retriever.retrieve_and_seed(knowledge_entries: [valid_entry])
        synapse = Legion::Extensions::Synapse::Data::Model::Synapse.last
        expect(synapse.status).to eq('active')
      end

      it 'returns seeded entry with id, source, and target' do
        result = retriever.retrieve_and_seed(knowledge_entries: [valid_entry])
        entry = result[:seeded].first
        expect(entry[:source]).to eq(100)
        expect(entry[:target]).to eq(200)
        expect(entry[:id]).to be_a(Integer)
      end

      it 'returns count of 1' do
        result = retriever.retrieve_and_seed(knowledge_entries: [valid_entry])
        expect(result[:count]).to eq(1)
      end
    end

    context 'with entry below confidence threshold' do
      it 'skips the entry' do
        entry = valid_entry(confidence: 0.5)
        result = retriever.retrieve_and_seed(knowledge_entries: [entry])
        expect(result[:count]).to eq(0)
      end
    end

    context 'with entry missing confidence' do
      it 'skips the entry' do
        entry = { content_type: 'synapse_pattern', content: '{}' }
        result = retriever.retrieve_and_seed(knowledge_entries: [entry])
        expect(result[:count]).to eq(0)
      end
    end

    context 'with non-synapse_pattern content type' do
      it 'skips the entry' do
        entry = valid_entry(content_type: 'other_pattern')
        result = retriever.retrieve_and_seed(knowledge_entries: [entry])
        expect(result[:count]).to eq(0)
      end
    end

    context 'when synapse already exists for the same source/target pair' do
      before do
        Legion::Extensions::Synapse::Data::Model::Synapse.create(
          source_function_id:  100,
          target_function_id:  200,
          routing_strategy:    'direct',
          confidence:          0.7,
          baseline_throughput: 0.0,
          origin:              'explicit',
          status:              'active',
          version:             1
        )
      end

      it 'skips duplicate synapse' do
        result = retriever.retrieve_and_seed(knowledge_entries: [valid_entry])
        expect(result[:count]).to eq(0)
      end
    end

    context 'with malformed JSON content' do
      it 'handles gracefully and skips' do
        entry = { confidence: 0.8, content_type: 'synapse_pattern', content: 'not-valid-json{{{' }
        expect do
          result = retriever.retrieve_and_seed(knowledge_entries: [entry])
          expect(result[:count]).to eq(0)
        end.not_to raise_error
      end
    end

    context 'with content as a hash (already parsed)' do
      it 'uses the hash directly' do
        entry = {
          confidence:   0.8,
          content_type: 'synapse_pattern',
          content:      {
            source_function_id: 300,
            target_function_id: 400,
            routing_strategy:   'direct'
          }
        }
        result = retriever.retrieve_and_seed(knowledge_entries: [entry])
        expect(result[:count]).to eq(1)
        expect(result[:seeded].first[:source]).to eq(300)
      end
    end

    context 'with nil content' do
      it 'skips entry with nil content' do
        entry = { confidence: 0.8, content_type: 'synapse_pattern', content: nil }
        result = retriever.retrieve_and_seed(knowledge_entries: [entry])
        expect(result[:count]).to eq(0)
      end
    end

    context 'with multiple entries' do
      it 'seeds multiple valid entries' do
        entries = [
          valid_entry(source: 1, target: 2),
          valid_entry(source: 3, target: 4),
          valid_entry(source: 5, target: 6, confidence: 0.3)
        ]
        result = retriever.retrieve_and_seed(knowledge_entries: entries)
        expect(result[:count]).to eq(2)
      end
    end
  end
end
