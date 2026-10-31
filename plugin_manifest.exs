defmodule PairingsEngine.PluginManifest do
  @moduledoc """
  Reads a plugin's `openpairings_plugin.exs`. Lives outside `lib/` because
  `mix.exs` needs it before anything is compiled; see `PairingsEngine.Plugin`
  for the manifest's keys.
  """

  @doc """
  Turns the keyword list a manifest evaluates to into the plugin map the
  build uses, raising `ArgumentError` - naming the manifest - when a key is
  missing or wrong. `dir` is the plugin's checkout.
  """
  def parse(opts, dir) when is_list(opts) do
    manifest = Path.join(dir, "openpairings_plugin.exs")

    name = fetch!(opts, :name, manifest)
    module = fetch!(opts, :module, manifest)

    unless is_atom(name) and is_atom(module) do
      raise ArgumentError,
            "#{manifest}: :name and :module must be atoms, got #{inspect(name)} and #{inspect(module)}"
    end

    applications = Keyword.get(opts, :applications, [])

    unless is_list(applications) and Enum.all?(applications, &is_atom/1) do
      raise ArgumentError,
            "#{manifest}: :applications must be a list of OTP application names " <>
              "(atoms), got #{inspect(applications)}"
    end

    %{name: name, module: module, applications: applications, path: Path.expand(dir)}
  end

  def parse(other, dir) do
    raise ArgumentError,
          "#{Path.join(dir, "openpairings_plugin.exs")} must evaluate to a keyword list, " <>
            "got #{inspect(other)}"
  end

  # The plugins a DESKTOP build may carry: the hall programs' (Polis, the
  # print station; Nunki, the announcer), which run on the same PC as a
  # desktop OpenPairings and have nothing to connect to without it. Every
  # other plugin - the private, national and server-side ones - is the
  # hosted edition's alone, and a desktop build asked to include one stops
  # instead of shipping it to every arbiter's laptop.
  @desktop_plugins [:openpairings_polis, :openpairings_nunki]

  @doc "Whether the plugin called `name` may be built into the desktop edition."
  def desktop_allowed?(name), do: name in @desktop_plugins

  @doc """
  Stops the build when `plugin` may not be part of `edition`: anything but a
  hall plug-in in the desktop edition. The hosted edition takes every plugin.
  """
  def check_edition!(plugin, "hosted"), do: plugin

  def check_edition!(plugin, "desktop") do
    unless desktop_allowed?(plugin.name) do
      raise ArgumentError,
            "plugin #{inspect(plugin.name)} (#{plugin.path}) is for the hosted edition only; " <>
              "the desktop edition builds in " <>
              Enum.map_join(@desktop_plugins, " and ", &inspect/1) <> " and nothing else"
    end

    plugin
  end

  defp fetch!(opts, key, manifest) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "#{manifest}: the :#{key} key is missing"
    end
  end
end
