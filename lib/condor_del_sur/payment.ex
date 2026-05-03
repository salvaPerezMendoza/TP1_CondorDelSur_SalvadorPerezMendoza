# Proceso que simula la validación de pago

defmodule CondorDelSur.Payment do
  @success_rate 0.85

  @min_delay_ms 800
  @max_delay_ms 1_800

  def start(server_name, reservation_id, caller, opts \\ []) do
    spawn(fn ->
      run(server_name, reservation_id, caller, opts)
    end)
  end

  defp run(server_name, reservation_id, caller, opts) do
    delay = Keyword.get(opts, :delay_ms, random_delay())
    Process.sleep(delay)

    result =
      case Keyword.get(opts, :force) do
        nil -> simulate_validation()
        forced -> forced
      end

    send(server_name, {:payment_result, reservation_id, result})
    send(caller, {:payment_done, reservation_id, result})
  end

  defp random_delay, do: Enum.random(@min_delay_ms..@max_delay_ms)

  defp simulate_validation do
    if :rand.uniform() <= @success_rate do
      :ok
    else
      {:error, Enum.random([:card_declined, :insufficient_funds, :network_error])}
    end
  end
end
