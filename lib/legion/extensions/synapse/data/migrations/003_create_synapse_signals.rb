# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:synapse_signals) do
      primary_key :id
      foreign_key :synapse_id, :synapses, null: false, index: true
      Integer    :task_id
      TrueClass  :passed_attention,   default: false
      TrueClass  :transform_success,  default: false
      String     :downstream_outcome, size: 50
      Integer    :latency_ms
      DateTime   :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  down do
    drop_table :synapse_signals
  end
end
