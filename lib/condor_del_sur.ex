# Punto de entrada del sistema CondorDelSur

defmodule CondorDelSur do
  alias CondorDelSur.{AuditServer, Flight, FlightServer, Passenger}

  def bootstrap(opts \\ []) do
    flight_id = Keyword.get(opts, :flight_id, "AR1234")
    ttl_ms = Keyword.get(opts, :ttl_ms, 30_000)

    seat_codes =
      Keyword.get(
        opts,
        :seat_codes,
        for(row <- 1..3, col <- ~w(A B C D), do: "#{row}#{col}")
      )

    flight =
      Flight.new(
        %{
          id: flight_id,
          origin: "EZE",
          destination: "COR",
          date: ~D[2026-05-04]
        },
        seat_codes
      )

    {:ok, audit_pid} = ensure_started(:audit, fn -> AuditServer.start() end)

    server_name = FlightServer.server_name(flight_id)
    {:ok, flight_pid} = ensure_started(server_name, fn ->
      FlightServer.start(flight, name: server_name, ttl_ms: ttl_ms)
    end)

    %{
      flight_id: flight_id,
      flight_pid: flight_pid,
      flight_name: server_name,
      audit_pid: audit_pid
    }
  end

  def seed_passengers(server_name, passengers) when is_list(passengers) do
    Enum.each(passengers, fn %Passenger{} = p ->
      FlightServer.add_passenger(server_name, p)
    end)
  end

  def shutdown do
    for name <- [:audit] ++ flight_names() do
      case Process.whereis(name) do
        nil -> :ok
        pid -> Process.exit(pid, :shutdown)
      end
    end

    :ok
  end

  defp flight_names do
    Process.registered()
    |> Enum.filter(fn n -> n |> Atom.to_string() |> String.starts_with?("flight_") end)
  end

  defp ensure_started(name, start_fn) do
    case Process.whereis(name) do
      nil -> start_fn.()
      pid -> {:ok, pid}
    end
  end
end
