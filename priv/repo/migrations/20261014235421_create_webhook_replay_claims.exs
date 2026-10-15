defmodule Ironhold.Repo.Migrations.CreateWebhookReplayClaims do
  use Ecto.Migration

  def change do
    create table(:webhook_replay_claims, primary_key: false) do
      add :fingerprint, :string, size: 64, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:webhook_replay_claims, [:fingerprint])
    create index(:webhook_replay_claims, [:expires_at])

    create constraint(:webhook_replay_claims, :webhook_replay_claims_fingerprint_format,
             check: "char_length(fingerprint) = 64 AND fingerprint ~ '^[0-9a-f]{64}$'"
           )
  end
end
