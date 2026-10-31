defmodule PairingsEngine.PlayerImport do
  @moduledoc """
  Reads the players of a TRF or CSV file for adding to a tournament that
  already exists (the Players page's "Import players"), as opposed to
  `PairingsEngine.TrfImport.import_text/2`, which makes a whole new one.

  Two steps, neither of which writes anything:

    * `parse/2` reads the file into rows. A row is a string-keyed attribute
      map, the shape the Players page's add form sends to
      `Tournaments.create_player/2`, with the line it came from. A line that
      cannot be read is reported with its number and the reason, and does not
      stop the others.
    * `review/2` sets the rows against the players already in the tournament:
      `%{add: rows, invalid: [...], duplicates: [...]}`. A duplicate has the
      same FIDE ID as a player already there or earlier in the file, or - when
      the row has no FIDE ID - the same name and birth year.

  `add_all/2` then writes the `add` rows in one transaction, each through
  `Tournaments.create_player/2` as the add form does.

  TRF: only the `001` player records are read (`TrfImport.parse_players/1`).
  CSV: the first row names the columns; separator, encoding and quoting are
  read by `PairingsEngine.RatingLists.Csv.read_table/1`, and the field checks
  are that module's. Only a name is required: either a `name` column, or
  `first_name` and `last_name`, which are joined as "Last, First".
  """

  import Ecto.Query, only: [from: 2]

  alias PairingsEngine.RatingLists.Csv
  alias PairingsEngine.{Repo, TrfImport, Tournaments}
  alias PairingsEngine.Tournaments.Player

  @max_bytes 5_000_000
  @max_rows 5_000
  @max_invalid 200

  @aliases %{
    "name" => :name,
    "naam" => :name,
    "nom" => :name,
    "player" => :name,
    "player_name" => :name,
    "full_name" => :name,
    "fullname" => :name,
    "first_name" => :first_name,
    "firstname" => :first_name,
    "first" => :first_name,
    "given_name" => :first_name,
    "voornaam" => :first_name,
    "prenom" => :first_name,
    "pr_nom" => :first_name,
    "last_name" => :last_name,
    "lastname" => :last_name,
    "last" => :last_name,
    "surname" => :last_name,
    "family_name" => :last_name,
    "familyname" => :last_name,
    "achternaam" => :last_name,
    "rating" => :rating,
    "elo" => :rating,
    "cote" => :rating,
    "fide_rating" => :rating,
    "federation" => :federation,
    "fed" => :federation,
    "title" => :title,
    "titel" => :title,
    "birth_year" => :birth_year,
    "birthyear" => :birth_year,
    "birth" => :birth_year,
    "born" => :birth_year,
    "year" => :birth_year,
    "fide_id" => :fide_id,
    "fideid" => :fide_id,
    "fide" => :fide_id,
    "sex" => :sex,
    "gender" => :sex,
    "geslacht" => :sex,
    "sexe" => :sex,
    "club" => :club,
    "national_id" => :national_id,
    "nationalid" => :national_id,
    "national" => :national_id,
    "stamnummer" => :national_id,
    "matricule" => :national_id
  }

  @type row :: %{line: pos_integer(), attrs: %{optional(String.t()) => String.t()}}
  @type parsed :: %{format: :trf | :csv, rows: [row()], invalid: [map()], invalid_more: integer()}

  @doc "The largest file read, in bytes."
  def max_bytes, do: @max_bytes

  @doc "The most rows one import takes."
  def max_rows, do: @max_rows

  @doc """
  Which format `raw` is: `:csv` for a `.csv` name, `:trf` for a `.trf` name,
  and for anything else (`.txt`, no extension) the content decides - a line
  that starts with `001` is a TRF.
  """
  def detect_format(raw, filename \\ "") when is_binary(raw) do
    case filename |> to_string() |> Path.extname() |> String.downcase() do
      ".csv" -> :csv
      ".trf" -> :trf
      _ -> if Regex.match?(~r/^001 /m, raw), do: :trf, else: :csv
    end
  end

  @doc """
  `{:ok, parsed}` or `{:error, message}` when the file as a whole is no use
  (empty, too large, no name column, no `001` records). `parsed.invalid` is
  `[%{line:, reason:}]`, capped at #{@max_invalid}; `invalid_more` is how many
  were left out of it.
  """
  @spec parse(binary(), String.t()) :: {:ok, parsed()} | {:error, String.t()}
  def parse(raw, filename \\ "") when is_binary(raw) do
    if byte_size(raw) > @max_bytes do
      {:error, "This file is larger than #{div(@max_bytes, 1_000_000)} MB."}
    else
      case detect_format(raw, filename) do
        :trf -> parse_trf(raw)
        :csv -> parse_csv(raw)
      end
    end
  end

  @doc "`parse/2` of the file at `path` (an upload's temporary file); `{:error, :unreadable}` when it cannot be read."
  def parse_file(path, filename \\ "") do
    case File.read(path) do
      {:ok, raw} -> parse(raw, filename)
      {:error, _} -> {:error, :unreadable}
    end
  end

  ## ---------- TRF ----------

  defp parse_trf(raw) do
    case TrfImport.parse_players(raw) do
      {:ok, entries} ->
        rows = for {line, {:ok, attrs}} <- entries, do: %{line: line, attrs: attrs}
        invalid = for {line, {:error, reason}} <- entries, do: %{line: line, reason: reason}
        finish(:trf, rows, invalid)

      {:error, reason} ->
        {:error, TrfImport.error_message(reason)}
    end
  end

  ## ---------- CSV ----------

  defp parse_csv(raw) do
    with {:ok, %{header: header, rows: data}} <- csv_table(raw),
         {:ok, columns} <- csv_columns(header),
         :ok <- check_rows(data) do
      {rows, invalid} =
        Enum.reduce(data, {[], []}, fn {line, cells}, {rows, invalid} ->
          case csv_row(cells, columns) do
            {:ok, attrs} -> {[%{line: line, attrs: attrs} | rows], invalid}
            {:error, reason} -> {rows, [%{line: line, reason: reason} | invalid]}
          end
        end)

      finish(:csv, Enum.reverse(rows), Enum.reverse(invalid))
    end
  end

  defp csv_table(raw) do
    case Csv.read_table(raw) do
      {:ok, table} -> {:ok, table}
      {:error, [message | _]} -> {:error, message}
    end
  end

  defp check_rows(data) when length(data) > @max_rows,
    do:
      {:error,
       "The file has #{length(data)} rows; one import takes at most #{@max_rows}. Split it."}

  defp check_rows(_), do: :ok

  defp csv_columns(header) do
    mapped =
      header
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {cell, i}, acc ->
        case Map.get(@aliases, cell) do
          nil -> acc
          field -> Map.put_new(acc, field, i)
        end
      end)

    if Map.has_key?(mapped, :name) or
         (Map.has_key?(mapped, :first_name) and Map.has_key?(mapped, :last_name)) do
      {:ok, mapped}
    else
      {:error,
       "The first row must name the columns, and one of them must be the name " <>
         "(name, or first_name and last_name)."}
    end
  end

  defp csv_row(cells, columns) do
    get = fn field ->
      case Map.fetch(columns, field) do
        {:ok, i} -> cells |> Enum.at(i, "") |> String.trim()
        :error -> ""
      end
    end

    with {:ok, name} <- name(get),
         {:ok, rating} <- Csv.rating(get.(:rating)),
         {:ok, federation} <- Csv.federation(get.(:federation)),
         {:ok, title} <- Csv.title(get.(:title)),
         {:ok, birth_year} <- Csv.birth_year(get.(:birth_year)),
         {:ok, fide_id} <- Csv.fide_id(get.(:fide_id)),
         {:ok, sex} <- sex(get.(:sex)) do
      %{
        "name" => name,
        "fide_rating" => rating,
        "federation" => federation,
        "title" => title,
        "birth_year" => birth_year,
        "fide_id" => fide_id,
        "sex" => sex,
        "club" => get.(:club),
        "national_id" => get.(:national_id)
      }
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new(fn {k, v} -> {k, to_string(v)} end)
      |> validate_attrs()
    end
  end

  defp name(get) do
    full = get.(:name)

    joined =
      case {get.(:last_name), get.(:first_name)} do
        {last, ""} -> last
        {"", first} -> first
        {last, first} -> last <> ", " <> first
      end

    case if(full != "", do: full, else: joined) do
      "" -> {:error, "the name is empty"}
      name -> {:ok, name}
    end
  end

  defp sex(""), do: {:ok, ""}

  defp sex(value) do
    case Player.normalize_sex(value) do
      "" -> {:error, "the sex #{inspect(value)} is not m or w"}
      sex -> {:ok, sex}
    end
  end

  # The schema's own checks (name length and the like), so a row the add form
  # would refuse is listed here instead of failing the whole write.
  defp validate_attrs(attrs) do
    case Player.changeset(%Player{}, attrs) do
      %{valid?: true} ->
        {:ok, attrs}

      changeset ->
        {:error, Enum.map_join(changeset.errors, "; ", fn {f, {msg, _}} -> "#{f} #{msg}" end)}
    end
  end

  defp finish(format, rows, invalid) do
    cond do
      rows == [] and invalid == [] ->
        {:error, "The file holds no players."}

      length(rows) + length(invalid) > @max_rows ->
        {:error,
         "The file has #{length(rows) + length(invalid)} players; one import takes at most " <>
           "#{@max_rows}. Split it."}

      true ->
        {:ok,
         %{
           format: format,
           rows: rows,
           invalid: Enum.take(invalid, @max_invalid),
           invalid_more: max(length(invalid) - @max_invalid, 0)
         }}
    end
  end

  ## ---------- review ----------

  @doc """
  Sets `parsed.rows` against `existing` (see `existing/1`). Returns
  `%{add: [row], duplicates: [row + reason: :fide_id | :name, of: :tournament |
  {:line, n}], invalid: [..], invalid_more: n}`.
  """
  def review(%{rows: rows} = parsed, existing) do
    seed =
      Enum.reduce(existing, empty_index(), fn p, idx ->
        index(idx, p.name, p.fide_id, p.birth_year, :tournament)
      end)

    {add, dupes, _index} =
      Enum.reduce(rows, {[], [], seed}, fn row, {add, dupes, idx} ->
        name = row.attrs["name"]
        fide_id = parse_int(row.attrs["fide_id"])
        birth_year = parse_int(row.attrs["birth_year"])

        case duplicate_of(idx, name, fide_id, birth_year) do
          nil ->
            {[row | add], dupes, index(idx, name, fide_id, birth_year, {:line, row.line})}

          {kind, of} ->
            {add, [Map.merge(row, %{reason: kind, of: of}) | dupes], idx}
        end
      end)

    %{
      add: Enum.reverse(add),
      duplicates: Enum.reverse(dupes),
      invalid: parsed.invalid,
      invalid_more: parsed.invalid_more
    }
  end

  @doc "The players already in the tournament, for `review/2`."
  def existing(tournament_id) do
    Repo.all(
      from p in Player,
        where: p.tournament_id == ^tournament_id,
        select: %{name: p.name, fide_id: p.fide_id, birth_year: p.birth_year}
    )
  end

  defp empty_index, do: %{fide: %{}, name: %{}}

  # FIDE IDs identify a player on their own; a name and a birth year are only
  # looked at for an entry that has no FIDE ID - the same name with two
  # different FIDE IDs is two people.
  defp index(idx, name, fide_id, birth_year, origin) do
    if is_integer(fide_id) do
      %{idx | fide: Map.put_new(idx.fide, fide_id, origin)}
    else
      %{idx | name: Map.put_new(idx.name, {name_key(name), birth_year}, origin)}
    end
  end

  defp duplicate_of(idx, name, fide_id, birth_year) do
    {kind, found} =
      if is_integer(fide_id),
        do: {:fide_id, Map.fetch(idx.fide, fide_id)},
        else: {:name, Map.fetch(idx.name, {name_key(name), birth_year})}

    case found do
      {:ok, of} -> {kind, of}
      :error -> nil
    end
  end

  defp name_key(name),
    do: name |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, " ") |> String.trim()

  defp parse_int(nil), do: nil

  defp parse_int(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  ## ---------- write ----------

  @doc """
  Adds `rows` (the `add` list of `review/2`) to the tournament in one
  transaction: `{:ok, [player]}`, or `{:error, {line, reason}}` with nothing
  written (`reason` as `Tournaments.create_player/2` gives it).

  Each row goes through `Tournaments.create_player/2` with the round the add
  form offers in "Joins in round" (`Tournaments.next_start_round/1`), so a
  late entrant is treated as one. Change broadcasts wait for the commit and
  go out once.
  """
  def add_all(tournament_id, rows) do
    start_round = Integer.to_string(Tournaments.next_start_round(tournament_id))

    result =
      Tournaments.with_broadcast_suppressed(fn ->
        Repo.transaction(fn ->
          Enum.map(rows, fn row ->
            case Tournaments.create_player(
                   tournament_id,
                   Map.put(row.attrs, "start_round", start_round)
                 ) do
              {:ok, player} -> player
              {:error, reason} -> Repo.rollback({row.line, reason})
            end
          end)
        end)
      end)

    with {:ok, players} <- result do
      Tournaments.broadcast_tournament_change(tournament_id, :players)
      {:ok, players}
    end
  end
end
