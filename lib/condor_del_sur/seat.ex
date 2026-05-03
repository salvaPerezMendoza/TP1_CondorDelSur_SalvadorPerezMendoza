# Estructura de datos para representar un asiento

defmodule CondorDelSur.Seat do
  @enforce_keys [:code]
  defstruct [:code, status: :available, reservation_id: nil]

  @type status :: :available | :reserved | :confirmed
  @type t :: %__MODULE__{
          code: String.t(),
          status: status(),
          reservation_id: String.t() | nil
        }
end
