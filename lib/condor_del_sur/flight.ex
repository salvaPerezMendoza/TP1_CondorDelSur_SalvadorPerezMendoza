# Módulo con lógica pura del vuelo

defmodule CondorDelSur.Flight do
  alias CondorDelSur.{Flight, Passenger, Reservation, Seat}

  @enforce_keys [:id, :origin, :destination, :date]
  defstruct [
    :id,
    :origin,
    :destination,
    :date,
    seats: %{},
    passengers: %{},
    reservations: %{},
    next_reservation_id: 1
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          origin: String.t(),
          destination: String.t(),
          date: Date.t(),
          seats: %{String.t() => Seat.t()},
          passengers: %{term() => Passenger.t()},
          reservations: %{String.t() => Reservation.t()},
          next_reservation_id: integer()
        }

  def new(attrs, seat_codes) when is_list(seat_codes) do
    seats =
      seat_codes
      |> Enum.map(fn code -> {code, %Seat{code: code}} end)
      |> Map.new()

    %Flight{
      id: attrs.id,
      origin: attrs.origin,
      destination: attrs.destination,
      date: attrs.date,
      seats: seats
    }
  end

  def add_passenger(%Flight{} = flight, %Passenger{} = passenger) do
    %Flight{flight | passengers: Map.put(flight.passengers, passenger.id, passenger)}
  end

  def get_passenger(%Flight{} = flight, passenger_id),
    do: Map.get(flight.passengers, passenger_id)

  def start_reservation(%Flight{} = flight, passenger_id, seat_code, now_ms, ttl_ms) do
    cond do
      not Map.has_key?(flight.passengers, passenger_id) ->
        {:error, :passenger_not_found}

      not Map.has_key?(flight.seats, seat_code) ->
        {:error, :seat_not_found}

      true ->
        case Map.fetch!(flight.seats, seat_code) do
          %Seat{status: :available} = seat ->
            res_id = "R#{flight.next_reservation_id}"

            reservation = %Reservation{
              id: res_id,
              passenger_id: passenger_id,
              seat_code: seat_code,
              expires_at: now_ms + ttl_ms,
              created_at: now_ms,
              status: :pending
            }

            updated_seat = %Seat{seat | status: :reserved, reservation_id: res_id}

            new_flight = %Flight{
              flight
              | seats: Map.put(flight.seats, seat_code, updated_seat),
                reservations: Map.put(flight.reservations, res_id, reservation),
                next_reservation_id: flight.next_reservation_id + 1
            }

            {:ok, new_flight, reservation}

          %Seat{status: status} ->
            {:error, {:seat_unavailable, status}}
        end
    end
  end

  def confirm_reservation(%Flight{} = flight, reservation_id, now_ms) do
    case Map.get(flight.reservations, reservation_id) do
      nil ->
        {:error, :reservation_not_found}

      %Reservation{status: :pending} = res ->
        %Seat{} = seat = Map.fetch!(flight.seats, res.seat_code)

        updated_res = %Reservation{res | status: :confirmed, confirmed_at: now_ms}
        updated_seat = %Seat{seat | status: :confirmed}

        new_flight = %Flight{
          flight
          | reservations: Map.put(flight.reservations, reservation_id, updated_res),
            seats: Map.put(flight.seats, res.seat_code, updated_seat)
        }

        {:ok, new_flight, updated_res}

      %Reservation{status: status} ->
        {:error, {:cannot_confirm, status}}
    end
  end

  def cancel_reservation(%Flight{} = flight, reservation_id, now_ms) do
    case Map.get(flight.reservations, reservation_id) do
      nil ->
        {:error, :reservation_not_found}

      %Reservation{status: :pending} = res ->
        %Seat{} = seat = Map.fetch!(flight.seats, res.seat_code)

        updated_res = %Reservation{res | status: :cancelled, cancelled_at: now_ms}
        updated_seat = %Seat{seat | status: :available, reservation_id: nil}

        new_flight = %Flight{
          flight
          | reservations: Map.put(flight.reservations, reservation_id, updated_res),
            seats: Map.put(flight.seats, res.seat_code, updated_seat)
        }

        {:ok, new_flight, updated_res}

      %Reservation{status: status} ->
        {:error, {:cannot_cancel, status}}
    end
  end

  def expire_reservation(%Flight{} = flight, reservation_id, now_ms) do
    case Map.get(flight.reservations, reservation_id) do
      nil ->
        {:error, :reservation_not_found}

      %Reservation{status: :pending} = res ->
        %Seat{} = seat = Map.fetch!(flight.seats, res.seat_code)

        updated_res = %Reservation{res | status: :expired, expired_at: now_ms}
        updated_seat = %Seat{seat | status: :available, reservation_id: nil}

        new_flight = %Flight{
          flight
          | reservations: Map.put(flight.reservations, reservation_id, updated_res),
            seats: Map.put(flight.seats, res.seat_code, updated_seat)
        }

        {:ok, new_flight, updated_res}

      %Reservation{} ->
        :noop
    end
  end

  def get_reservation(%Flight{} = flight, reservation_id),
    do: Map.get(flight.reservations, reservation_id)

  def available_seats(%Flight{} = flight) do
    flight.seats
    |> Map.values()
    |> Enum.filter(fn %Seat{status: s} -> s == :available end)
    |> Enum.map(& &1.code)
    |> Enum.sort()
  end

  def reservations_by_status(%Flight{} = flight, status) do
    flight.reservations
    |> Map.values()
    |> Enum.filter(fn %Reservation{status: s} -> s == status end)
  end

  def summary(%Flight{} = flight) do
    seat_counts =
      flight.seats
      |> Map.values()
      |> Enum.frequencies_by(& &1.status)

    reservation_counts =
      flight.reservations
      |> Map.values()
      |> Enum.frequencies_by(& &1.status)

    %{
      flight_id: flight.id,
      route: "#{flight.origin} -> #{flight.destination}",
      date: flight.date,
      seats: %{
        available: Map.get(seat_counts, :available, 0),
        reserved: Map.get(seat_counts, :reserved, 0),
        confirmed: Map.get(seat_counts, :confirmed, 0)
      },
      reservations: %{
        pending: Map.get(reservation_counts, :pending, 0),
        confirmed: Map.get(reservation_counts, :confirmed, 0),
        cancelled: Map.get(reservation_counts, :cancelled, 0),
        expired: Map.get(reservation_counts, :expired, 0)
      },
      passengers: map_size(flight.passengers)
    }
  end
end
