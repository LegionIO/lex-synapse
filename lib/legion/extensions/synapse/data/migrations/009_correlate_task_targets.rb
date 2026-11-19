# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:synapse_signals) do
      add_column :target_runner_class, String
      add_column :target_function, String
      add_index :task_id
    end
  end
end
