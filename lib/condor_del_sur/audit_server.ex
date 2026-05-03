# Proceso de auditoría que mantiene un log de eventos

defmodule CondorDelSur.AuditServer do
  @name :audit

  def start(opts \\ []) do
    pid = spawn(fn -> loop([]) end)

    name = Keyword.get(opts, :name, @name)
    if name, do: Process.register(pid, name)

    {:ok, pid}
  end

  def event(server \\ @name, type, payload) do
    send(server, {:event, type, payload})
    :ok
  end

  def dump(server \\ @name, timeout \\ 1_000) do
    send(server, {:dump, self()})

    receive do
      {:audit_dump, events} -> events
    after
      timeout -> {:error, :timeout}
    end
  end

  def reset(server \\ @name, timeout \\ 1_000) do
    send(server, {:reset, self()})

    receive do
      :ok -> :ok
    after
      timeout -> {:error, :timeout}
    end
  end

  def stop(server \\ @name), do: send(server, :stop)

  defp loop(events) do
    receive do
      {:event, type, payload} ->
        entry = %{
          at: System.system_time(:millisecond),
          type: type,
          payload: payload
        }

        loop([entry | events])

      {:dump, from} ->
        send(from, {:audit_dump, Enum.reverse(events)})
        loop(events)

      {:reset, from} ->
        send(from, :ok)
        loop([])

      :stop ->
        :ok

      other ->
        IO.puts("[AuditServer] mensaje desconocido: #{inspect(other)}")
        loop(events)
    end
  end
end
