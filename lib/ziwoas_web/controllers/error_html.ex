defmodule ZiwoasWeb.ErrorHTML do
  use ZiwoasWeb, :html

  def config_error(assigns) do
    ~H"""
    <main class="container py-5">
      <h1 class="h3">ZiWoAS kann die Gerätekonfiguration nicht laden</h1>
      <p>Bis sie korrigiert und die App neu gestartet ist, laufen keine Messungen und Jobs.</p>
      <pre id="config-error" class="alert alert-danger text-wrap">{@message}</pre>
    </main>
    """
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
