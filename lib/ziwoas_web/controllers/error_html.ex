defmodule ZiwoasWeb.ErrorHTML do
  use ZiwoasWeb, :html

  def config_error(assigns) do
    ~H"""
    <main id="main" class="mx-auto max-w-3xl px-4 py-12 sm:px-6 lg:px-8">
      <.plush name="zipfelmaus" size={:xl} class="mb-4" />
      <.header>
        ZiWoAS kann die Gerätekonfiguration nicht laden
        <:subtitle>
          Bis sie korrigiert und die App neu gestartet ist, laufen keine Messungen und Jobs.
        </:subtitle>
      </.header>
      <.alert tone={:error} title="Fehler in der Gerätekonfiguration">
        <pre id="config-error" class="mt-1 font-mono text-sm whitespace-pre-wrap">{@message}</pre>
      </.alert>
    </main>
    """
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
