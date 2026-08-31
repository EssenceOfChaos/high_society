defmodule HighSocietyWeb.SupportLive do
  use HighSocietyWeb, :live_view

  alias HighSociety.Support
  alias HighSociety.Support.Report

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Contact support
            <:subtitle>
              Found a bug or have a question? Send us a message and we'll get back to you.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="support_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:name]} type="text" label="Name" required phx-mounted={JS.focus()} />
          <.input field={@form[:email]} type="email" label="Email" autocomplete="email" required />
          <.input field={@form[:message]} type="textarea" label="Message" rows="6" required />

          <.button phx-disable-with="Sending..." class="btn btn-primary w-full">
            Send report
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    default_email =
      case socket.assigns[:current_scope] do
        %{user: %{email: email}} -> email
        _ -> nil
      end

    changeset = Support.change_report(%Report{}, %{"email" => default_email})

    {:ok, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("validate", %{"report" => report_params}, socket) do
    changeset = Support.change_report(%Report{}, report_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"report" => report_params}, socket) do
    case Support.send_report(report_params) do
      {:ok, _report} ->
        {:noreply,
         socket
         |> put_flash(:info, "Thanks! Your message has been sent to our support team.")
         |> push_navigate(to: ~p"/")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "report"))
  end
end
