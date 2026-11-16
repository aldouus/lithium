defmodule Lithium.Worker do
  @moduledoc false

  use GenServer

  @tick_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{running: MapSet.new()}}
  end

  @impl true
  def handle_info(:tick, state) do
    state = dispatch(state)
    schedule_tick()
    {:noreply, state}
  end

  @impl true
  def handle_info({:sync_done, tenant_id}, state) do
    {:noreply, %{state | running: MapSet.delete(state.running, tenant_id)}}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp dispatch(state) do
    Enum.reduce(Lithium.Tenant.list(), state, fn tenant_id, state ->
      if MapSet.member?(state.running, tenant_id) or not due?(tenant_id) do
        state
      else
        start_sync(state, tenant_id)
      end
    end)
  end

  defp start_sync(state, tenant_id) do
    parent = self()

    {:ok, _pid} =
      Task.start(fn ->
        try do
          Lithium.Sync.run(tenant_id)
        after
          send(parent, {:sync_done, tenant_id})
        end
      end)

    %{state | running: MapSet.put(state.running, tenant_id)}
  end

  defp due?(tenant_id) do
    case Lithium.Store.with_conn(tenant_id, &Lithium.Store.next_run/1) do
      {:ok, next} when is_integer(next) -> next <= System.system_time(:second)
      _ -> false
    end
  end
end
