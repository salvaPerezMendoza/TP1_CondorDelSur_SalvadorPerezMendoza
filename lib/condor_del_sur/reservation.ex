# Estructura de datos para representar una reserva

defmodule CondorDelSur.Reservation do
  @enforce_keys [:id, :passenger_id, :seat_code, :expires_at]
  defstruct [
    :id,
    :passenger_id,
    :seat_code,
    :expires_at,
    status: :pending,
    created_at: nil,
    confirmed_at: nil,
    cancelled_at: nil,
    expired_at: nil
  ]

  @type status :: :pending | :confirmed | :cancelled | :expired
  @type t :: %__MODULE__{
          id: String.t(),
          passenger_id: term(),
          seat_code: String.t(),
          expires_at: integer(),
          status: status(),
          created_at: integer() | nil,
          confirmed_at: integer() | nil,
          cancelled_at: integer() | nil,
          expired_at: integer() | nil
        }

  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(%__MODULE__{}), do: false

  def closed?(%__MODULE__{status: status}) when status in [:confirmed, :cancelled, :expired],
    do: true

  def closed?(%__MODULE__{}), do: false
end
