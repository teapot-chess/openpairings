defmodule PairingsEngine.Fide.Freshness do
  @moduledoc """
  Is the local copy of the FIDE rating list as new as the one FIDE serves?

  One `HEAD` request to the list's URL (`PairingsEngine.Fide.Sync.list_url/0`)
  and a comparison of its `Last-Modified` with the moment the local copy was
  taken - no 41 MB download to find out. Used before a requested rating check
  (an out-of-date list makes the check meaningless) and by
  `PairingsEngine.Fide.AutoSync` to decide whether to download.

  Answers:

    * `:current` - the server's list is not newer than ours
    * `:stale` - it is newer, or the server does not say but our list is from
      an earlier month than this one
    * `:unverified` - nothing has been downloaded yet, or the server could not
      be asked (offline) or does not say and our list is from this month:
      assumed current, but not confirmed

  `Application.get_env(:pairings_engine, :fide_req_options)` is merged into
  the request, so a test can route it to a `Req.Test` stub.
  """

  alias PairingsEngine.Fide
  alias PairingsEngine.Fide.Sync

  @type result :: :current | :stale | :unverified

  @spec check() :: result()
  def check do
    # With no list at all there is nothing to compare, and no question to put
    # to FIDE: `:unverified`. Whoever wants a first download asks for it
    # itself (`PairingsEngine.Fide.AutoSync` does).
    case Fide.last_sync() do
      nil -> :unverified
      last_sync -> check_against(remote_modified(), last_sync, Fide.list_period())
    end
  end

  @doc false
  def check_against({:ok, %DateTime{} = remote}, last_sync, _period) do
    case parse_local(last_sync) do
      %DateTime{} = local -> if DateTime.compare(remote, local) == :gt, do: :stale, else: :current
      nil -> :stale
    end
  end

  def check_against(_unknown, _last_sync, period) do
    this_month = Fide.month_of(Date.utc_today())

    cond do
      not Fide.period?(period) -> :unverified
      period < this_month -> :stale
      true -> :unverified
    end
  end

  @doc "The server's `Last-Modified` for the list, or `{:error, reason}` / `:none`."
  def remote_modified do
    opts =
      [
        method: :head,
        url: Sync.list_url(),
        retry: false,
        connect_options: [timeout: 4_000],
        receive_timeout: 5_000
      ]
      |> Keyword.merge(Application.get_env(:pairings_engine, :fide_req_options, []))

    case Req.request(opts) do
      {:ok, %{status: 200} = resp} ->
        case Req.Response.get_header(resp, "last-modified") do
          [value | _] ->
            case Fide.parse_http_date(value) do
              %DateTime{} = at -> {:ok, at}
              nil -> :none
            end

          _ ->
            :none
        end

      {:ok, %{status: status}} ->
        {:error, {:status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  One `HEAD` request to `url` for the Connections page's Test button: what the
  server answers, in terms a person can act on. A longer timeout than the
  background freshness check, because somebody is waiting and watching.

  `{:ok, %{status: integer, last_modified: String.t() | nil, size: integer | nil}}`
  or `{:error, reason}` for a request that never got an answer.
  """
  def probe(url, timeout_ms \\ 10_000) when is_binary(url) do
    opts =
      [
        method: :head,
        url: url,
        retry: false,
        connect_options: [timeout: timeout_ms],
        receive_timeout: timeout_ms
      ]
      |> Keyword.merge(Application.get_env(:pairings_engine, :fide_req_options, []))

    case Req.request(opts) do
      {:ok, resp} ->
        {:ok,
         %{
           status: resp.status,
           last_modified: first_header(resp, "last-modified"),
           size: resp |> first_header("content-length") |> parse_int()
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp first_header(resp, name) do
    case Req.Response.get_header(resp, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  # `datetime('now')` in SQLite: "YYYY-MM-DD HH:MM:SS", UTC.
  defp parse_local(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      _ -> nil
    end
  end

  defp parse_local(_), do: nil
end
