defmodule Ironhold.WebhooksTest do
  use Ironhold.DataCase, async: true

  alias Ironhold.Webhooks
  alias Ironhold.Webhooks.ReceivedWebhook

  @received_at ~U[2026-08-11 12:00:00.000000Z]
  @valid_attrs %{
    event_id: "evt_123",
    event_type: "order.created",
    payload: %{"order_id" => "123"}
  }

  describe "ReceivedWebhook.changeset/2" do
    test "accepts valid attributes" do
      attrs = Map.put(@valid_attrs, :received_at, @received_at)

      assert ReceivedWebhook.changeset(%ReceivedWebhook{}, attrs).valid?
    end

    test "requires every persisted field" do
      changeset = ReceivedWebhook.changeset(%ReceivedWebhook{}, %{})

      assert errors_on(changeset) == %{
               event_id: ["can't be blank"],
               event_type: ["can't be blank"],
               payload: ["can't be blank"],
               received_at: ["can't be blank"]
             }
    end

    test "accepts event id and event type with 255 characters" do
      attrs = %{
        @valid_attrs
        | event_id: String.duplicate("i", 255),
          event_type: String.duplicate("t", 255)
      }

      attrs = Map.put(attrs, :received_at, @received_at)

      assert ReceivedWebhook.changeset(%ReceivedWebhook{}, attrs).valid?
    end

    test "associates length errors with each field" do
      attrs = %{
        @valid_attrs
        | event_id: String.duplicate("i", 256),
          event_type: String.duplicate("t", 256)
      }

      changeset =
        attrs
        |> Map.put(:received_at, @received_at)
        |> then(&ReceivedWebhook.changeset(%ReceivedWebhook{}, &1))

      assert errors_on(changeset) == %{
               event_id: ["should be at most 255 character(s)"],
               event_type: ["should be at most 255 character(s)"]
             }
    end
  end

  describe "receive_webhook/2" do
    test "persists a webhook envelope" do
      assert {:ok, webhook} = Webhooks.receive_webhook(@valid_attrs, @received_at)
      assert webhook.event_id == "evt_123"
      assert webhook.event_type == "order.created"
      assert webhook.payload == %{"order_id" => "123"}
    end

    test "records the supplied receipt time" do
      assert {:ok, webhook} = Webhooks.receive_webhook(@valid_attrs, @received_at)
      assert webhook.received_at == @received_at
    end

    test "rejects a duplicate event id" do
      assert {:ok, _webhook} = Webhooks.receive_webhook(@valid_attrs, @received_at)
      assert {:error, :duplicate_event_id} = Webhooks.receive_webhook(@valid_attrs, @received_at)
    end

    test "does not persist an envelope with fields longer than 255 characters" do
      attrs = %{
        @valid_attrs
        | event_id: String.duplicate("i", 256),
          event_type: String.duplicate("t", 256)
      }

      assert {:error, changeset} = Webhooks.receive_webhook(attrs, @received_at)
      assert Map.has_key?(errors_on(changeset), :event_id)
      assert Map.has_key?(errors_on(changeset), :event_type)
      assert Repo.aggregate(ReceivedWebhook, :count) == 0
    end
  end
end
