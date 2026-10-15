defmodule Ironhold.Ingestion.Signature do
  @moduledoc """
  Verifies Tidewake webhook signatures from explicit request values.

  This module does not read configuration or the system clock. Callers provide
  the exact body bytes, shared secret, and current Unix time.
  """

  @max_past_age_seconds 300
  @max_future_skew_seconds 30
  @signature_prefix "v1="
  @hex_digest_size 64
  @minimum_secret_size 32
  @invalid_signature {:error, :invalid_signature}

  @doc """
  Verifies a version 1 signature and returns normalized authenticated values.

  Every invalid input or failed check returns `{:error, :invalid_signature}`.
  """
  @spec verify(binary(), binary(), binary(), binary(), binary(), integer()) ::
          {:ok, %{event_id: binary(), signed_at: non_neg_integer()}}
          | {:error, :invalid_signature}
  def verify(header_id, timestamp, signature, body, secret, current_time) do
    with true <- valid_id?(header_id),
         {:ok, signed_at} <- parse_timestamp(timestamp),
         true <- valid_current_time?(current_time),
         true <- inside_time_window?(signed_at, current_time),
         true <- valid_signature_format?(signature),
         true <- is_binary(body),
         true <- valid_secret?(secret),
         true <- signature_matches?(signature, header_id, timestamp, body, secret) do
      {:ok, %{event_id: header_id, signed_at: signed_at}}
    else
      _invalid -> @invalid_signature
    end
  end

  @doc """
  Returns when a successfully authenticated signing timestamp leaves the
  accepted past-age window.
  """
  @spec acceptance_expires_at(integer()) ::
          {:ok, DateTime.t()} | {:error, :invalid_signed_at | :invalid_unix_time}
  def acceptance_expires_at(signed_at) when is_integer(signed_at) and signed_at >= 0 do
    DateTime.from_unix(signed_at + @max_past_age_seconds)
  end

  def acceptance_expires_at(_signed_at), do: {:error, :invalid_signed_at}

  defp valid_id?(header_id), do: is_binary(header_id) and byte_size(header_id) > 0

  defp parse_timestamp(timestamp) when is_binary(timestamp) and byte_size(timestamp) > 0 do
    if decimal_digits?(timestamp) do
      {:ok, String.to_integer(timestamp)}
    else
      :error
    end
  end

  defp parse_timestamp(_timestamp), do: :error

  defp decimal_digits?(value) do
    value
    |> :binary.bin_to_list()
    |> Enum.all?(&(&1 in ?0..?9))
  end

  defp valid_current_time?(current_time), do: is_integer(current_time) and current_time >= 0

  defp inside_time_window?(signed_at, current_time) do
    signed_at >= current_time - @max_past_age_seconds and
      signed_at <= current_time + @max_future_skew_seconds
  end

  defp valid_signature_format?(@signature_prefix <> digest)
       when byte_size(digest) == @hex_digest_size do
    lowercase_hex?(digest)
  end

  defp valid_signature_format?(_signature), do: false

  defp lowercase_hex?(<<>>), do: true

  defp lowercase_hex?(<<byte, rest::binary>>)
       when byte in ?0..?9 or byte in ?a..?f do
    lowercase_hex?(rest)
  end

  defp lowercase_hex?(_digest), do: false

  defp valid_secret?(secret), do: is_binary(secret) and byte_size(secret) >= @minimum_secret_size

  defp signature_matches?(signature, header_id, timestamp, body, secret) do
    expected = expected_signature(header_id, timestamp, body, secret)

    byte_size(signature) == byte_size(expected) and
      Plug.Crypto.secure_compare(signature, expected)
  end

  defp expected_signature(header_id, timestamp, body, secret) do
    canonical = IO.iodata_to_binary(["v1.", header_id, ".", timestamp, ".", body])

    digest =
      :crypto.mac(:hmac, :sha256, secret, canonical)
      |> Base.encode16(case: :lower)

    @signature_prefix <> digest
  end
end
