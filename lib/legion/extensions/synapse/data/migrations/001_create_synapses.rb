# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:synapses) do
      primary_key :id
      Integer  :source_function_id, null: true, index: true
      Integer  :target_function_id, null: true, index: true
      Integer  :relationship_id,    null: true, index: true
      String   :attention,          text: true
      String   :transform,          text: true
      String   :routing_strategy,   null: false, default: 'direct', size: 50
      Float    :confidence,         null: false, default: 0.5
      Float    :baseline_throughput, null: false, default: 0.0
      String   :origin,             null: false, default: 'explicit', size: 50
      String   :status,             null: false, default: 'active', size: 50
      Integer  :version,            null: false, default: 1
      DateTime :created_at,         null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at
    end
  end

  down do
    drop_table :synapses
  end
end
