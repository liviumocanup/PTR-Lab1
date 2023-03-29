defmodule WorkerPoolManager do
  use GenServer

  @start_num_workers 3
  @max_num_workers 11
  @min_num_workers 1

  @spec_num_workers 3
  @spec_timeout 5000

  def start_link() do
    IO.puts "Starting WorkerPoolManager ..."
    pid = GenServer.start_link(__MODULE__, [], name: __MODULE__)
    |> elem(1)
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

  def execute_speculatively(message) do
    worker_pids = get_worker_pids(@spec_num_workers)

    tasks = Enum.map(worker_pids, fn worker_pid ->
      Task.async(fn ->
        ref = make_ref()
        send(worker_pid, {PrintSupervisor.get_worker_id(worker_pid), message, self(), ref})
        receive do
          {^ref, :result, result} -> result
        after
          @spec_timeout -> nil
        end
      end)
    end)

    await_first_task(tasks)
  end

  defp get_worker_pids(num_workers) do
    PrintSupervisor |> Supervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> Enum.take(num_workers)
  end

  defp await_first_task(tasks) do
    tasks
    |> Enum.map(fn task ->
      try do
        Task.await(task, @spec_timeout) # Add the timeout value here
      rescue
        Task.TimeoutError ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> List.first()
  end


  # def redistribute_messages(pid) do
  #   flush_and_redistribute(pid)
  # end

  # defp flush_and_redistribute(pid) do
  #   receive do
  #     message ->
  #       # Redistribute the message to the other workers
  #       IO.puts("============================Redistributing message #{inspect message}")
  #       Task.async(fn -> LoadBalancer.print(message) end)

  #       # Recursively process the remaining messages
  #       flush_and_redistribute(pid)

  #   after
  #     0 ->
  #       IO.puts("No more messages to redistribute")
  #   end
  # end

  def execute_speculative(text) do
    Task.async(fn -> LoadBalancer.print(text) end)
  end

end
