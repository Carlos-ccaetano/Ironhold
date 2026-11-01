defmodule IronholdWeb.PageControllerTest do
  use IronholdWeb.ConnCase, async: true

  test "GET / presents the implemented webhook receiver", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200) |> String.replace(~r/\s+/, " ")

    for text <- [
          "Receive signed webhooks",
          "Ironhold authenticates webhook requests",
          "Elixir, Phoenix, PostgreSQL, HMAC-SHA256, and ExUnit",
          "Implemented and tested",
          "HMAC-SHA256 over the exact request bytes",
          "timestamp verification",
          "JSON content validation",
          "request size limits",
          "cryptographic replay protection",
          "transactional PostgreSQL persistence",
          "replay claim expiration and supervised cleanup",
          "Telemetry events and metrics",
          "automated tests"
        ] do
      assert html =~ text
    end
  end

  test "GET / distinguishes accepted retries from generic conflicts", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200) |> String.replace(~r/\s+/, " ")

    assert html =~
             "A legitimate retry with a fresh timestamp and signature is not an exact replay."

    assert html =~ "POST /api/webhooks"

    rows = Regex.scan(~r/<tr>.*?<\/tr>/s, html) |> List.flatten()

    assert Enum.any?(rows, &(&1 =~ "First valid webhook" and &1 =~ "202 Accepted"))

    assert Enum.any?(rows, fn row ->
             row =~ "Same event ID, type, and payload with a fresh timestamp and signature" and
               row =~ "202 Accepted"
           end)

    assert Enum.any?(rows, fn row ->
             row =~ "Exact signature replay or the same event ID with conflicting content" and
               row =~ "409 Conflict"
           end)

    assert html =~ "Both conflict cases return the same generic response."
    assert html =~ "An accepted identical retry does not create another stored event."
  end

  test "GET / states pre-release limits and links to the contract and independent sender", %{
    conn: conn
  } do
    html = conn |> get(~p"/") |> html_response(200) |> String.replace(~r/\s+/, " ")

    for text <- [
          "Pre-release",
          "Ingestion rate limiting",
          "signing secret rotation",
          "broader operational auditing and retention",
          "a dashboard",
          "external metrics reporting",
          "alerts remain future work",
          "is not proven; automated tests and green CI do not establish production readiness.",
          "Tidewake produces and sends webhooks; Ironhold is a complementary receiver.",
          "systems and repositories, with no proven joint production deployment."
        ] do
      assert html =~ text
    end

    assert html =~
             ~s(href="https://github.com/Carlos-ccaetano/Ironhold/blob/main/docs/api/webhooks.md")

    assert html =~ ~s(href="https://github.com/Carlos-ccaetano/Tidewake")
  end
end
