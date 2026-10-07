defmodule ZiwoasWeb.LightHTML do
  @moduledoc "A lamp's settings as a page of its own (`lights/edit.html.erb`), the fallback without Turbo."
  use ZiwoasWeb, :html

  import ZiwoasWeb.LightsComponents, only: [light_form: 1]

  def edit(assigns) do
    ~H"""
    <Layouts.app look={@look} current_path={@current_path}>
      <h1 class="h2 mb-3">Lampe bearbeiten</h1>
      <div class="card card-body">
        <.light_form light={@light} plugs={@plugs} errors={@errors} />
      </div>
    </Layouts.app>
    """
  end
end
