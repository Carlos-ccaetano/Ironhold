defmodule Ironhold.Repo.Migrations.CreateReceivedWebhooks do
  use Ecto.Migration

  def change do
    create table(:received_webhooks) do
      add :event_id, :string, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false
      add :received_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:received_webhooks, [:event_id])
  end
end
