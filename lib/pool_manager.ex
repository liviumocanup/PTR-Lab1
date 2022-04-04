defmodule WorkerPoolManager do
  use GenServer

  # @start_num_workers 3
  @max_num_workers 11
  @min_num_workers 1

  # @spec_num_workers 3
  # @spec_timeout 5000

  def start_link(supervisor_name, worker) do
    supervisor_name = String.to_atom(supervisor_name)
    IO.puts "Starting WorkerPoolManager for...#{inspect supervisor_name}"
    GenServer.start_link(__MODULE__, %{supervisor_name: supervisor_name, worker: worker, sup_pid: GenServer.whereis(supervisor_name)}, name: String.to_atom("WPM" <> inspect(worker)))
    |> elem(1)
  end

  def init(state) do
    # state.supervisor_module.start_link(state.worker, @start_num_workers)
    {:ok, state}
  end

  def handle_cast({:increase_workers, num}, state) do
    current_num_workers = count_workers(state)
    new_num_workers = current_num_workers + num

    new_num_workers = min(new_num_workers, @max_num_workers)

    if new_num_workers > current_num_workers do
      start_workers(new_num_workers - current_num_workers, state)
    end

    {:noreply, state}
  end

  def handle_cast({:decrease_workers, num}, state) do
    current_num_workers = count_workers(state)
    new_num_workers = current_num_workers - num

    new_num_workers = max(new_num_workers, @min_num_workers)

    if new_num_workers < current_num_workers do
      stop_workers(current_num_workers - new_num_workers, state)
    end

    {:noreply, state}
  end

  def increase_workers(pid, num) do
    GenServer.cast(pid, {:increase_workers, num})
  end

  def decrease_workers(pid, num) do
    GenServer.cast(pid, {:decrease_workers, num})
  end

  defp start_workers(num, state) do
    children_to_add = Enum.map(count_workers(state)+1..count_workers(state)+num, fn id ->
      %{
        id: id,
        start: {state.worker, :start_link, [id]}
      }
    end)

    Enum.each(children_to_add, fn child ->
      if Enum.any?(Supervisor.which_children(state.sup_pid), fn {id, _, _, _} -> id == child.id end) do
        Supervisor.restart_child(state.sup_pid, child.id)
      else
        Supervisor.start_child(state.sup_pid, child)
      end
    end)

    {:ok, state}
  end

  defp stop_workers(num, state) do
    Enum.map(count_workers(state)-num+1..count_workers(state), fn id ->
      IO.puts("Stopping worker #{id}")
      Supervisor.terminate_child(state.sup_pid, id)
    end)

    {:ok, state}
  end

  defp count_workers(state) do
    GenericSupervisor.count(state.sup_pid)
  end

  # def execute_speculatively(message) do
  #   worker_pids = get_worker_pids(@spec_num_workers)

  #   tasks = Enum.map(worker_pids, fn worker_pid ->
  #     Task.async(fn ->
  #       ref = make_ref()
  #       send(worker_pid, {PrintSupervisor.get_worker_id(worker_pid), message, self(), ref})
  #       receive do
  #         {^ref, :result, result} -> result
  #       after
  #         @spec_timeout -> nil
  #       end
  #     end)
  #   end)

  #   await_first_task(tasks)
  # end

  # defp get_worker_pids(num_workers) do
  #   PrintSupervisor |> Supervisor.which_children()
  #   |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
  #   |> Enum.take(num_workers)
  # end

  # defp await_first_task(tasks) do
  #   tasks
  #   |> Enum.map(fn task ->
  #     try do
  #       Task.await(task, @spec_timeout) # Add the timeout value here
  #     rescue
  #       Task.TimeoutError ->
  #         nil
  #     end
  #   end)
  #   |> Enum.reject(&is_nil/1)
  #   |> List.first()
  # end

end
