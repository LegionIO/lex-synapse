# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:synapse_proposals) do
      primary_key :id
      foreign_key :synapse_id, :synapses, null: false, index: true
      Integer    :signal_id
      String     :proposal_type, null: false, size: 50
      String     :trigger, null: false, size: 50
      String     :inputs, text: true
      String     :output, text: true
      String     :rationale, text: true
      String     :status, default: 'pending', size: 50
      Float      :estimated_confidence_impact
      DateTime   :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime   :reviewed_at
    end
  end

  down do
    drop_table :synapse_proposals
  end
end
