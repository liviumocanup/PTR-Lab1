defmodule WorkerPoolManager do
  use GenServer

  @start_num_workers 3
  @max_num_workers 10
  @min_num_workers 1

  def start_link() do
    IO.puts "Starting WorkerPoolManager ..."
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    PrintSupervisor.start_link(@start_num_workers)
    {:ok, []}
  end

  def handle_cast({:increase_workers, num}, state) do
    current_num_workers = count_workers()
    new_num_workers = current_num_workers + num

    new_num_workers = min(new_num_workers, @max_num_workers)

    if new_num_workers > current_num_workers do
      start_workers(new_num_workers - current_num_workers)
    end

    {:noreply, state}
  end

  def handle_cast({:decrease_workers, num}, state) do
    current_num_workers = count_workers()
    new_num_workers = current_num_workers - num

    new_num_workers = max(new_num_workers, @min_num_workers)

    if new_num_workers < current_num_workers do
      stop_workers(current_num_workers - new_num_workers)
    end

    {:noreply, state}
  end

  def increase_workers(num) do
    GenServer.cast(__MODULE__, {:increase_workers, num})
  end

  def decrease_workers(num) do
    GenServer.cast(__MODULE__, {:decrease_workers, num})
  end

  defp start_workers(num) do
    children_to_add = Enum.map(count_workers()+1..count_workers()+num, fn id ->
      %{
        id: id,
        start: {Print, :start_link, [id]}
      }
    end)

    Enum.each(children_to_add, fn child ->
      if Enum.any?(Supervisor.which_children(PrintSupervisor), fn {id, _, _, _} -> id == child.id end) do
        Supervisor.restart_child(PrintSupervisor, child.id)
      else
        Supervisor.start_child(PrintSupervisor, child)
      end
    end)

    :ok
  end

  defp stop_workers(num) do
    Enum.map(count_workers()-num+1..count_workers(), fn id ->
      IO.puts("Stopping worker #{id}")
      Supervisor.terminate_child(PrintSupervisor, id)
    end)

    :ok
  end

  defp count_workers() do
    PrintSupervisor.count()
  end

end
