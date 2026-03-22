# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:synapse_challenges) do
      primary_key :id
      foreign_key :proposal_id, :synapse_proposals, null: false, index: true
      String     :challenger_type, null: false, size: 50
      String     :verdict, null: false, size: 50
      String     :reasoning, text: true
      Float      :challenger_confidence, default: 0.5
      DateTime   :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime   :resolved_at
      String     :outcome, size: 50
    end

    alter_table(:synapse_proposals) do
      add_column :challenge_state, String, size: 50
      add_column :challenge_score, Float
      add_column :impact_score, Float
    end
  end

  down do
    drop_table :synapse_challenges

    alter_table(:synapse_proposals) do
      drop_column :challenge_state
      drop_column :challenge_score
      drop_column :impact_score
    end
  end
end
