defmodule ZiwoasWeb.Components.Shading do
  @moduledoc false
  use ZiwoasWeb, :html

  import ZiwoasWeb.Components.DailyProfiles
  import ZiwoasWeb.Components.PanelCurves
  import ZiwoasWeb.Components.YieldMap

  alias Ziwoas.Shading

  attr :report, Shading.Report, required: true

  def shading(assigns) do
    ~H"""
    <section
      id="shading"
      class={!Shading.Report.empty?(@report) && "sun-charts shading"}
      aria-labelledby="shading-heading"
    >
      <.section_heading id="shading-heading">Ausbeute</.section_heading>
      <.empty_state :if={Shading.Report.empty?(@report)} plush="sun" title="Noch keine Ausbeute">
        Die Karte erscheint, sobald die ersten Stundenwerte der PV-Leistung vorliegen.
      </.empty_state>
      <div :if={!Shading.Report.empty?(@report)} class="flex flex-col gap-3 md:gap-6">
        <.yield_map map={@report.map} />
        <.daily_profiles profiles={@report.profiles} />
        <.panel_curves panels={@report.panels} />
      </div>
    </section>
    """
  end
end
