# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:synapse_signals) do
      add_column :success_credit_pending, TrueClass, null: false, default: false
    end
  end
end
