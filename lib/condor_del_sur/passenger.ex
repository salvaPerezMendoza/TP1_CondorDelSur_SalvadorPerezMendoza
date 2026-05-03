# Estructura de datos para representar un pasajero

defmodule CondorDelSur.Passenger do
  @enforce_keys [:id, :name]
  defstruct [:id, :name]

  @type t :: %__MODULE__{
          id: String.t() | integer(),
          name: String.t()
        }

  def new(id, name), do: %__MODULE__{id: id, name: name}
end
