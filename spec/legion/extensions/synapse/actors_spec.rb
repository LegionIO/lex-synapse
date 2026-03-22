# frozen_string_literal: true

require 'spec_helper'

# Stub framework base classes
unless defined?(Legion::Extensions::Actors::Subscription)
  module Legion
    module Extensions
      module Actors
        class Subscription; end
      end
    end
  end
end

unless defined?(Legion::Extensions::Actors::Every)
  module Legion
    module Extensions
      module Actors
        class Every; end
      end
    end
  end
end

require 'legion/extensions/synapse/actors/evaluate'
require 'legion/extensions/synapse/actors/pain'
require 'legion/extensions/synapse/actors/crystallize'
require 'legion/extensions/synapse/actors/homeostasis'
require 'legion/extensions/synapse/actors/decay'
require 'legion/extensions/synapse/actors/propose'
require 'legion/extensions/synapse/actors/challenge'

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
      it 'returns empty results when no active synapses exist' do
        result = actor.action
        expect(result).to include(spikes: 0, droughts: 0, updated: 0)
      end
    end
  end

  describe Legion::Extensions::Synapse::Actor::Decay do
    let(:actor) { described_class.allocate }

    it('has runner_function apply_decay') { expect(actor.runner_function).to eq('apply_decay') }
    it('runs every 3600 seconds') { expect(actor.time).to eq(3600) }
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
end
