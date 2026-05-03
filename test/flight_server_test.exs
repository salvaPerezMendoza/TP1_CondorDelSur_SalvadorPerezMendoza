# Tests para el proceso FlightServer

# Tests para el proceso FlightServer

defmodule CondorDelSur.FlightServerTest do
  use ExUnit.Case, async: false

  alias CondorDelSur.{Flight, FlightServer, Passenger}

  setup do
    flight =
      Flight.new(
        %{id: "T1", origin: "EZE", destination: "BRC", date: ~D[2026-05-10]},
        ["1A", "1B", "1C"]
      )

    {:ok, pid} = FlightServer.start(flight, name: nil, ttl_ms: 30_000)

    :ok = FlightServer.add_passenger(pid, Passenger.new("P1", "Ana"))
    :ok = FlightServer.add_passenger(pid, Passenger.new("P2", "Pedro"))

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    end)

    {:ok, server: pid}
  end

  test "protocolo básico: reserva + confirm via mensaje", %{server: server} do
    assert {:ok, res_id} = FlightServer.start_reservation(server, "P1", "1A")
    assert is_binary(res_id)

    me = self()
    CondorDelSur.Payment.start(server, res_id, me, force: :ok, delay_ms: 50)

    assert_receive {:payment_done, ^res_id, :ok}, 1_000
    Process.sleep(50)

    res = FlightServer.get_reservation(server, res_id)
    assert res.status == :confirmed
  end

  test "concurrencia: N pasajeros, gana 1", %{server: server} do
    me = self()

    for i <- 1..50 do
      :ok = FlightServer.add_passenger(server, Passenger.new("PX#{i}", "Px#{i}"))
    end

    for i <- 1..50 do
      spawn(fn ->
        result = FlightServer.start_reservation(server, "PX#{i}", "1A")
        send(me, {:result, result})
      end)
    end

    results =
      for _ <- 1..50 do
        receive do
          {:result, r} -> r
        after
          2_000 -> :timeout
        end
      end

    oks = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    errs = Enum.count(results, fn r -> match?({:error, _}, r) end)

    assert oks == 1, "Solo un pasajero debería ganar el asiento, ganaron #{oks}"
    assert errs == 49
  end

  test "no se puede cancelar una reserva ya confirmada", %{server: server} do
    {:ok, res_id} = FlightServer.start_reservation(server, "P1", "1A")

    me = self()
    CondorDelSur.Payment.start(server, res_id, me, force: :ok, delay_ms: 50)
    assert_receive {:payment_done, ^res_id, :ok}, 1_000
    Process.sleep(50)

    assert {:error, {:cannot_cancel, :confirmed}} =
             FlightServer.cancel_reservation(server, res_id)
  end

  test "expiración automática: el asiento se libera tras el TTL", %{} do
    flight =
      Flight.new(
        %{id: "T2", origin: "EZE", destination: "BRC", date: ~D[2026-05-10]},
        ["1A"]
      )

    {:ok, pid} = FlightServer.start(flight, name: nil, ttl_ms: 200)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    end)

    :ok = FlightServer.add_passenger(pid, Passenger.new("P1", "Ana"))
    {:ok, res_id} = FlightServer.start_reservation(pid, "P1", "1A")

    assert FlightServer.available_seats(pid) == []

    Process.sleep(500)

    assert FlightServer.available_seats(pid) == ["1A"]

    res = FlightServer.get_reservation(pid, res_id)
    assert res.status == :expired
  end
end
