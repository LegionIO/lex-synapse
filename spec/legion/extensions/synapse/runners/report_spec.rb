# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../lib/legion/extensions/synapse/runners/report'

RSpec.describe Legion::Extensions::Synapse::Runners::Report do
  subject(:reporter) { Object.new.extend(described_class) }

  let(:synapse) do
    Legion::Extensions::Synapse::Data::Model::Synapse.create(
      routing_strategy:    'direct',
      confidence:          0.7,
      baseline_throughput: 1.0,
      origin:              'explicit',
      status:              'active',
      version:             1
    )
  end

  after do
    Legion::Extensions::Synapse::Data::Model::SynapseSignal.where(synapse_id: synapse.id).delete
    Legion::Extensions::Synapse::Data::Model::SynapseMutation.where(synapse_id: synapse.id).delete
    synapse.delete
  end

  describe '#report' do
    context 'with nonexistent synapse' do
      it 'returns error' do
        result = reporter.report(synapse_id: 99_999)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('synapse not found')
      end
    end

    context 'with a synapse and no signals' do
      it 'returns success' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:success]).to be true
      end

      it 'returns synapse_id' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:synapse_id]).to eq(synapse.id)
      end

      it 'returns confidence' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:confidence]).to eq(0.7)
      end

      it 'returns status' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:status]).to eq('active')
      end

      it 'returns origin' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:origin]).to eq('explicit')
      end

      it 'returns version' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:version]).to eq(1)
      end

      it 'returns nil success_rate when no signals' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:success_rate]).to be_nil
      end

      it 'returns 0 signals_24h' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:signals_24h]).to eq(0)
      end

      it 'returns nil last_mutation when no mutations' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:last_mutation]).to be_nil
      end
    end

    context 'with signals' do
      before do
        3.times do
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id:         synapse.id,
            passed_attention:   true,
            transform_success:  true,
            downstream_outcome: 'success'
          )
        end
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id:         synapse.id,
          passed_attention:   true,
          transform_success:  true,
          downstream_outcome: 'failed'
        )
      end

      it 'calculates success_rate from recent signals' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:success_rate]).to eq(0.75)
      end

      it 'returns total_signals count' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:total_signals]).to eq(4)
      end
    end

    context 'with unresolved and completed outcomes' do
      it 'excludes unknown outcomes from the completion denominator' do
        %w[success success failed].each do |outcome|
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id: synapse.id, downstream_outcome: outcome, transform_success: true
          )
        end
        5.times do
          Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
            synapse_id: synapse.id, transform_success: true
          )
        end
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id: synapse.id, downstream_outcome: 'failed', created_at: Time.now - 90_000
        )
        expect(reporter.report(synapse_id: synapse.id)).to include(
          signals_24h: 8, total_signals: 9, success_rate: 0.6667,
          completed_outcomes_24h: 3, successful_outcomes_24h: 2, failed_outcomes_24h: 1,
          unresolved_signals_24h: 5, evaluation_successes_24h: 8
        )
      end

      it 'distinguishes successful evaluation from downstream completion' do
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id: synapse.id, transform_success: true
        )
        expect(reporter.report(synapse_id: synapse.id)).to include(
          success_rate: nil, completed_outcomes_24h: 0, failed_outcomes_24h: 0,
          unresolved_signals_24h: 1, evaluation_successes_24h: 1
        )
      end

      it 'reports a real zero rate when all completed outcomes failed' do
        Legion::Extensions::Synapse::Data::Model::SynapseSignal.create(
          synapse_id: synapse.id, downstream_outcome: 'failed'
        )
        expect(reporter.report(synapse_id: synapse.id)).to include(
          success_rate: 0.0, completed_outcomes_24h: 1, failed_outcomes_24h: 1
        )
      end
    end

    context 'with a mutation' do
      before do
        Legion::Extensions::Synapse::Data::Model::SynapseMutation.create(
          synapse_id:    synapse.id,
          version:       2,
          mutation_type: 'confidence_changed',
          trigger:       'manual',
          outcome:       nil
        )
      end

      it 'includes last_mutation info' do
        result = reporter.report(synapse_id: synapse.id)
        expect(result[:last_mutation]).not_to be_nil
        expect(result[:last_mutation][:type]).to eq('confidence_changed')
        expect(result[:last_mutation][:trigger]).to eq('manual')
        expect(result[:last_mutation][:version]).to eq(2)
      end
    end
  end
end
