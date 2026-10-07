defmodule ZiwoasWeb.Components.Shading do
  @moduledoc """
  The shading report of the PV page: yield map, daily profiles and panel
  curves, or one empty state while there is no PV hour.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.Components.DailyProfiles
  import ZiwoasWeb.Components.PanelCurves
  import ZiwoasWeb.Components.YieldMap

  alias Ziwoas.Shading

  attr :report, Shading.Report, required: true

  def shading(assigns) do
    ~H"""
    <%= if Shading.Report.empty?(@report) do %>
      <section class="card card-body mb-3 empty-state">
        <h2 class="card-title">Noch keine Ausbeute</h2>
        <p>Die Karte erscheint, sobald die ersten Stundenwerte der PV-Leistung vorliegen.</p>
      </section>
    <% else %>
      <div class="sun-charts shading">
        <.yield_map map={@report.map} />
        <.daily_profiles profiles={@report.profiles} />
        <.panel_curves panels={@report.panels} />
      </div>
    <% end %>
    """
  end
end
