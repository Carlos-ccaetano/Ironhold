defmodule Ironhold.Webhooks.ReceivedWebhook do
  use Ecto.Schema

  import Ecto.Changeset

  @max_string_length 255
  @required_fields [:event_id, :event_type, :payload, :received_at]
  @timestamps_opts [type: :utc_datetime_usec]

  schema "received_webhooks" do
    field :event_id, :string
    field :event_type, :string
    field :payload, :map
    field :received_at, :utc_datetime_usec

    timestamps()
  end

  def changeset(received_webhook, attrs) do
    received_webhook
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:event_id, max: @max_string_length)
    |> validate_length(:event_type, max: @max_string_length)
    |> unique_constraint(:event_id)
  end
end
