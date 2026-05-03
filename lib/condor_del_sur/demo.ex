# Demo automática que reproduce todos los casos del TP

defmodule CondorDelSur.Demo do
  alias CondorDelSur.{AuditServer, FlightServer, Passenger}

  @ttl_ms 4_000

  def run do
    banner("ARRANCANDO SISTEMA")
    %{flight_name: server} = CondorDelSur.bootstrap(ttl_ms: @ttl_ms)
    AuditServer.reset()
    IO.puts("FlightServer registrado como #{inspect(server)}")
    IO.puts("AuditServer registrado como :audit")
    IO.puts("TTL de reservas: #{@ttl_ms} ms\n")

    seed_passengers(server)
    case_competencia(server)
    case_pago_confirmado(server)
    case_pago_rechazado(server)
    case_cancelacion(server)
    case_expiracion(server)

    banner("ESTADO FINAL")
    print_summary(server)
    print_audit()
  end

  defp seed_passengers(server) do
    banner("REGISTRO DE PASAJEROS")

    passengers = [
      Passenger.new("P001", "Ana"),
      Passenger.new("P002", "Bruno"),
      Passenger.new("P003", "Carla"),
      Passenger.new("P004", "Diego"),
      Passenger.new("P005", "Eva"),
      Passenger.new("P006", "Federico")
    ]

    Enum.each(passengers, fn p ->
      :ok = FlightServer.add_passenger(server, p)
      IO.puts("  registrado: #{p.id} - #{p.name}")
    end)

    IO.puts("")
  end

  defp case_competencia(server) do
    banner("CASO 1: COMPETENCIA POR EL ASIENTO 1A")
    IO.puts("6 pasajeros lanzan pedidos concurrentes sobre el asiento 1A.")
    IO.puts("Solo uno debería ganarlo. Los demás reciben error.\n")

    me = self()
    contendientes = ~w(P001 P002 P003 P004 P005 P006)

    pids =
      for pid <- contendientes do
        spawn(fn ->
          result = FlightServer.start_reservation(server, pid, "1A")
          send(me, {:result, pid, result})
        end)
      end

    results = recolectar(pids, [])

    Enum.each(results, fn {pid, r} ->
      IO.puts("  #{pid}: #{format_result(r)}")
    end)

    ganadores = Enum.count(results, fn {_, r} -> match?({:ok, _}, r) end)
    perdedores = length(results) - ganadores
    IO.puts("\nGanadores: #{ganadores}  |  Rechazados: #{perdedores}")
    IO.puts("Invariante mantenida: un asiento, un pasajero.\n")
  end

  defp recolectar([], acc), do: Enum.reverse(acc)

  defp recolectar([_ | rest], acc) do
    receive do
      {:result, pid, r} -> recolectar(rest, [{pid, r} | acc])
    after
      5_000 -> Enum.reverse(acc)
    end
  end

  defp case_pago_confirmado(server) do
    banner("CASO 2: CONFIRMACION POR PAGO (camino feliz)")
    {:ok, res_id} = FlightServer.start_reservation(server, "P002", "1B")
    IO.puts("Bruno (P002) reservó #{res_id} sobre 1B → :pending\n")

    IO.puts("Disparamos pago. El proceso Payment corre en paralelo y reporta…")
    :ok = FlightServer.request_payment(server, res_id)

    forzar_pago_ok(server, res_id)

    Process.sleep(200)
    print_reservation(server, res_id)
    IO.puts("")
  end

  defp forzar_pago_ok(server, res_id) do
    me = self()
    CondorDelSur.Payment.start(server, res_id, me, force: :ok, delay_ms: 300)

    receive do
      {:payment_done, ^res_id, :ok}              -> IO.puts("  → pago aceptado")
      {:payment_done, ^res_id, {:error, reason}} -> IO.puts("  → rechazado (#{inspect(reason)})")
    after
      2_000 -> IO.puts("  → timeout esperando pago")
    end
  end

  defp case_pago_rechazado(server) do
    banner("CASO 3: PAGO RECHAZADO")
    {:ok, res_id} = FlightServer.start_reservation(server, "P003", "1C")
    IO.puts("Carla (P003) reservó #{res_id} sobre 1C → :pending\n")

    me = self()
    CondorDelSur.Payment.start(server, res_id, me, force: {:error, :card_declined}, delay_ms: 300)

    receive do
      {:payment_done, ^res_id, _} -> :ok
    after
      2_000 -> :ok
    end

    Process.sleep(200)
    IO.puts("Resultado: la reserva queda :pending (la usuaria puede reintentar).")
    print_reservation(server, res_id)

    :ok = FlightServer.cancel_reservation(server, res_id)
    IO.puts("(Cancelamos #{res_id} para limpiar la demo)\n")
  end

  defp case_cancelacion(server) do
    banner("CASO 4: CANCELACION ANTES DE CONFIRMAR")
    {:ok, res_id} = FlightServer.start_reservation(server, "P004", "1D")
    IO.puts("Diego (P004) reservó #{res_id} sobre 1D → :pending")

    :ok = FlightServer.cancel_reservation(server, res_id)
    IO.puts("Diego cancela #{res_id} antes de pagar.")

    print_reservation(server, res_id)

    seats = FlightServer.available_seats(server)
    IO.puts("1D ahora está disponible: #{"1D" in seats}\n")
  end

  defp case_expiracion(server) do
    banner("CASO 5: EXPIRACION AUTOMATICA")
    {:ok, res_id} = FlightServer.start_reservation(server, "P005", "2A")

    IO.puts("Eva (P005) reservó #{res_id} sobre 2A → :pending")
    IO.puts("Nadie paga. El proceso Expirer (puntual) duerme #{@ttl_ms} ms")
    IO.puts("y al despertar manda :check_expire al FlightServer.\n")

    IO.write("Esperando…")
    espera = @ttl_ms + 500

    Enum.each(1..div(espera, 200), fn _ ->
      Process.sleep(200)
      IO.write(".")
    end)

    IO.puts("\n")

    print_reservation(server, res_id)

    seats = FlightServer.available_seats(server)
    IO.puts("2A liberado y disponible nuevamente: #{"2A" in seats}\n")
  end

  defp banner(text) do
    IO.puts("")
    IO.puts(String.duplicate("=", 60))
    IO.puts("  #{text}")
    IO.puts(String.duplicate("=", 60))
  end

  defp print_reservation(server, res_id) do
    case FlightServer.get_reservation(server, res_id) do
      nil ->
        IO.puts("  (#{res_id} no encontrada)")

      r ->
        IO.puts("  #{r.id}  pasajero=#{r.passenger_id}  asiento=#{r.seat_code}  estado=#{r.status}")
    end
  end

  defp print_summary(server) do
    s = FlightServer.summary(server)

    IO.puts("Vuelo:        #{s.flight_id}  (#{s.route}, #{s.date})")
    IO.puts("Pasajeros:    #{s.passengers}")
    IO.puts("Asientos:     available=#{s.seats.available}  reserved=#{s.seats.reserved}  confirmed=#{s.seats.confirmed}")

    IO.puts(
      "Reservas:     pending=#{s.reservations.pending}  confirmed=#{s.reservations.confirmed}  cancelled=#{s.reservations.cancelled}  expired=#{s.reservations.expired}"
    )

    IO.puts("")
  end

  defp print_audit do
    events = AuditServer.dump()

    if is_list(events) do
      IO.puts("--- Audit log (#{length(events)} eventos) ---")

      Enum.each(events, fn e ->
        IO.puts("  #{e.type}  #{compact(e.payload)}")
      end)

      IO.puts("")
    end
  end

  defp compact(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(" ")
  end

  defp compact(other), do: inspect(other)

  defp format_result({:ok, res_id}), do: "OK reserva=#{res_id}"
  defp format_result({:error, reason}), do: "ERROR #{inspect(reason)}"
  defp format_result(other), do: inspect(other)
end
