defmodule Ironhold.Webhooks.ReplayFingerprint do
  @moduledoc """
  Derives an irreversible replay fingerprint from an authenticated signature.

  Callers must provide the complete, normalized signature value only after
  authentication and temporal validation have succeeded.
  """

  @domain_separator "ironhold:webhook-replay-fingerprint:v1\0"

  @doc """
  Derives a lowercase SHA-256 fingerprint from a validated signature.
  """
  @spec derive(binary()) :: String.t()
  def derive(validated_signature) when is_binary(validated_signature) do
    :sha256
    |> :crypto.hash([@domain_separator, validated_signature])
    |> Base.encode16(case: :lower)
  end
end
