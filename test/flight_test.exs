# Tests para el módulo Flight

defmodule CondorDelSur.FlightTest do
  @moduledoc """
  Tests de la lógica pura sobre `%Flight{}`. No levantan procesos.

  Cubrimos los casos mínimos pedidos por el enunciado:

    * iniciar una reserva sobre un asiento disponible
    * intentar reservar un asiento ocupado
    * confirmar una reserva pendiente
    * cancelar una reserva pendiente
    * evitar cancelar una reserva ya confirmada
    * verificar que una reserva expirada libere el asiento
  """

  use ExUnit.Case, async: true

  alias CondorDelSur.{Flight, Passenger, Reservation, Seat}

  @ttl_ms 30_000

  defp build_flight(seat_codes \\ ["1A", "1B", "1C"]) do
    Flight.new(
      %{id: "T1", origin: "EZE", destination: "BRC", date: ~D[2026-05-10]},
      seat_codes
    )
    |> Flight.add_passenger(Passenger.new("P1", "Ana"))
    |> Flight.add_passenger(Passenger.new("P2", "Pedro"))
  end

  describe "start_reservation/5" do
    test "inicia una reserva sobre un asiento disponible" do
      f = build_flight()
      now = 1_000

      assert {:ok, f2, %Reservation{} = res} =
               Flight.start_reservation(f, "P1", "1A", now, @ttl_ms)

      assert res.status == :pending
      assert res.passenger_id == "P1"
      assert res.seat_code == "1A"
      assert res.expires_at == now + @ttl_ms
      assert %Seat{status: :reserved, reservation_id: rid} = f2.seats["1A"]
      assert rid == res.id
    end

    test "no se puede reservar un asiento ya reservado" do
      f = build_flight()
      {:ok, f, _} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)

      assert {:error, {:seat_unavailable, :reserved}} =
               Flight.start_reservation(f, "P2", "1A", 2_000, @ttl_ms)
    end

    test "no se puede reservar un asiento confirmado" do
      f = build_flight()
      {:ok, f, res} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)
      {:ok, f, _} = Flight.confirm_reservation(f, res.id, 1_500)

      assert {:error, {:seat_unavailable, :confirmed}} =
               Flight.start_reservation(f, "P2", "1A", 2_000, @ttl_ms)
    end

    test "rechaza pasajero inexistente" do
      f = build_flight()
      assert {:error, :passenger_not_found} =
               Flight.start_reservation(f, "no-existo", "1A", 1_000, @ttl_ms)
    end

    test "rechaza asiento inexistente" do
      f = build_flight()
      assert {:error, :seat_not_found} =
               Flight.start_reservation(f, "P1", "99Z", 1_000, @ttl_ms)
    end
  end

  describe "confirm_reservation/3" do
    test "confirma una reserva pendiente y deja el asiento :confirmed" do
      f = build_flight()
      {:ok, f, res} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)

      assert {:ok, f2, %Reservation{status: :confirmed} = r2} =
               Flight.confirm_reservation(f, res.id, 1_500)

      assert r2.confirmed_at == 1_500
      assert %Seat{status: :confirmed} = f2.seats["1A"]
    end

    test "no se puede confirmar una reserva inexistente" do
      f = build_flight()
      assert {:error, :reservation_not_found} =
               Flight.confirm_reservation(f, "R999", 1_500)
    end

    test "no se puede confirmar una reserva ya cancelada" do
      f = build_flight()
      {:ok, f, res} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)
      {:ok, f, _} = Flight.cancel_reservation(f, res.id, 1_200)

      assert {:error, {:cannot_confirm, :cancelled}} =
               Flight.confirm_reservation(f, res.id, 1_300)
    end
  end

  describe "cancel_reservation/3" do
    test "cancela una reserva pendiente y libera el asiento" do
      f = build_flight()
      {:ok, f, res} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)

      assert {:ok, f2, %Reservation{status: :cancelled}} =
               Flight.cancel_reservation(f, res.id, 1_500)

      assert %Seat{status: :available, reservation_id: nil} = f2.seats["1A"]
    end

    test "evita cancelar una reserva ya confirmada" do
      f = build_flight()
      {:ok, f, res} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)
      {:ok, f, _} = Flight.confirm_reservation(f, res.id, 1_200)

      assert {:error, {:cannot_cancel, :confirmed}} =
               Flight.cancel_reservation(f, res.id, 1_300)
    end

    test "rechaza reserva inexistente" do
      f = build_flight()
      assert {:error, :reservation_not_found} =
               Flight.cancel_reservation(f, "R999", 1_500)
    end
  end

  describe "expire_reservation/3" do
    test "una reserva pending expira y libera el asiento" do
      f = build_flight()
      {:ok, f, res} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)

      assert {:ok, f2, %Reservation{status: :expired}} =
               Flight.expire_reservation(f, res.id, 1_000 + @ttl_ms)

      assert %Seat{status: :available, reservation_id: nil} = f2.seats["1A"]
    end

    test "expirar una reserva ya confirmada es :noop (no rompe nada)" do
      f = build_flight()
      {:ok, f, res} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)
      {:ok, f, _} = Flight.confirm_reservation(f, res.id, 1_200)

      assert :noop = Flight.expire_reservation(f, res.id, 1_500)
      # Y la reserva sigue confirmed:
      assert %Reservation{status: :confirmed} = Flight.get_reservation(f, res.id)
    end

    test "expirar una reserva ya cancelada también es :noop" do
      f = build_flight()
      {:ok, f, res} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)
      {:ok, f, _} = Flight.cancel_reservation(f, res.id, 1_200)

      assert :noop = Flight.expire_reservation(f, res.id, 1_500)
    end
  end

  describe "summary/1" do
    test "cuenta correctamente asientos y reservas por estado" do
      f = build_flight(["1A", "1B", "1C", "1D"])
      {:ok, f, r1} = Flight.start_reservation(f, "P1", "1A", 1_000, @ttl_ms)
      {:ok, f, _r2} = Flight.start_reservation(f, "P2", "1B", 1_000, @ttl_ms)
      {:ok, f, _} = Flight.confirm_reservation(f, r1.id, 1_500)

      summary = Flight.summary(f)

      assert summary.seats == %{available: 2, reserved: 1, confirmed: 1}
      assert summary.reservations.pending == 1
      assert summary.reservations.confirmed == 1
    end
  end
end
