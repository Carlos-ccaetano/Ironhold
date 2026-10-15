defmodule Ironhold.Webhooks.WebhookReplayClaim do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @fingerprint_length 64
  @fingerprint_format ~r/\A[0-9a-f]{64}\z/
  @required_fields [:fingerprint, :expires_at]
  @timestamps_opts [type: :utc_datetime_usec]

  schema "webhook_replay_claims" do
    field :fingerprint, :string
    field :expires_at, :utc_datetime_usec

    timestamps(updated_at: false)
  end

  def changeset(webhook_replay_claim, attrs) do
    webhook_replay_claim
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:fingerprint, is: @fingerprint_length)
    |> validate_format(:fingerprint, @fingerprint_format)
    |> unique_constraint(:fingerprint)
    |> check_constraint(:fingerprint, name: :webhook_replay_claims_fingerprint_format)
  end
end
