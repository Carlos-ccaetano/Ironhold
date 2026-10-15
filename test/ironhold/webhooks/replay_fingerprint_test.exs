defmodule Ironhold.Webhooks.ReplayFingerprintTest do
  use ExUnit.Case, async: true

  alias Ironhold.Webhooks.ReplayFingerprint

  @digest String.duplicate("a", 64)
  @validated_signature "v1=" <> @digest

  test "derives the same fingerprint for the same authenticated signature" do
    assert ReplayFingerprint.derive(@validated_signature) ==
             ReplayFingerprint.derive(@validated_signature)
  end

  test "returns exactly 64 lowercase hexadecimal characters" do
    fingerprint = ReplayFingerprint.derive(@validated_signature)

    assert byte_size(fingerprint) == 64
    assert fingerprint =~ ~r/\A[0-9a-f]{64}\z/
  end

  test "distinguishes different authenticated signatures" do
    other_signature = "v1=" <> String.duplicate("b", 64)

    refute ReplayFingerprint.derive(@validated_signature) ==
             ReplayFingerprint.derive(other_signature)
  end

  test "includes the signature scheme version" do
    version_two_signature = "v2=" <> @digest

    refute ReplayFingerprint.derive(@validated_signature) ==
             ReplayFingerprint.derive(version_two_signature)
  end

  test "does not vary by calling process" do
    expected = ReplayFingerprint.derive(@validated_signature)
    task = Task.async(fn -> ReplayFingerprint.derive(@validated_signature) end)

    assert Task.await(task) == expected
  end
end
