defmodule PairingsEngine do
  @moduledoc """
  PairingsEngine keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # Who signs the program: the printout footer and Settings > About. One
  # place, because the title in front of the name is expected to change.
  @author "NA Jorian Burssens"

  @doc "The author's name as it is credited, title included."
  def author, do: @author
end
