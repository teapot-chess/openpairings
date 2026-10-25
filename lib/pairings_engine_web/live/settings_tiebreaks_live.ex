defmodule PairingsEngineWeb.SettingsTiebreaksLive do
  @moduledoc """
  The "Tie-breaks" settings page (`/t/:id/settings/tiebreaks`): the ordered
  list that separates players level on points, the presets and the builder
  that put things on it, how an unrated player is counted, and whether
  players still level share a place. It used to be a card on the Tournament
  page and saved with it; it now saves on its own, through the same
  `Tournaments.update_tournament/2` and the same audit entry.

  In FIDE mode the list is locked once round 1 is paired
  (`Tournaments.fide_locked_fields/1`), and the whole editor goes with it.
  """
  use PairingsEngineWeb, :live_view

  import PairingsEngineWeb.SettingsSupport

  alias PairingsEngine.{Tournaments, Tiebreaks}
  alias PairingsEngine.Tiebreaks.Builder

  # SWAR §5.22 Tie-break Presets (TB_PERSONEL) - see the original SettingsLive
  # for the best-effort mapping rationale onto our own catalogue codes.
  @tb_presets [
    {"fide_rr", gettext_noop("FIDE Round Robin"), ~w(DE WIN SB KS)},
    {"disparate_sw", gettext_noop("Disparate Swiss (wide rating range)"), ~w(BHC1 BH SB)},
    {"regular_sw", gettext_noop("Regular Swiss"), ~w(BHC1 BH PS)},
    {"old_sw", gettext_noop("Old Swiss (classic)"), ~w(PS BH SB)}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    tournament = Tournaments.get_authorized_tournament!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(PairingsEngine.PubSub, Tournaments.tournament_topic(tournament.id))
    end

    {:ok,
     socket
     |> attach_dirty_tracker()
     |> attach_advanced()
     |> assign(
       tournament: tournament,
       page_title: "#{tournament.name} · " <> gettext("Tie-breaks"),
       tiebreaks: tournament.tiebreaks,
       tb_state: Builder.initial(tournament.type),
       fide_locked: Tournaments.fide_locked_fields(tournament),
       note: nil,
       error: nil,
       dirty: false,
       stale: false
     )}
  end

  @impl true
  def handle_info({:tournament_changed, _id, _hint}, %{assigns: %{dirty: true}} = socket) do
    handle_stale_check(socket)
  end

  def handle_info({:tournament_changed, _id, _hint}, socket) do
    case Tournaments.get_authorized_tournament(
           socket.assigns.current_scope,
           socket.assigns.tournament.id
         ) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("This tournament was deleted."))
         |> push_navigate(to: ~p"/")}

      tournament ->
        {:noreply,
         assign(socket,
           tournament: tournament,
           tiebreaks: tournament.tiebreaks,
           fide_locked: Tournaments.fide_locked_fields(tournament),
           stale: false
         )}
    end
  end

  @impl true
  def handle_event("tb_up", %{"index" => index}, socket) do
    {:noreply,
     assign(socket,
       tiebreaks: swap(socket.assigns.tiebreaks, String.to_integer(index), -1),
       note: nil
     )}
  end

  def handle_event("tb_down", %{"index" => index}, socket) do
    {:noreply,
     assign(socket,
       tiebreaks: swap(socket.assigns.tiebreaks, String.to_integer(index), 1),
       note: nil
     )}
  end

  def handle_event("tb_remove", %{"code" => code}, socket) do
    {:noreply, assign(socket, tiebreaks: List.delete(socket.assigns.tiebreaks, code), note: nil)}
  end

  # The builder: every change re-reads the whole form, so what is shown is
  # always what the server composed.
  def handle_event("tb_family", %{"family" => family}, socket),
    do: {:noreply, tb_update(socket, %{"family" => family})}

  def handle_event("tb_set", %{"field" => field, "option" => value}, socket),
    do: {:noreply, tb_update(socket, %{field => value})}

  def handle_event("tb_toggle", %{"field" => field}, socket) do
    on = if socket.assigns.tb_state[field] == "true", do: "false", else: "true"
    {:noreply, tb_update(socket, %{field => on})}
  end

  def handle_event("tb_factor", %{"factor" => value}, socket),
    do: {:noreply, tb_update(socket, %{"factor" => value})}

  def handle_event("tb_add_built", _params, socket) do
    type = socket.assigns.tournament.type
    state = socket.assigns.tb_state

    with {:ok, code} <- Builder.compose(type, state),
         false <- code in socket.assigns.tiebreaks do
      {:noreply,
       assign(socket, tiebreaks: socket.assigns.tiebreaks ++ [code], tb_state: state, note: nil)}
    else
      _ -> {:noreply, assign(socket, tb_state: state)}
    end
  end

  def handle_event("tb_reset", _params, socket) do
    {:noreply,
     assign(socket, tiebreaks: Tiebreaks.fide_defaults_for(socket.assigns.tournament), note: nil)}
  end

  def handle_event("tb_preset", %{"key" => "personel"}, socket), do: {:noreply, socket}

  def handle_event("tb_preset", %{"key" => key}, socket) do
    case Enum.find(@tb_presets, fn {k, _label, _methods} -> k == key end) do
      nil -> {:noreply, socket}
      {_key, _label, methods} -> {:noreply, assign(socket, tiebreaks: methods, note: nil)}
    end
  end

  ## ---------- Save ----------

  def handle_event("save", %{"tournament" => params}, socket) do
    # The list, plus the three settings beside it and nothing else: this page
    # must not be a way to write the rest of the tournament. A list FIDE mode
    # holds (`Tournaments.fide_locked_fields/1`) is not sent at all, so the
    # other settings still save.
    params = Map.take(params, ~w(tiebreak_unrated_method tiebreak_unrated_rating shared_places))

    params =
      if :tiebreaks in socket.assigns.fide_locked,
        do: params,
        else: Map.put(params, "tiebreaks", socket.assigns.tiebreaks)

    base = Tournaments.get_tournament!(socket.assigns.tournament.id)

    case Tournaments.update_tournament(base, params) do
      {:ok, tournament} ->
        log_settings_change(socket, base, tournament)

        {:noreply,
         assign(socket,
           tournament: tournament,
           tiebreaks: tournament.tiebreaks,
           fide_locked: Tournaments.fide_locked_fields(tournament),
           note: gettext("Saved."),
           error: nil,
           dirty: false,
           stale: false
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, error: error_text(changeset), note: nil)}
    end
  end

  ## ---------- helpers ----------

  defp swap(list, index, delta) do
    target = index + delta

    if target < 0 or target >= length(list) do
      list
    else
      a = Enum.at(list, index)
      b = Enum.at(list, target)
      list |> List.replace_at(index, b) |> List.replace_at(target, a)
    end
  end

  # The advanced half of this page: how unrated players count, and shared
  # places.
  defp advanced_changed(tournament) do
    changed_count(tournament, [:tiebreak_unrated_method, :tiebreak_unrated_rating, :shared_places])
  end

  defp tb_presets,
    do:
      for(
        {key, label, methods} <- @tb_presets,
        do: {key, Gettext.gettext(PairingsEngineWeb.Gettext, label), methods}
      )

  defp tb_preset_match(tiebreaks) do
    Enum.find_value(@tb_presets, "personel", fn {key, _label, methods} ->
      if tiebreaks == methods, do: key
    end)
  end

  # `selectable/1`, not `catalogue/0`: an individual tournament is offered
  # exactly what it was before team standings existed, and a team tournament
  # the breaks `PairingsEngine.TeamStandings` calculates. Offering anything
  # else is offering a column of noughts that decides nothing. See
  # PairingsEngine.Tiebreaks.
  defp tb_families(type), do: Builder.families(type)

  # A change of family starts from that family's defaults; any other change
  # keeps the rest of the state, and `Builder.normalize/2` drops what the
  # family does not accept.
  defp tb_update(socket, change) do
    type = socket.assigns.tournament.type
    base = if Map.has_key?(change, "family"), do: %{}, else: socket.assigns.tb_state
    assign(socket, tb_state: Builder.normalize(type, Map.merge(base, change)))
  end

  # `{:ok, code}` / `{:error, reason}` for the builder as it stands, with the
  # reason an Add button that cannot be pressed gives.
  defp tb_candidate(type, state, selected) do
    case Builder.compose(type, state) do
      {:ok, code} ->
        if code in selected,
          do: {:error, :duplicate, code},
          else: {:ok, code}

      {:error, :factor} ->
        {:error, :factor, nil}

      _ ->
        {:error, :invalid, nil}
    end
  end

  defp tb_reason(:duplicate), do: gettext("Already in the list.")
  defp tb_reason(:factor), do: gettext("The normalising factor is a whole number from 1.")
  defp tb_reason(:invalid), do: gettext("This combination is not a tie-break.")

  defp tb_spec(type, state), do: Builder.spec(type, state["family"]) || %{}

  defp tb_cut_label(""), do: gettext("None")
  defp tb_cut_label("C1"), do: gettext("Cut-1")
  defp tb_cut_label("C2"), do: gettext("Cut-2")
  defp tb_cut_label("M1"), do: gettext("Median-1")
  defp tb_cut_label("M2"), do: gettext("Median-2")

  defp tb_limit_label(""), do: gettext("50%")
  defp tb_limit_label("L1"), do: gettext("50% + 1/2")
  defp tb_limit_label("L2"), do: gettext("50% + 1")
  defp tb_limit_label("L-1"), do: gettext("50% - 1/2")
  defp tb_limit_label("L-2"), do: gettext("50% - 1")

  defp tb_variant_label(""), do: gettext("Direct encounter only")
  defp tb_variant_label("BT"), do: gettext("then Board Count and Top Board Results")
  defp tb_variant_label("BB"), do: gettext("then Board Count and Bottom Board Elimination")
  defp tb_variant_label("T"), do: gettext("then Top Board Results")
  defp tb_variant_label("B"), do: gettext("then Bottom Board Elimination")

  defp tb_ref_label("MP"), do: gettext("Match points")
  defp tb_ref_label("GP"), do: gettext("Game points")

  defp tb_group_label(:results), do: gettext("Results and games")
  defp tb_group_label(:buchholz), do: gettext("Buchholz")
  defp tb_group_label(:sonneborn), do: gettext("Sonneborn-Berger and Koya")
  defp tb_group_label(:progressive), do: gettext("Progressive score")
  defp tb_group_label(:rating), do: gettext("Rating-based")
  defp tb_group_label(:team), do: gettext("Team events")

  defp tb_name(code), do: (Tiebreaks.get(code) || %{name: code}).name
  defp tb_desc(code), do: (Tiebreaks.get(code) || %{description: ""}).description

  attr :state, :map, required: true
  attr :type, :string, required: true
  attr :selected, :list, required: true

  # Adding a tie-break in two steps: the family, then only the modifiers it
  # accepts, with the code that comes out shown before it is added. The
  # controls sit inside the settings form, so they are plain inputs with
  # their own events rather than a form of their own (forms do not nest).
  defp tb_builder(assigns) do
    spec = tb_spec(assigns.type, assigns.state)
    candidate = tb_candidate(assigns.type, assigns.state, assigns.selected)

    assigns =
      assign(assigns,
        spec: spec,
        candidate: candidate,
        families: tb_families(assigns.type)
      )

    ~H"""
    <div id="tiebreak-builder" class="tb-builder">
      <div class="tb-head">
        <h3 id="tb-builder-title" class="tb-title">{gettext("Add a tie-break")}</h3>

        <p class="tb-intro">
          {gettext(
            "Build one in two steps; it goes to the bottom of the list above, where you can move it."
          )}
        </p>
      </div>

      <p class="tb-step">
        <span class="tb-step-n">1</span> {gettext("Choose the tie-break")}
      </p>

      <select
        id="tb-family"
        name="family"
        class="pe-select"
        style="width: auto; max-width: 100%"
        phx-change="tb_family"
        aria-label={gettext("Tie-break")}
      >
        <optgroup :for={{group, list} <- @families} label={tb_group_label(group)}>
          <option :for={{id, label} <- list} value={id} selected={@state["family"] == id}>
            {id} - {label}
          </option>
        </optgroup>
      </select>

      <p
        :if={
          @spec[:cuts] || @spec[:refs] || @spec[:limits] || @spec[:variants] || @spec[:forfeits?] ||
            @spec[:fore?] || @spec[:factor?] || @spec[:reversed?]
        }
        class="tb-step"
      >
        <span class="tb-step-n">2</span> {gettext("Adjust it")}
      </p>

      <.tb_choice
        :if={@spec[:refs] && length(@spec[:refs]) > 1}
        id="tb-ref"
        field="ref"
        label={gettext("Score basis")}
        value={@state["ref"]}
        options={for r <- @spec[:refs], do: {r, tb_ref_label(r)}}
      />
      <.tb_choice
        :if={@spec[:variants]}
        id="tb-variant"
        field="variant"
        label={gettext("Then")}
        value={@state["variant"]}
        options={for v <- @spec[:variants], do: {v, tb_variant_label(v)}}
      />
      <.tb_choice
        :if={@spec[:cuts]}
        id="tb-cut"
        field="cut"
        label={gettext("Cut or median")}
        value={@state["cut"]}
        options={for c <- @spec[:cuts], do: {c, tb_cut_label(c)}}
      />
      <.tb_choice
        :if={@spec[:limits]}
        id="tb-limit"
        field="limit"
        label={gettext("Koya limit")}
        value={@state["limit"]}
        options={for l <- @spec[:limits], do: {l, tb_limit_label(l)}}
      />
      <div class="tb-flags">
        <label :if={@spec[:forfeits?]} for="tb-forfeits">
          <input
            type="checkbox"
            id="tb-forfeits"
            checked={@state["forfeits"] == "true"}
            phx-click="tb_toggle"
            phx-value-field="forfeits"
          /> {gettext("Forfeits count as games")}
        </label>

        <label :if={@spec[:fore?]} for="tb-fore">
          <input
            type="checkbox"
            id="tb-fore"
            checked={@state["fore"] == "true"}
            phx-click="tb_toggle"
            phx-value-field="fore"
          /> {gettext("Fore (the last round counted as a draw)")}
        </label>

        <label :if={@spec[:reversed?]} for="tb-reversed">
          <input
            type="checkbox"
            id="tb-reversed"
            checked={@state["reversed"] == "true"}
            phx-click="tb_toggle"
            phx-value-field="reversed"
          /> {gettext("Reversed (the lower, the better)")}
        </label>
      </div>

      <div :if={@spec[:factor?]} class="tb-field">
        <label for="tb-factor">{gettext("Normalising factor (optional)")}</label>
        <input
          type="number"
          inputmode="numeric"
          id="tb-factor"
          name="factor"
          min="1"
          step="1"
          class="pe-input"
          style="width: 7em"
          value={@state["factor"]}
          phx-change="tb_factor"
          onkeydown="if (event.key === 'Enter') event.preventDefault()"
        />
      </div>

      <div id="tb-preview" class="tb-preview">
        <%= case @candidate do %>
          <% {:ok, code} -> %>
            <code id="tb-preview-code">{Builder.c07(@type, code)}</code>
            <span id="tb-preview-name">{tb_name(code)}</span>
          <% {:error, _reason, code} when is_binary(code) -> %>
            <code id="tb-preview-code">{Builder.c07(@type, code)}</code>
            <span id="tb-preview-name">{tb_name(code)}</span>
          <% _ -> %>
            <span id="tb-preview-name">&nbsp;</span>
        <% end %>
      </div>

      <div class="tb-add-row">
        <button
          type="button"
          id="tb-add"
          class="pe-btn tb-add"
          phx-click="tb_add_built"
          disabled={match?({:error, _, _}, @candidate)}
        >
          {gettext("Add tie-break")}
        </button>

        <span
          :if={match?({:error, _, _}, @candidate)}
          id="tb-add-reason"
          class="hint"
          role="status"
        >
          {tb_reason(elem(@candidate, 1))}
        </span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp tb_choice(assigns) do
    ~H"""
    <div class="tb-field" id={@id}>
      <span class="tb-field-label">{@label}</span>
      <div class="tb-seg" role="group" aria-label={@label}>
        <button
          :for={{val, text} <- @options}
          type="button"
          id={"#{@id}-#{if(val == "", do: "none", else: String.downcase(val))}"}
          class={["tb-seg-btn", @value == val && "is-on"]}
          aria-pressed={to_string(@value == val)}
          phx-click="tb_set"
          phx-value-field={@field}
          phx-value-option={val}
        >
          {text}
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      publish_status={assigns[:publish_status]}
      update_notice={assigns[:update_notice]}
      fide_notice={assigns[:fide_notice]}
      flash={@flash}
      current_path={assigns[:current_path]}
      current_scope={@current_scope}
      tournament={@tournament}
      active="settings"
    >
      <.settings_page
        guard
        tournament={@tournament}
        current_scope={@current_scope}
        active={:tiebreaks}
        subtitle={gettext("Settings - Tie-breaks")}
        show_status={false}
        advanced={advanced(@show_advanced, advanced_changed(@tournament))}
      >
        <.stale_banner stale={@stale} />
        <form id="tiebreaks-settings-form" phx-submit="save">
          <div class="card">
            <h2>{gettext("Tiebreaks")}</h2>

            <p class="hint" style="margin-top: 0">
              {gettext(
                "Applied in order, following the FIDE Tie-Break Regulations. Higher in the list = decided first."
              )}
            </p>

            <.fide_lock_note
              id="tiebreaks-fide-lock"
              tournament={@tournament}
              fide_locked={@fide_locked}
              fields={[:tiebreaks]}
            />
            <%!-- A disabled fieldset disables every control inside it, the
                move/remove buttons and the presets included. --%>
            <fieldset
              id="tiebreak-editor"
              disabled={:tiebreaks in @fide_locked}
              style="border: 0; padding: 0; margin: 0; min-width: 0"
            >
              <%!-- A div, not <.setting_field>: that renders a <label>, which would
                make the "Preset" text toggle whichever radio it wrapped. --%>
              <div class="set-field solo">
                <span class="set-label">{gettext("Preset")}</span>
                <div class="radio-row">
                  <label>
                    <input
                      type="radio"
                      name="tb_preset_display"
                      phx-click="tb_preset"
                      phx-value-key="personel"
                      checked={tb_preset_match(@tiebreaks) == "personel"}
                    /> {gettext("Custom")}
                  </label>

                  <label :for={{key, label, _methods} <- tb_presets()}>
                    <input
                      type="radio"
                      name="tb_preset_display"
                      phx-click="tb_preset"
                      phx-value-key={key}
                      checked={tb_preset_match(@tiebreaks) == key}
                    /> {label}
                  </label>
                </div>
              </div>

              <ol class="tb-list">
                <li :for={{code, i} <- Enum.with_index(@tiebreaks)}>
                  <span class="tb-order">{i + 1}.</span>
                  <div>
                    <div class="tb-name">{tb_name(code)}</div>

                    <div class="tb-desc">{tb_desc(code)}</div>
                  </div>

                  <%!-- Three glyphs, each named for the tiebreak it acts on: a
                    screen reader tabbing down this list otherwise hears "up
                    arrow" eleven times with nothing to say which row it is. --%>
                  <div class="tb-buttons">
                    <button
                      type="button"
                      class="pe-btn"
                      title={gettext("Move up")}
                      aria-label={gettext("Move %{tiebreak} up", tiebreak: tb_name(code))}
                      disabled={i == 0}
                      phx-click="tb_up"
                      phx-value-index={i}
                    >
                      ↑
                    </button>

                    <button
                      type="button"
                      class="pe-btn"
                      title={gettext("Move down")}
                      aria-label={gettext("Move %{tiebreak} down", tiebreak: tb_name(code))}
                      disabled={i == length(@tiebreaks) - 1}
                      phx-click="tb_down"
                      phx-value-index={i}
                    >
                      ↓
                    </button>

                    <button
                      type="button"
                      class="pe-btn"
                      title={gettext("Remove")}
                      aria-label={gettext("Remove %{tiebreak}", tiebreak: tb_name(code))}
                      phx-click="tb_remove"
                      phx-value-code={code}
                    >
                      ✕
                    </button>
                  </div>
                </li>
              </ol>

              <p :if={@tiebreaks == []} class="hint">
                {gettext(
                  "No tiebreaks selected - players level on points are ordered by rating and name."
                )}
              </p>
              <.tb_builder state={@tb_state} type={@tournament.type} selected={@tiebreaks} />
              <div class="actions" style="flex-wrap: wrap">
                <button type="button" class="pe-btn" phx-click="tb_reset">{gettext(
                  "Reset to FIDE default"
                )}</button>
              </div>
            </fieldset>

            <.setting_group class="tset-adv" style="margin-top: 20px">
              <p class="tset-subhead">{gettext("Unrated players and shared places")}</p>

              <.setting_field
                label={gettext("How an unrated player is counted in the tie-breaks")}
                hint={
                  gettext(
                    "Fixed rating: the rating below, and the rating-based tie-breaks are dropped while it is empty. Lowest rating in the field: every unrated player counts as the lowest rating of the tournament. Average rating: as the average of the rated players. The number worked out is the one written to the TRF tie-break line, so a checker computes the same values."
                  )
                }
              >
                <select id="tiebreak-unrated-method" name="tournament[tiebreak_unrated_method]">
                  <option value="fixed" selected={@tournament.tiebreak_unrated_method == "fixed"}>
                    {gettext("Fixed rating")}
                  </option>

                  <option value="lowest" selected={@tournament.tiebreak_unrated_method == "lowest"}>
                    {gettext("Lowest rating in the field")}
                  </option>

                  <option value="average" selected={@tournament.tiebreak_unrated_method == "average"}>
                    {gettext("Average rating of the rated players")}
                  </option>
                </select>
              </.setting_field>

              <.setting_field
                label={gettext("Rating of an unrated player in the tie-breaks")}
                hint={
                  gettext(
                    "C.07 Article 10: with an unrated player in the tournament the rating-based tie-breaks (ARO and its cuts and medians, TPR, PTP, APRO, APPO, RTNG) are dropped, unless the regulations say how unrated players are handled. Leave empty to drop them; enter a rating to count every unrated player as that rating instead. State the rule in the tournament regulations before the first round."
                  )
                }
              >
                <input
                  id="tiebreak-unrated-rating"
                  type="number"
                  name="tournament[tiebreak_unrated_rating]"
                  value={@tournament.tiebreak_unrated_rating}
                  min="0"
                  max="4000"
                />
              </.setting_field>

              <.setting_field
                label={gettext("Players still level share a place")}
                hint={
                  gettext(
                    "C.07 Article 2.1: the regulations say whether tied participants share a place. Off, players still level after the whole tie-break list are put in an order (rating, then name) and numbered one after the other - record a drawing of lots with the manual order. On, they all show the same place, such as 2=, and the next place is skipped accordingly."
                  )
                }
              >
                <input type="hidden" name="tournament[shared_places]" value="false" />
                <input
                  id="shared-places"
                  type="checkbox"
                  name="tournament[shared_places]"
                  value="true"
                  checked={@tournament.shared_places}
                />
              </.setting_field>
            </.setting_group>
          </div>

          <div class="actions form-actions">
            <button type="submit" class="pe-btn primary">{gettext("Save settings")}</button>
            <.save_status note={@note} error={@error} />
          </div>
        </form>
      </.settings_page>
    </Layouts.app>
    """
  end
end
