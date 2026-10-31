defmodule PairingsEngine.PlayerImportTest do
  use PairingsEngine.DataCase, async: true

  alias PairingsEngine.{PlayerImport, Tournaments}

  # A `001` record, column by column (TRF16 layout; TRF06 and TRF26 use the
  # same one).
  def trf_line(rank, name, opts \\ []) do
    sex = Keyword.get(opts, :sex, "m")
    title = Keyword.get(opts, :title, "")
    rating = Keyword.get(opts, :rating, 1500)
    fed = Keyword.get(opts, :fed, "BEL")
    fide = Keyword.get(opts, :fide, 0)
    birth = Keyword.get(opts, :birth, "1990-01-01")
    games = Keyword.get(opts, :games, "")

    "001 " <>
      String.pad_leading("#{rank}", 4) <>
      " " <>
      sex <>
      String.pad_leading(title, 3) <>
      " " <>
      String.pad_trailing(name, 33) <>
      " " <>
      String.pad_leading("#{rating}", 4) <>
      " " <>
      String.pad_trailing(fed, 3) <>
      " " <>
      String.pad_leading(if(fide == 0, do: "", else: "#{fide}"), 11) <>
      " " <>
      String.pad_trailing(birth, 10) <>
      " " <>
      "0.0  " <> String.pad_leading("#{rank}", 4) <> "  " <> games
  end

  defp trf(lines), do: Enum.join(lines, "\r\n") <> "\r\n"

  describe "TRF" do
    test "reads the 001 players and ignores everything else" do
      file =
        trf([
          "012 Some Open",
          "022 Brussels",
          trf_line(1, "Claes, Bram", title: "FM", rating: 2250, fide: 201_001, sex: "m"),
          trf_line(2, "Peeters, Eva", rating: 1800, sex: "w", birth: "2001-05-17"),
          "XXR 5",
          "332 BEL"
        ])

      assert {:ok, %{format: :trf, rows: [a, b], invalid: []}} =
               PlayerImport.parse(file, "players.trf")

      assert a.attrs["name"] == "Claes, Bram"
      assert a.attrs["title"] == "FM"
      assert a.attrs["fide_rating"] == "2250"
      assert a.attrs["fide_id"] == "201001"
      assert a.attrs["federation"] == "BEL"
      assert a.attrs["birth_year"] == "1990"
      assert b.attrs["sex"] == "w"
      assert b.attrs["birth_year"] == "2001"
      # The file's own starting rank is not carried over.
      refute Map.has_key?(a.attrs, "pairing_number")
      assert a.line == 3
    end

    test "a file whose rounds and results are nonsense still yields its players" do
      file =
        trf([
          trf_line(1, "Claes, Bram", games: "   2 w 1"),
          trf_line(2, "Peeters, Eva", games: "   9 b Q")
        ])

      assert {:ok, %{rows: [_, _], invalid: []}} = PlayerImport.parse(file, "x.trf")
    end

    test "a file with no 001 records is refused as a whole" do
      assert {:error, message} = PlayerImport.parse("012 Nothing here\r\n", "x.trf")
      assert message =~ "001"
    end

    test "Windows-1252 names are decoded" do
      line = trf_line(1, "Boutchon, Gaetan")
      latin = String.replace(line, "Gaetan", <<"Ga", 0xEB, "tan">>)
      assert {:ok, %{rows: [row]}} = PlayerImport.parse(trf([latin]), "x.txt")
      assert row.attrs["name"] == "Boutchon, Gaëtan"
    end

    test "a .txt file with 001 lines is read as a TRF" do
      assert PlayerImport.detect_format(trf([trf_line(1, "A, B")]), "list.txt") == :trf
      assert PlayerImport.detect_format("name\nA\n", "list.txt") == :csv
      assert PlayerImport.detect_format("name\nA\n", "list") == :csv
    end
  end

  describe "CSV" do
    test "reads a comma file with aliases and optional columns" do
      csv = """
      Naam,ELO,Fed,Titel,FIDE,Born,Gender,Club,National ID
      "Claes, Bram",2250,bel,fm,201001,1990,M,Brussels CC,1234
      Peeters Eva,1800,,,,2001,F,,
      """

      assert {:ok, %{format: :csv, rows: [a, b], invalid: []}} =
               PlayerImport.parse(csv, "p.csv")

      assert a.attrs == %{
               "name" => "Claes, Bram",
               "fide_rating" => "2250",
               "federation" => "BEL",
               "title" => "FM",
               "fide_id" => "201001",
               "birth_year" => "1990",
               "sex" => "m",
               "club" => "Brussels CC",
               "national_id" => "1234"
             }

      assert b.attrs["sex"] == "w"
      assert b.line == 3
    end

    test "semicolon separator and first/last name columns" do
      csv = "First Name;Last Name;Rating\nBram;Claes;2250\nEva;Peeters;\n"

      assert {:ok, %{rows: [a, b]}} = PlayerImport.parse(csv, "p.csv")
      assert a.attrs["name"] == "Claes, Bram"
      assert a.attrs["fide_rating"] == "2250"
      assert b.attrs["name"] == "Peeters, Eva"
      refute Map.has_key?(b.attrs, "fide_rating")
    end

    test "Windows-1252 and a BOM" do
      latin = <<"name;rating\nGa", 0xEB, "tan;1500\n">>
      assert {:ok, %{rows: [row]}} = PlayerImport.parse(latin, "p.csv")
      assert row.attrs["name"] == "Gaëtan"

      with_bom = <<0xEF, 0xBB, 0xBF>> <> "name\nAnna\n"

      assert {:ok, %{rows: [%{attrs: %{"name" => "Anna"}}]}} =
               PlayerImport.parse(with_bom, "p.csv")
    end

    test "a row with no name is invalid and carries its line number" do
      csv = "name,rating\nClaes,1500\n,1400\nPeeters,abc\nVerhoeven,1300\n"

      assert {:ok, %{rows: rows, invalid: invalid}} = PlayerImport.parse(csv, "p.csv")
      assert Enum.map(rows, & &1.attrs["name"]) == ["Claes", "Verhoeven"]
      assert [%{line: 3, reason: r3}, %{line: 4, reason: r4}] = invalid
      assert r3 =~ "name"
      assert r4 =~ "rating"
    end

    test "no name column is refused as a whole" do
      assert {:error, message} = PlayerImport.parse("rating,fed\n1500,BEL\n", "p.csv")
      assert message =~ "name"
    end

    test "an empty file is refused" do
      assert {:error, _} = PlayerImport.parse("", "p.csv")
      assert {:error, _} = PlayerImport.parse("name\n", "p.csv")
    end
  end

  describe "review" do
    setup do
      scope = PairingsEngine.AccountsFixtures.user_scope_fixture()

      {:ok, t} = Tournaments.create_tournament(scope, %{"name" => "Dup", "type" => "swiss"})

      {:ok, _} =
        Tournaments.create_player(t.id, %{
          "name" => "Claes, Bram",
          "fide_id" => "201001",
          "fide_rating" => "2000"
        })

      {:ok, _} =
        Tournaments.create_player(t.id, %{"name" => "Peeters, Eva", "birth_year" => "2001"})

      %{t: t}
    end

    test "skips a repeated FIDE ID, or the same name and birth year when there is no FIDE ID",
         %{t: t} do
      csv = """
      name,fide_id,born
      Somebody Else,201001,1980
      peeters eva,,2001
      Peeters Eva,,1999
      New Person,,
      new  person,,
      With Id,300,
      With Id Again,300,
      """

      {:ok, parsed} = PlayerImport.parse(csv, "p.csv")
      review = PlayerImport.review(parsed, PlayerImport.existing(t.id))

      assert Enum.map(review.add, & &1.attrs["name"]) ==
               ["Peeters Eva", "New Person", "With Id"]

      assert [
               %{line: 2, reason: :fide_id, of: :tournament},
               %{line: 3, reason: :name, of: :tournament},
               %{line: 6, reason: :name, of: {:line, 5}},
               %{line: 8, reason: :fide_id, of: {:line, 7}}
             ] = review.duplicates
    end

    test "add_all writes every row, or none", %{t: t} do
      {:ok, parsed} = PlayerImport.parse("name,rating\nA One,1500\nB Two,1400\n", "p.csv")
      before = length(Tournaments.list_players(t.id))

      assert {:ok, [_, _]} = PlayerImport.add_all(t.id, parsed.rows)
      assert length(Tournaments.list_players(t.id)) == before + 2

      # A row the write refuses (the same FIDE ID as one now in the
      # tournament) takes the rows before it down with it.
      rows = [
        %{line: 2, attrs: %{"name" => "C Three"}},
        %{line: 3, attrs: %{"name" => "Dup", "fide_id" => "201001"}}
      ]

      assert {:error, {3, :duplicate_fide_id}} = PlayerImport.add_all(t.id, rows)
      assert length(Tournaments.list_players(t.id)) == before + 2
    end
  end
end
