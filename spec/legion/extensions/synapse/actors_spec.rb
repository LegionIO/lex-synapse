# frozen_string_literal: true

require 'spec_helper'
require 'open3'

require 'legion/extensions/synapse/actors/evaluate'
require 'legion/extensions/synapse/actors/pain'
require 'legion/extensions/synapse/actors/crystallize'
require 'legion/extensions/synapse/actors/homeostasis'
require 'legion/extensions/synapse/actors/decay'
require 'legion/extensions/synapse/actors/propose'
require 'legion/extensions/synapse/actors/challenge'
require 'legion/extensions/synapse/actors/blast_radius'

RSpec.describe 'Synapse Actors' do
  describe Legion::Extensions::Synapse::Actor::Evaluate do
    let(:actor) { described_class.allocate }

    it('has runner_function evaluate') { expect(actor.runner_function).to eq('evaluate') }
  end

  describe Legion::Extensions::Synapse::Actor::Pain do
    let(:actor) { described_class.allocate }

    it('has runner_function handle_pain') { expect(actor.runner_function).to eq('handle_pain') }
  end

  describe Legion::Extensions::Synapse::Actor::Crystallize do
    let(:actor) { described_class.allocate }

    it('has runner_function crystallize') { expect(actor.runner_function).to eq('crystallize') }
    it('runs every 300 seconds') { expect(actor.time).to eq(300) }
  end

  describe Legion::Extensions::Synapse::Actor::Homeostasis do
    let(:actor) { described_class.allocate }

    it('returns self.class as runner_class') { expect(actor.runner_class).to eq(described_class) }
    it('runs every 30 seconds') { expect(actor.time).to eq(30) }
    it('does not use runner') { expect(actor.use_runner?).to be false }

    describe '#action' do
      before do
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.delete
        Legion::Extensions::Synapse::Data::Model::Synapse.dataset.delete
      end

      it 'returns empty results when no active synapses exist' do
        result = actor.action
        expect(result).to include(spikes: 0, droughts: 0, updated: 0)
      end

      it 'initializes both lazy models on the first action in a fresh process' do
        script = <<~RUBY
          require 'sequel'
          require 'legion/settings'
          module Legion
            module Data; end
            module Settings
              def self.dig(*) = true
            end
            module Extensions
              module Actors
                class Every; end
              end
            end
          end
          db = Sequel.sqlite
          Sequel.extension :migration
          Sequel::Migrator.run(db, 'lib/legion/extensions/synapse/data/migrations')
          Sequel::Model.db = db
          db[:synapses].insert(status: 'active', baseline_throughput: 10.0)
          require 'legion/extensions/synapse/helpers/homeostasis'
          require 'legion/extensions/synapse/actors/homeostasis'
          models = Legion::Extensions::Synapse::Data::Model
          abort 'model initialized too early' if models.const_defined?(:Synapse, false)
          result = Legion::Extensions::Synapse::Actor::Homeostasis.allocate.action
          abort result.inspect unless result[:updated] == 1 && result[:droughts] == 1
          abort 'baseline not updated' unless db[:synapses].get(:baseline_throughput) == 9.0
        RUBY
        stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', '-e', script)
        expect(status.success?).to be(true), "#{stdout}#{stderr}"
      end

      it 'reports unavailable data when lazy model initialization cannot run' do
        hide_const('Legion::Extensions::Synapse::Data::Model::SynapseSignal')
        allow(Legion::Settings).to receive(:dig).with(:data, :connected).and_return(false)
        expect(actor.action).to eq(status: :skipped, reason: :no_data)
      end

      context 'with one active synapse and no recent signals' do
        let!(:synapse) do
          Legion::Extensions::Synapse::Data::Model::Synapse.create(
            status: 'active', baseline_throughput: 10.0
          )
        end

        it 'updates the synapse baseline and returns updated count of 1' do
          result = actor.action
          expect(result).to include(updated: 1, spikes: 0)
          synapse.reload
          expect(synapse.baseline_throughput).to be < 10.0
        end

        it 'does not issue a per-synapse signals sub-query (no N+1)' do
          query_log = []
          db = Sequel::Model.db
          logger = Object.new
          logger.define_singleton_method(:info)  { |m| query_log << m }
          logger.define_singleton_method(:debug) { |m| query_log << m }
          logger.define_singleton_method(:warn)  { |_m| nil }
          logger.define_singleton_method(:error) { |_m| nil }

          original_loggers = db.loggers.dup
          db.loggers << logger

          actor.action

          db.loggers.replace(original_loggers)

          signal_queries = query_log.count { |q| q.to_s.include?('synapse_signals') }
          expect(signal_queries).to be <= 1
        end
      end

      context 'with multiple active synapses' do
        let!(:synapse_a) do
          Legion::Extensions::Synapse::Data::Model::Synapse.create(
            status: 'active', baseline_throughput: 5.0
          )
        end
        let!(:synapse_b) do
          Legion::Extensions::Synapse::Data::Model::Synapse.create(
            status: 'active', baseline_throughput: 5.0
          )
        end

        it 'processes all active synapses in a single signals query' do
          query_log = []
          db = Sequel::Model.db
          logger = Object.new
          logger.define_singleton_method(:info)  { |m| query_log << m }
          logger.define_singleton_method(:debug) { |m| query_log << m }
          logger.define_singleton_method(:warn)  { |_m| nil }
          logger.define_singleton_method(:error) { |_m| nil }

          original_loggers = db.loggers.dup
          db.loggers << logger

          result = actor.action

          db.loggers.replace(original_loggers)

          expect(result[:updated]).to eq(2)
          signal_queries = query_log.count { |q| q.to_s.include?('synapse_signals') }
          expect(signal_queries).to be <= 1
        end
      end

      context 'with a new active synapse' do
        let!(:synapse) { Legion::Extensions::Synapse::Data::Model::Synapse.create(status: 'active') }

        it 'keeps a silent zero baseline without reporting an anomaly' do
          expect(actor.action).to eq(spikes: 0, droughts: 0, updated: 1)
          expect(synapse.reload.baseline_throughput).to eq(0.0)
        end

        it 'bootstraps from traffic and detects a spike in the next window' do
          10.times do
            Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
              synapse_id: synapse.id, created_at: Time.now
            )
          end
          expect(actor.action).to eq(spikes: 0, droughts: 0, updated: 1)
          expect(synapse.reload.baseline_throughput).to eq(1.0)
          expect(actor.action).to eq(spikes: 1, droughts: 0, updated: 1)
          expect(synapse.reload.baseline_throughput).to eq(1.9)
        end

        it 'can detect a drought after bootstrapping a sufficiently busy baseline' do
          100.times do
            Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
              synapse_id: synapse.id, created_at: Time.now
            )
          end
          expect(actor.action).to eq(spikes: 0, droughts: 0, updated: 1)
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.dataset.update(created_at: Time.now - 120)
          expect(actor.action).to eq(spikes: 0, droughts: 1, updated: 1)
          expect(synapse.reload.baseline_throughput).to eq(9.0)
        end
      end

      context 'with an inactive synapse' do
        let!(:inactive) do
          Legion::Extensions::Synapse::Data::Model::Synapse.create(
            status: 'inactive', baseline_throughput: 10.0
          )
        end

        it 'skips inactive synapses' do
          result = actor.action
          expect(result).to include(updated: 0)
        end
      end
    end
  end

  describe Legion::Extensions::Synapse::Actor::Decay do
    let(:actor) { described_class.allocate }

    it('returns self.class as runner_class') { expect(actor.runner_class).to eq(described_class) }
    it('runs every 3600 seconds') { expect(actor.time).to eq(3600) }
    it('responds to action') { expect(actor).to respond_to(:action) }
  end

  describe Legion::Extensions::Synapse::Actor::Propose do
    let(:actor) { described_class.allocate }

    it('has runner_function propose_proactive') { expect(actor.runner_function).to eq('propose_proactive') }
    it('runs every 300 seconds') { expect(actor.time).to eq(300) }
    it('does not use runner') { expect(actor.use_runner?).to be false }
    it('does not check subtask') { expect(actor.check_subtask?).to be false }
    it('does not generate task') { expect(actor.generate_task?).to be false }
  end

  describe Legion::Extensions::Synapse::Actor::Challenge do
    let(:actor) { described_class.allocate }

    it('has runner_function run_challenge_cycle') { expect(actor.runner_function).to eq('run_challenge_cycle') }
    it('runs every 60 seconds') { expect(actor.time).to eq(60) }
    it('does not use runner') { expect(actor.use_runner?).to be false }
  end

  describe Legion::Extensions::Synapse::Actor::BlastRadius do
    let(:actor) { described_class.allocate }

    it('has runner_function compute') { expect(actor.runner_function).to eq('compute') }
    it('runs every 1800 seconds') { expect(actor.time).to eq(1800) }
    it('does not use runner') { expect(actor.use_runner?).to be false }
    it('does not check subtask') { expect(actor.check_subtask?).to be false }
    it('does not generate task') { expect(actor.generate_task?).to be false }
    it('returns self.class as runner_class') { expect(actor.runner_class).to eq(described_class) }
  end
end
