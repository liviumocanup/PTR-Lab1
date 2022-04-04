defmodule GenericSupervisor do
  use Supervisor

  def start_link(worker_module, num_workers) do
    supervisor_name = generate_supervisor_name(worker_module)
    IO.puts "Starting #{supervisor_name}..."
    Supervisor.start_link(__MODULE__, %{worker_module: worker_module, num_workers: num_workers, name: String.to_atom(supervisor_name)}, name: String.to_atom(supervisor_name))
  end

  def init(state) do
    children =
      Enum.map(1..state.num_workers, fn id ->
        %{
          id: id,
          start: {state.worker_module, :start_link, [id]}
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end


  def get_message_count(pid) do
    GenServer.call(pid, :message_count)
  end

  def count(sup_pid) do
    Supervisor.count_children(sup_pid)
    |> Map.fetch!(:active)
  end

  def get_worker_pid(sup_pid, id) do
    Supervisor.which_children(sup_pid)
    |> Enum.find(fn {i, _, _, _} -> i == id end)
    |> elem(1)
  end

  def get_worker_id(sup_pid, pid) do
    Supervisor.which_children(sup_pid)
    |> Enum.find(fn {_, i, _, _} -> i == pid end)
    |> elem(0)
  end

  def get_all_pids(sup_pid) do
    Enum.map(1..count(sup_pid), fn i -> get_worker_pid(sup_pid, i) end)
  end

  def generate_supervisor_name(worker_module) do
    module_name = inspect(worker_module)
    String.replace_suffix(module_name, "", "Supervisor")
  end
end
