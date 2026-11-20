# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:synapse_proposals) do
      add_column :review_attempts, Integer, null: false, default: 0
      add_column :next_review_at, DateTime
    end
  end
end
