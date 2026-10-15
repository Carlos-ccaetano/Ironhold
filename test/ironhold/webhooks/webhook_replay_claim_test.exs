defmodule Ironhold.Webhooks.WebhookReplayClaimTest do
  use Ironhold.DataCase, async: true

  alias Ironhold.Webhooks.WebhookReplayClaim

  @fingerprint String.duplicate("a", 64)
  @expires_at ~U[2026-10-15 12:00:00.000000Z]
  @valid_attrs %{fingerprint: @fingerprint, expires_at: @expires_at}

  describe "changeset/2" do
    test "accepts a lowercase hexadecimal fingerprint and expiration" do
      changeset = WebhookReplayClaim.changeset(%WebhookReplayClaim{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes == @valid_attrs
    end

    test "requires a fingerprint" do
      changeset =
        WebhookReplayClaim.changeset(%WebhookReplayClaim{}, %{expires_at: @expires_at})

      assert errors_on(changeset) == %{fingerprint: ["can't be blank"]}
    end

    test "requires an expiration" do
      changeset =
        WebhookReplayClaim.changeset(%WebhookReplayClaim{}, %{fingerprint: @fingerprint})

      assert errors_on(changeset) == %{expires_at: ["can't be blank"]}
    end

    test "rejects a fingerprint shorter than 64 characters" do
      attrs = %{@valid_attrs | fingerprint: String.duplicate("a", 63)}

      assert "should be 64 character(s)" in fingerprint_errors(attrs)
    end

    test "rejects a fingerprint longer than 64 characters" do
      attrs = %{@valid_attrs | fingerprint: String.duplicate("a", 65)}

      assert "should be 64 character(s)" in fingerprint_errors(attrs)
    end

    test "rejects characters outside lowercase hexadecimal" do
      attrs = %{@valid_attrs | fingerprint: String.duplicate("a", 63) <> "G"}

      assert fingerprint_errors(attrs) == ["has invalid format"]
    end

    test "maps a persisted duplicate to the fingerprint constraint" do
      assert {:ok, _claim} =
               %WebhookReplayClaim{}
               |> WebhookReplayClaim.changeset(@valid_attrs)
               |> Repo.insert()

      assert {:error, changeset} =
               %WebhookReplayClaim{}
               |> WebhookReplayClaim.changeset(@valid_attrs)
               |> Repo.insert()

      assert errors_on(changeset) == %{fingerprint: ["has already been taken"]}
    end
  end

  defp fingerprint_errors(attrs) do
    %WebhookReplayClaim{}
    |> WebhookReplayClaim.changeset(attrs)
    |> errors_on()
    |> Map.fetch!(:fingerprint)
  end
end
