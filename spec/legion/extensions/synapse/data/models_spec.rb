# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Synapse data models' do
  describe 'migration files' do
    let(:migrations_dir) do
      File.expand_path('../../../../../lib/legion/extensions/synapse/data/migrations', __dir__)
    end

    it 'has migration 001_create_synapses.rb' do
      expect(File.exist?(File.join(migrations_dir, '001_create_synapses.rb'))).to be true
    end

    it 'has migration 002_create_synapse_mutations.rb' do
      expect(File.exist?(File.join(migrations_dir, '002_create_synapse_mutations.rb'))).to be true
    end

    it 'has migration 003_create_synapse_signals.rb' do
      expect(File.exist?(File.join(migrations_dir, '003_create_synapse_signals.rb'))).to be true
    end

    it 'migration 001 is valid Ruby' do
      path = File.join(migrations_dir, '001_create_synapses.rb')
      expect { RubyVM::InstructionSequence.compile_file(path) }.not_to raise_error
    end

    it 'migration 002 is valid Ruby' do
      path = File.join(migrations_dir, '002_create_synapse_mutations.rb')
      expect { RubyVM::InstructionSequence.compile_file(path) }.not_to raise_error
    end

    it 'migration 003 is valid Ruby' do
      path = File.join(migrations_dir, '003_create_synapse_signals.rb')
      expect { RubyVM::InstructionSequence.compile_file(path) }.not_to raise_error
    end
  end

  describe 'schema' do
    it 'creates the synapses table' do
      expect(DB.table_exists?(:synapses)).to be true
    end

    it 'creates the synapse_mutations table' do
      expect(DB.table_exists?(:synapse_mutations)).to be true
    end

    it 'creates the synapse_signals table' do
      expect(DB.table_exists?(:synapse_signals)).to be true
    end

    it 'synapses has expected columns' do
      cols = DB.schema(:synapses).map { |c| c[0] }
      expect(cols).to include(:id, :routing_strategy, :confidence, :status, :origin, :version, :created_at)
    end

    it 'synapse_mutations has expected columns' do
      cols = DB.schema(:synapse_mutations).map { |c| c[0] }
      expect(cols).to include(:id, :synapse_id, :version, :mutation_type, :trigger, :created_at)
    end

    it 'synapse_signals has expected columns' do
      cols = DB.schema(:synapse_signals).map { |c| c[0] }
      expect(cols).to include(:id, :synapse_id, :task_id, :passed_attention, :transform_success, :created_at)
    end
  end

  describe Legion::Extensions::Synapse::Data::Model::Synapse do
    it 'is defined' do
      expect(defined?(Legion::Extensions::Synapse::Data::Model::Synapse)).to eq('constant')
    end

    it 'is a Sequel::Model subclass' do
      expect(described_class.ancestors).to include(Sequel::Model)
    end

    it 'responds to one_to_many association :mutations' do
      expect(described_class).to respond_to(:one_to_many)
    end

    it 'has mutations association' do
      expect(described_class.associations).to include(:mutations)
    end

    it 'has signals association' do
      expect(described_class.associations).to include(:signals)
    end

    it 'can create and retrieve a record' do
      synapse = described_class.create(
        routing_strategy:    'direct',
        confidence:          0.7,
        baseline_throughput: 1.5,
        origin:              'explicit',
        status:              'active',
        version:             1,
        created_at:          Time.now
      )
      expect(synapse.id).not_to be_nil
      expect(synapse.confidence).to eq(0.7)
      expect(synapse.routing_strategy).to eq('direct')
      synapse.delete
    end

    it 'defaults confidence to 0.5' do
      synapse = described_class.create(
        routing_strategy:    'direct',
        baseline_throughput: 0.0,
        origin:              'explicit',
        status:              'active',
        version:             1,
        created_at:          Time.now
      )
      expect(synapse.confidence).to eq(0.5)
      synapse.delete
    end

    it 'defaults status to active' do
      synapse = described_class.create(
        routing_strategy:    'direct',
        baseline_throughput: 0.0,
        origin:              'explicit',
        version:             1,
        created_at:          Time.now
      )
      expect(synapse.status).to eq('active')
      synapse.delete
    end
  end

  describe Legion::Extensions::Synapse::Data::Model::SynapseMutation do
    let(:synapse) do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy:    'weighted',
        confidence:          0.6,
        baseline_throughput: 0.0,
        origin:              'learned',
        status:              'active',
        version:             1,
        created_at:          Time.now
      )
    end

    after { synapse.delete }

    it 'is defined' do
      expect(defined?(Legion::Extensions::Synapse::Data::Model::SynapseMutation)).to eq('constant')
    end

    it 'is a Sequel::Model subclass' do
      expect(described_class.ancestors).to include(Sequel::Model)
    end

    it 'has synapse association' do
      expect(described_class.associations).to include(:synapse)
    end

    it 'can create and retrieve a record' do
      mutation = described_class.create(
        synapse_id:    synapse.id,
        version:       1,
        mutation_type: 'confidence_update',
        trigger:       'signal',
        created_at:    Time.now
      )
      expect(mutation.id).not_to be_nil
      expect(mutation.synapse_id).to eq(synapse.id)
      expect(mutation.mutation_type).to eq('confidence_update')
      mutation.delete
    end
  end

  describe 'synapse_proposals migration' do
    it 'has migration 004_create_synapse_proposals.rb' do
      migrations_dir = File.expand_path('../../../../../lib/legion/extensions/synapse/data/migrations', __dir__)
      expect(File.exist?(File.join(migrations_dir, '004_create_synapse_proposals.rb'))).to be true
    end

    it 'migration 004 is valid Ruby' do
      migrations_dir = File.expand_path('../../../../../lib/legion/extensions/synapse/data/migrations', __dir__)
      path = File.join(migrations_dir, '004_create_synapse_proposals.rb')
      expect { RubyVM::InstructionSequence.compile_file(path) }.not_to raise_error
    end

    it 'creates the synapse_proposals table' do
      expect(DB.table_exists?(:synapse_proposals)).to be true
    end

    it 'synapse_proposals has expected columns' do
      cols = DB.schema(:synapse_proposals).map { |c| c[0] }
      expect(cols).to include(:id, :synapse_id, :signal_id, :proposal_type, :trigger,
                              :inputs, :output, :rationale, :status, :estimated_confidence_impact,
                              :created_at, :reviewed_at)
    end
  end

  describe Legion::Extensions::Synapse::Data::Model::SynapseSignal do
    let(:synapse) do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy:    'direct',
        confidence:          0.8,
        baseline_throughput: 2.0,
        origin:              'explicit',
        status:              'active',
        version:             1,
        created_at:          Time.now
      )
    end

    after { synapse.delete }

    it 'is defined' do
      expect(defined?(Legion::Extensions::Synapse::Data::Model::SynapseSignal)).to eq('constant')
    end

    it 'is a Sequel::Model subclass' do
      expect(described_class.ancestors).to include(Sequel::Model)
    end

    it 'has synapse association' do
      expect(described_class.associations).to include(:synapse)
    end

    it 'can create and retrieve a record' do
      signal = described_class.create(
        synapse_id:         synapse.id,
        task_id:            42,
        passed_attention:   true,
        transform_success:  false,
        downstream_outcome: 'routed',
        latency_ms:         12,
        created_at:         Time.now
      )
      expect(signal.id).not_to be_nil
      expect(signal.synapse_id).to eq(synapse.id)
      expect(signal.passed_attention).to be true
      expect(signal.latency_ms).to eq(12)
      signal.delete
    end

    it 'defaults passed_attention to false' do
      signal = described_class.create(
        synapse_id: synapse.id,
        created_at: Time.now
      )
      expect(signal.passed_attention).to be false
      signal.delete
    end

    it 'defaults transform_success to false' do
      signal = described_class.create(
        synapse_id: synapse.id,
        created_at: Time.now
      )
      expect(signal.transform_success).to be false
      signal.delete
    end
  end

  describe Legion::Extensions::Synapse::Data::Model::SynapseProposal do
    let(:synapse) do
      Legion::Extensions::Synapse::Data::Model::Synapse.create(
        routing_strategy: 'direct', confidence: 0.85, baseline_throughput: 1.0,
        origin: 'explicit', status: 'active', version: 1, created_at: Time.now
      )
    end

    after { synapse.delete }

    it 'is defined' do
      expect(defined?(Legion::Extensions::Synapse::Data::Model::SynapseProposal)).to eq('constant')
    end

    it 'is a Sequel::Model subclass' do
      expect(described_class.ancestors).to include(Sequel::Model)
    end

    it 'has synapse association' do
      expect(described_class.associations).to include(:synapse)
    end

    it 'can create and retrieve a record' do
      proposal = described_class.create(
        synapse_id: synapse.id, proposal_type: 'llm_transform', trigger: 'reactive',
        inputs: '{"source_schema":{}}', output: '{"template":"hello"}',
        rationale: 'no template exists', status: 'pending', created_at: Time.now
      )
      expect(proposal.id).not_to be_nil
      expect(proposal.proposal_type).to eq('llm_transform')
      expect(proposal.trigger).to eq('reactive')
      proposal.delete
    end

    it 'defaults status to pending' do
      proposal = described_class.create(
        synapse_id: synapse.id, proposal_type: 'llm_transform', trigger: 'reactive',
        created_at: Time.now
      )
      expect(proposal.status).to eq('pending')
      proposal.delete
    end
  end
end
