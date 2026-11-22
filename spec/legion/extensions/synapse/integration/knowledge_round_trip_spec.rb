# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/synapse/client'

RSpec.describe 'Apollo synapse pattern exchange' do
  let(:apollo) { double('Apollo') }
  let(:client) { Legion::Extensions::Synapse::Client.new(apollo_client: apollo) }
  let(:synapse) do
    client.create(source_function_id: 51, target_function_id: 52).tap do |record|
      record.update(confidence: 0.95, created_at: Time.now - (25 * 3600))
    end
  end

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.dataset.delete
    Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
  end

  it 'publishes a versioned raw pattern and seeds a normalized Apollo entry once' do
    synapse
    stored = {}
    allow(apollo).to receive(:ingest) do |**options|
      expect(options).to include(content_type: :procedure, source_agent: 'lex-synapse', scope: :global)
      expect(options[:raw_content]).to eq(options[:content])
      stored[options[:content]] ||= options
      { success: true, entry_id: 7 }
    end
    2.times { expect(client.promote[:count]).to eq(1) }
    expect(stored.size).to eq(1) # Same content permits Apollo's content-hash deduplication.
    synapse.delete
    allow(apollo).to receive(:retrieve).with(hash_including(tags: ['synapse'], scope: :global, min_confidence: 0.7)).and_return(
      success: true, entries: [{ content_type: 'fact', content: 'summary', raw_content: stored.values.first[:raw_content], confidence: 0.9 }]
    )
    expect(client.retrieve_and_seed[:count]).to eq(1)
    expect(client.retrieve_and_seed[:count]).to eq(0)
    seeded = Legion::Extensions::Synapse::Data::Model::Synapse.first(source_function_id: 51)
    expect(seeded).to have_attributes(target_function_id: 52, origin: 'seeded', confidence: 0.5)
  end

  it 'keeps case-sensitive template changes distinct under Apollo content normalization' do
    synapse.update(transform: '{"template":"ABC"}')
    contents = []
    allow(apollo).to receive(:ingest) do |**options|
      contents << options[:content].downcase
      { success: true, entry_id: 7 }
    end
    client.promote
    synapse.update(transform: '{"template":"abc"}')
    client.promote
    expect(contents.uniq.size).to eq(2)
  end

  it 'previews candidates without claiming publication or calling Apollo' do
    synapse
    expect(apollo).not_to receive(:ingest)
    expect(client.promote(publish: false)).to include(success: true, candidate_count: 1, count: 0, promoted: [])
  end

  it 'does not promote newly created or recently mutated state' do
    synapse.update(created_at: Time.now)
    expect(client.promote[:candidate_count]).to eq(0)
    synapse.update(created_at: Time.now - (25 * 3600))
    client.mutate(synapse_id: synapse.id, mutation_type: 'route_changed', changes: { routing_strategy: 'direct' }, trigger: 'manual')
    expect(client.promote[:candidate_count]).to eq(0)
  end

  it 'distinguishes asynchronous submission from durable publication' do
    synapse
    allow(apollo).to receive(:ingest).and_return(success: true, mode: :async)
    result = client.promote
    expect(result[:submitted].size).to eq(1)
    expect(result).to include(count: 0, promoted: [])
  end

  it 'reports provider failures without claiming durable publication' do
    synapse
    allow(apollo).to receive(:ingest).and_return(success: false, error: 'offline')
    expect(client.promote).to include(success: false, count: 0, errors: [{ synapse_id: synapse.id, error: 'offline' }])
  end

  it 'requires a durable entry ID or a persisted duplicate result' do
    synapse
    allow(apollo).to receive(:ingest).and_return(success: true)
    expect(client.promote).to include(success: false, count: 0)
  end

  it 'handles unavailable Apollo explicitly for promotion and retrieval' do
    synapse
    allow(client).to receive(:knowledge_provider).and_return(nil)
    expect(client.promote).to include(success: false, error: 'Apollo unavailable', count: 0)
    expect(client.retrieve_and_seed).to include(success: false, error: 'Apollo unavailable', count: 0)
  end

  it 'does not seed a failed or asynchronous retrieval' do
    allow(apollo).to receive(:retrieve).and_return(success: false, error: 'offline')
    expect(client.retrieve_and_seed).to include(success: false, count: 0)
    allow(apollo).to receive(:retrieve).and_return(success: true, mode: :async)
    expect(client.retrieve_and_seed).to include(success: false, count: 0)
  end

  it 'rejects unknown pattern versions and missing endpoint identities' do
    entries = [
      { content_type: 'fact', confidence: 0.9, content: { format: 'legion.synapse_pattern', schema_version: 2, source_function_id: 1, target_function_id: 2 } },
      { content_type: 'synapse_pattern', confidence: 0.9, content: {} }
    ]
    expect(client.retrieve_and_seed(knowledge_entries: entries)[:count]).to eq(0)
  end
end
