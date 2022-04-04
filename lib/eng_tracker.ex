defmodule EngagementTracker do
  use GenServer

  def start_link do
    pid = GenServer.start_link(__MODULE__, %{})
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(_) do
    {:ok, %{user_ratios: %{}}}
  end

  def store(name, engagement_ratio) do
    GenServer.call(__MODULE__, {:store, name, engagement_ratio})
  end

  def get_ratio(name) do
    GenServer.call(__MODULE__, {:get_ratio, name})
  end

  def handle_call({:store, name, engagement_ratio}, _from, state) do
    user_ratios = Map.get(state, :user_ratios)
    updated_user_ratios = update_user_ratios(user_ratios, name, engagement_ratio)

    {:reply, :ok, %{state | user_ratios: updated_user_ratios}}
  end

  def handle_call({:get_ratio, name}, _from, state) do
    user_ratios = Map.get(state, :user_ratios)
    ratios = Map.get(user_ratios, name, [])

    average_ratio =
      if length(ratios) > 0 do
        Enum.sum(ratios) / length(ratios)
      else
        0
      end

    {:reply, average_ratio, state}
  end

  defp update_user_ratios(user_ratios, name, engagement_ratio) do
    current_ratios = Map.get(user_ratios, name, [])
    updated_ratios = [engagement_ratio | current_ratios]
    Map.put(user_ratios, name, updated_ratios)
  end
end
