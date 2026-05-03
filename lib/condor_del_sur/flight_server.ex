# Proceso central que custodia el estado de un vuelo

defmodule CondorDelSur.FlightServer do
  alias CondorDelSur.{AuditServer, Flight, Payment, Reservation}

  @default_ttl_ms 30_000

  def start(%Flight{} = flight, opts \\ []) do
    name = Keyword.get(opts, :name, server_name(flight.id))
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)

    pid = spawn(fn -> loop(flight, %{ttl_ms: ttl_ms, name: name}) end)
    if name, do: Process.register(pid, name)

    {:ok, pid}
  end

  def server_name(flight_id), do: String.to_atom("flight_#{flight_id}")

  @timeout 2_000

  def add_passenger(server, passenger) do
    send(server, {:add_passenger, passenger, self()})
    wait(:passenger_added)
  end

  def start_reservation(server, passenger_id, seat_code) do
    send(server, {:start_reservation, passenger_id, seat_code, self()})

    receive do
      {:reservation_started, res_id}    -> {:ok, res_id}
      {:reservation_error, reason}      -> {:error, reason}
    after
      @timeout -> {:error, :timeout}
    end
  end

  def cancel_reservation(server, reservation_id) do
    send(server, {:cancel_reservation, reservation_id, self()})

    receive do
      :ok                          -> :ok
      {:error, reason}             -> {:error, reason}
    after
      @timeout -> {:error, :timeout}
    end
  end

  def request_payment(server, reservation_id) do
    send(server, {:request_payment, reservation_id, self()})

    receive do
      :payment_started      -> :ok
      {:error, reason}      -> {:error, reason}
    after
      @timeout -> {:error, :timeout}
    end
  end

  def available_seats(server) do
    send(server, {:available_seats, self()})

    receive do
      {:available_seats, list} -> list
    after
      @timeout -> {:error, :timeout}
    end
  end

  def summary(server) do
    send(server, {:summary, self()})

    receive do
      {:summary, s} -> s
    after
      @timeout -> {:error, :timeout}
    end
  end

  def get_reservation(server, reservation_id) do
    send(server, {:get_reservation, reservation_id, self()})

    receive do
      {:reservation, r} -> r
    after
      @timeout -> {:error, :timeout}
    end
  end

  def stop(server), do: send(server, :stop)

  defp loop(%Flight{} = flight, ctx) do
    receive do
      msg -> handle(msg, flight, ctx)
    end
  end

  defp handle({:add_passenger, passenger, from}, flight, ctx) do
    new_flight = Flight.add_passenger(flight, passenger)
    send(from, :passenger_added)
    audit(:passenger_added, %{passenger_id: passenger.id, name: passenger.name})
    loop(new_flight, ctx)
  end

  defp handle({:start_reservation, passenger_id, seat_code, from}, flight, ctx) do
    now = now_ms()

    case Flight.start_reservation(flight, passenger_id, seat_code, now, ctx.ttl_ms) do
      {:ok, new_flight, %Reservation{id: res_id}} ->
        send(from, {:reservation_started, res_id})

        spawn_expirer(self(), res_id, ctx.ttl_ms)

        audit(:reservation_started, %{
          reservation_id: res_id,
          passenger_id: passenger_id,
          seat_code: seat_code
        })

        loop(new_flight, ctx)

      {:error, reason} ->
        send(from, {:reservation_error, reason})

        audit(:reservation_failed, %{
          passenger_id: passenger_id,
          seat_code: seat_code,
          reason: reason
        })

        loop(flight, ctx)
    end
  end

  defp handle({:cancel_reservation, res_id, from}, flight, ctx) do
    case Flight.cancel_reservation(flight, res_id, now_ms()) do
      {:ok, new_flight, _res} ->
        send(from, :ok)
        audit(:reservation_cancelled, %{reservation_id: res_id})
        loop(new_flight, ctx)

      {:error, reason} ->
        send(from, {:error, reason})
        loop(flight, ctx)
    end
  end

  defp handle({:request_payment, res_id, from}, flight, ctx) do
    case Flight.get_reservation(flight, res_id) do
      %Reservation{status: :pending} ->
        send(from, :payment_started)

        Payment.start(ctx.name, res_id, from)

        audit(:payment_started, %{reservation_id: res_id})
        loop(flight, ctx)

      %Reservation{status: status} ->
        send(from, {:error, {:cannot_pay, status}})
        loop(flight, ctx)

      nil ->
        send(from, {:error, :reservation_not_found})
        loop(flight, ctx)
    end
  end

  defp handle({:payment_result, res_id, :ok}, flight, ctx) do
    case Flight.confirm_reservation(flight, res_id, now_ms()) do
      {:ok, new_flight, _res} ->
        audit(:reservation_confirmed, %{reservation_id: res_id})
        loop(new_flight, ctx)

      {:error, reason} ->
        audit(:payment_arrived_late, %{reservation_id: res_id, reason: reason})
        loop(flight, ctx)
    end
  end

  defp handle({:payment_result, res_id, {:error, reason}}, flight, ctx) do
    audit(:payment_failed, %{reservation_id: res_id, reason: reason})
    loop(flight, ctx)
  end

  defp handle({:check_expire, res_id}, flight, ctx) do
    case Flight.expire_reservation(flight, res_id, now_ms()) do
      {:ok, new_flight, _res} ->
        audit(:reservation_expired, %{reservation_id: res_id})
        loop(new_flight, ctx)

      :noop ->
        loop(flight, ctx)

      {:error, _} ->
        loop(flight, ctx)
    end
  end

  defp handle({:available_seats, from}, flight, ctx) do
    send(from, {:available_seats, Flight.available_seats(flight)})
    loop(flight, ctx)
  end

  defp handle({:summary, from}, flight, ctx) do
    send(from, {:summary, Flight.summary(flight)})
    loop(flight, ctx)
  end

  defp handle({:get_reservation, res_id, from}, flight, ctx) do
    send(from, {:reservation, Flight.get_reservation(flight, res_id)})
    loop(flight, ctx)
  end

  defp handle(:stop, _flight, _ctx), do: :ok

  defp handle(other, flight, ctx) do
    IO.puts("[FlightServer] mensaje desconocido: #{inspect(other)}")
    loop(flight, ctx)
  end

  defp audit(type, payload) do
    if Process.whereis(:audit), do: AuditServer.event(:audit, type, payload)
    :ok
  end

  defp now_ms, do: System.system_time(:millisecond)

  defp spawn_expirer(server_pid, res_id, ttl_ms) do
    spawn(fn ->
      Process.sleep(ttl_ms)
      send(server_pid, {:check_expire, res_id})
    end)
  end

  defp wait(expected) do
    receive do
      ^expected -> :ok
      {:error, reason} -> {:error, reason}
    after
      @timeout -> {:error, :timeout}
    end
  end
end
