# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:synapse_mutations) do
      primary_key :id
      foreign_key :synapse_id, :synapses, null: false, index: true
      Integer  :version,       null: false
      String   :mutation_type, null: false, size: 50
      String   :before_state,  text: true
      String   :after_state,   text: true
      String   :trigger,       null: false, size: 50
      String   :outcome,       size: 50
      DateTime :created_at,    null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  down do
    drop_table :synapse_mutations
  end
end
