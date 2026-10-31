defmodule PairingsEngine.PluginManifestTest do
  use ExUnit.Case, async: true

  alias PairingsEngine.PluginManifest

  test "a manifest without applications starts nothing extra" do
    plugin = PluginManifest.parse([name: :demo, module: Demo.Plugin], "somewhere/demo")

    assert plugin.name == :demo
    assert plugin.module == Demo.Plugin
    assert plugin.applications == []
  end

  test "applications are carried through" do
    plugin =
      PluginManifest.parse(
        [name: :demo, module: Demo.Plugin, applications: [:demo_client, :demo_core]],
        "somewhere/demo"
      )

    assert plugin.applications == [:demo_client, :demo_core]
  end

  test "applications that are not a list of atoms stop the build, naming the manifest" do
    for bad <- ["demo_client", [:ok, "no"], :demo_client, [1]] do
      error =
        assert_raise ArgumentError, fn ->
          PluginManifest.parse([name: :demo, module: Demo.Plugin, applications: bad], "x/demo")
        end

      assert error.message =~ "openpairings_plugin.exs"
      assert error.message =~ ":applications"
    end
  end

  test "a missing name or module is named" do
    error =
      assert_raise ArgumentError, fn -> PluginManifest.parse([module: Demo.Plugin], "x/demo") end

    assert error.message =~ ":name key is missing"

    assert_raise ArgumentError, ~r/:module key is missing/, fn ->
      PluginManifest.parse([name: :demo], "x/demo")
    end
  end

  test "a manifest that is not a keyword list is refused" do
    assert_raise ArgumentError, ~r/keyword list/, fn -> PluginManifest.parse(%{}, "x/demo") end
  end

  describe "the desktop edition" do
    test "takes the hall plug-ins" do
      for name <- [:openpairings_polis, :openpairings_nunki] do
        plugin = %{name: name, module: Demo.Plugin, applications: [], path: "x"}
        assert PluginManifest.check_edition!(plugin, "desktop") == plugin
      end
    end

    test "refuses any other plugin, the hosted edition takes it" do
      plugin = %{name: :openpairings_kbsb, module: Demo.Plugin, applications: [], path: "x"}

      assert_raise ArgumentError, ~r/hosted edition only/, fn ->
        PluginManifest.check_edition!(plugin, "desktop")
      end

      assert PluginManifest.check_edition!(plugin, "hosted") == plugin
    end
  end

  describe "bundled migrations" do
    test "a plugin's own path wins, the bundled copy stands in when it is gone" do
      alias PairingsEngine.Plugins

      tmp = Path.join(System.tmp_dir!(), "plugin-mig-2890")
      own = Path.join([tmp, "demo_plugin", "priv", "migrations"])
      File.mkdir_p!(own)
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert Plugins.bundled_or_own(own) == own

      gone = Path.join(["/no/such/checkout", "demo_plugin", "priv", "migrations"])
      bundled = Application.app_dir(:pairings_engine, "priv/plugin_migrations/demo_plugin")
      File.mkdir_p!(bundled)
      on_exit(fn -> File.rm_rf!(bundled) end)

      assert Plugins.bundled_or_own(gone) == bundled
      assert Plugins.bundled_or_own("/no/such/other/priv/migrations") =~ "other/priv/migrations"
    end
  end
end
