# Interfaz de línea de comandos para operar el sistema de reservas

defmodule CondorDelSur.CLI do
  alias CondorDelSur.{AuditServer, FlightServer, Passenger}

  def main(args \\ []) do
    ttl_ms = parse_ttl(args, 30_000)

    IO.puts("=== Cóndor del Sur — sistema de reservas ===")
    IO.puts("TTL de reservas: #{ttl_ms} ms (#{div(ttl_ms, 1000)} s)")

    %{flight_name: flight_name, flight_pid: flight_pid, audit_pid: audit_pid} =
      CondorDelSur.bootstrap(ttl_ms: ttl_ms)

    flight_ref = Process.monitor(flight_pid)
    audit_ref = Process.monitor(audit_pid)

    IO.puts("Vuelo registrado: #{inspect(flight_name)}")
    IO.puts("Escribí `help` para ver los comandos.\n")

    state = %{
      flight_name: flight_name,
      flight_ref: flight_ref,
      audit_ref: audit_ref
    }

    loop(state)
  end

  defp parse_ttl(args, default) do
    case Enum.find(args, fn a -> String.starts_with?(a, "--ttl=") end) do
      nil -> default
      "--ttl=" <> v -> String.to_integer(v)
    end
  end

  defp loop(state) do
    state = drain_messages(state)

    case IO.gets("> ") do
      :eof ->
        bye()

      {:error, reason} ->
        IO.puts("Error de input: #{inspect(reason)}")
        bye()

      line ->
        case execute(String.trim(line), state) do
          :quit ->
            bye()

          {:cont, new_state} ->
            loop(new_state)
        end
    end
  end

  defp bye, do: IO.puts("Chau.")

  defp execute("", state), do: {:cont, state}

  defp execute("help", state) do
    IO.puts("""

    Comandos:
      help                            -- esta ayuda
      summary                         -- resumen del vuelo
      available                       -- listar asientos disponibles
      add_passenger <id> <name>       -- registrar un pasajero
      reserve <pid> <seat>            -- iniciar reserva del asiento
      pay <res_id>                    -- iniciar pago de la reserva
      cancel <res_id>                 -- cancelar una reserva pendiente
      show <res_id>                   -- ver una reserva
      audit                           -- mostrar el log de auditoría
      quit                            -- salir

    """)

    {:cont, state}
  end

  defp execute("quit", _state), do: :quit
  defp execute("exit", _state), do: :quit

  defp execute("summary", state) do
    IO.inspect(FlightServer.summary(state.flight_name), pretty: true)
    {:cont, state}
  end

  defp execute("available", state) do
    seats = FlightServer.available_seats(state.flight_name)
    IO.puts("Disponibles (#{length(seats)}): #{Enum.join(seats, ", ")}")
    {:cont, state}
  end

  defp execute("audit", state) do
    case AuditServer.dump() do
      {:error, reason} ->
        IO.puts("Audit no disponible: #{inspect(reason)}")

      events ->
        IO.puts("\n--- Audit log (#{length(events)} eventos) ---")

        Enum.each(events, fn e ->
          IO.puts("  [#{e.at}] #{e.type}  #{inspect(e.payload)}")
        end)

        IO.puts("")
    end

    {:cont, state}
  end

  defp execute("add_passenger " <> rest, state) do
    case String.split(rest, " ", parts: 2) do
      [id, name] ->
        case FlightServer.add_passenger(state.flight_name, Passenger.new(id, name)) do
          :ok -> IO.puts("OK: pasajero #{id} (#{name}) registrado")
          {:error, r} -> IO.puts("Error: #{inspect(r)}")
        end

      _ ->
        IO.puts("Uso: add_passenger <id> <name>")
    end

    {:cont, state}
  end

  defp execute("reserve " <> rest, state) do
    case String.split(rest) do
      [pid, seat] ->
        case FlightServer.start_reservation(state.flight_name, pid, seat) do
          {:ok, res_id} -> IO.puts("OK: reserva #{res_id} iniciada (asiento #{seat})")
          {:error, r}   -> IO.puts("Error: #{inspect(r)}")
        end

      _ ->
        IO.puts("Uso: reserve <passenger_id> <seat_code>")
    end

    {:cont, state}
  end

  defp execute("pay " <> rest, state) do
    case String.split(rest) do
      [res_id] ->
        case FlightServer.request_payment(state.flight_name, res_id) do
          :ok ->
            IO.puts("Pago iniciado para #{res_id}. Esperando resultado…")

          {:error, r} ->
            IO.puts("Error: #{inspect(r)}")
        end

      _ ->
        IO.puts("Uso: pay <res_id>")
    end

    {:cont, state}
  end

  defp execute("cancel " <> rest, state) do
    case String.split(rest) do
      [res_id] ->
        case FlightServer.cancel_reservation(state.flight_name, res_id) do
          :ok         -> IO.puts("OK: reserva #{res_id} cancelada")
          {:error, r} -> IO.puts("Error: #{inspect(r)}")
        end

      _ ->
        IO.puts("Uso: cancel <res_id>")
    end

    {:cont, state}
  end

  defp execute("show " <> rest, state) do
    case String.split(rest) do
      [res_id] ->
        IO.inspect(FlightServer.get_reservation(state.flight_name, res_id), pretty: true)

      _ ->
        IO.puts("Uso: show <res_id>")
    end

    {:cont, state}
  end

  defp execute(other, state) do
    IO.puts("Comando desconocido: #{inspect(other)}. Probá `help`.")
    {:cont, state}
  end

  defp drain_messages(state) do
    receive do
      {:payment_done, res_id, :ok} ->
        IO.puts("\n[ASYNC] Pago de #{res_id}: CONFIRMADO")
        drain_messages(state)

      {:payment_done, res_id, {:error, reason}} ->
        IO.puts("\n[ASYNC] Pago de #{res_id}: RECHAZADO (#{inspect(reason)})")
        drain_messages(state)

      {:DOWN, ref, :process, _pid, reason} when ref == state.flight_ref ->
        IO.puts("\n[ALERTA] FlightServer cayó: #{inspect(reason)}")
        drain_messages(state)

      {:DOWN, ref, :process, _pid, reason} when ref == state.audit_ref ->
        IO.puts("\n[ALERTA] AuditServer cayó: #{inspect(reason)}")
        drain_messages(state)

      _other ->
        drain_messages(state)
    after
      0 -> state
    end
  end
end
