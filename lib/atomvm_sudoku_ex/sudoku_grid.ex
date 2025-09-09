defmodule AtomvmSudokuEx.SudokuGrid do
  @moduledoc """
  Sudoku grid generation and manipulation utilities.
  """

  @type index :: {1..9, 1..9}
  @type value :: 1..9
  @type puzzle_grid :: %{index() => 0 | value()}
  @type work_grid :: tuple()
  @type random_generator :: (pos_integer() -> pos_integer())

  @spec get(1..9, 1..9, puzzle_grid()) :: 0 | value()
  @spec get(1..9, 1..9, work_grid()) :: [value()]
  def get(x, y, grid) when is_map(grid) do
    Map.get(grid, {x, y})
  end

  def get(x, y, grid) when is_tuple(grid) do
    elem(grid, (x - 1) * 9 + y - 1)
  end

  @spec put(1..9, 1..9, 0 | value(), puzzle_grid()) :: puzzle_grid()
  @spec put(1..9, 1..9, [value()], work_grid()) :: work_grid()
  def put(x, y, value, grid) when is_map(grid) do
    Map.put(grid, {x, y}, value)
  end

  def put(x, y, value, grid) when is_tuple(grid) do
    put_elem(grid, (x - 1) * 9 + y - 1, value)
  end

  @spec to_list(puzzle_grid()) :: [{index(), 0 | value()}]
  @spec to_list(work_grid()) :: [{index(), [value()]}]
  def to_list(grid) when is_map(grid) do
    Map.to_list(grid)
  end

  def to_list(grid) when is_tuple(grid) do
    for x <- 1..9, y <- 1..9 do
      {{x, y}, get(x, y, grid)}
    end
  end

  @spec parallel_random_puzzle(random_generator(), pos_integer(), timeout()) ::
          {puzzle :: puzzle_grid(), solution :: puzzle_grid()}
  def parallel_random_puzzle(random_generator, max_hint, timeout) do
    schedulers = :erlang.system_info(:schedulers_online)
    parallel_random_puzzle(random_generator, max_hint, schedulers, timeout)
  end

  @spec parallel_random_puzzle(random_generator(), pos_integer(), pos_integer(), timeout()) ::
          {puzzle :: puzzle_grid(), solution :: puzzle_grid()}
  def parallel_random_puzzle(random_generator, max_hint, schedulers, timeout) do
    IO.puts("parallel_random_puzzle starting with max_hint=#{max_hint}, schedulers=#{schedulers}, timeout=#{timeout}")
    parent = self()
    start = :erlang.system_time(:millisecond)

    spawn_opts =
      case :erlang.system_info(:machine) do
        ~c"BEAM" -> []
        ~c"ATOM" -> [{:heap_growth, :fibonacci}]
      end

    IO.puts("Spawning #{schedulers} worker processes...")
    workers =
      for _ <- 1..schedulers do
        :erlang.spawn_opt(
          fn -> parallel_random_puzzle_worker_loop(random_generator, parent, :infinity) end,
          [:monitor | spawn_opts]
        )
      end

    IO.puts("Workers spawned, entering main loop...")
    parallel_random_puzzle_loop(start, max_hint, workers, timeout, :infinity, nil, nil)
  end

  defp parallel_random_puzzle_worker_loop(random_generator, parent, best_candidate) do
    IO.puts("Worker generating puzzle...")
    start_time = :erlang.system_time(:millisecond)
    {hints, puzzle, solution} = random_puzzle(random_generator)
    end_time = :erlang.system_time(:millisecond)
    IO.puts("Worker generated puzzle with #{hints} hints in #{end_time - start_time}ms")

    if hints < best_candidate do
      IO.puts("Found better puzzle with #{hints} hints, sending to parent")
      send(parent, {self(), hints, puzzle, solution})
      parallel_random_puzzle_worker_loop(random_generator, parent, hints)
    else
      parallel_random_puzzle_worker_loop(random_generator, parent, best_candidate)
    end
  end

  defp parallel_random_puzzle_loop(
         start,
         max_hint,
         workers,
         timeout,
         best_puzzle_hints,
         best_puzzle_grid,
         best_puzzle_solution
       ) do
    wait =
      case {timeout, best_puzzle_grid} do
        {:infinity, _} -> :infinity
        {_, nil} -> :infinity
        _ -> max(0, timeout + start - :erlang.system_time(:millisecond))
      end

    receive do
      {_worker, hints, puzzle, solution} ->
        if hints <= max_hint do
          stop_workers(workers)
          {puzzle, solution}
        else
          if hints < best_puzzle_hints do
            parallel_random_puzzle_loop(
              start,
              max_hint,
              workers,
              timeout,
              hints,
              puzzle,
              solution
            )
          else
            parallel_random_puzzle_loop(
              start,
              max_hint,
              workers,
              timeout,
              best_puzzle_hints,
              best_puzzle_grid,
              best_puzzle_solution
            )
          end
        end
    after
      wait ->
        stop_workers(workers)
        {best_puzzle_grid, best_puzzle_solution}
    end
  end

  defp stop_workers([]) do
    :ok
  end

  defp stop_workers([{worker, monitor} | tail]) do
    Process.exit(worker, :kill)
    Process.demonitor(monitor, [:flush])
    flush_solutions(worker)
    stop_workers(tail)
  end

  defp flush_solutions(worker) do
    receive do
      {^worker, _, _} -> flush_solutions(worker)
    after
      0 -> :ok
    end
  end

  @spec random_puzzle(random_generator()) ::
          {hints :: pos_integer(), puzzle :: puzzle_grid(), solution :: puzzle_grid()}
  def random_puzzle(random_generator) do
    IO.puts("Generating random solution...")
    solution_grid = random_solution(random_generator)
    IO.puts("Solution generated, shuffling cells...")
    all_cells = for x <- 1..9, y <- 1..9, do: {x, y}
    shuffled_cells = shuffle(random_generator, all_cells)
    IO.puts("Cells shuffled, removing values until multiple solutions...")
    {hints, puzzle_grid} = remove_values_until_multiple_solutions(solution_grid, shuffled_cells, [])
    IO.puts("Found puzzle with #{hints} hints")
    {hints, puzzle_grid, work_to_puzzle_grid(solution_grid)}
  end

  @spec shuffle(random_generator(), [any()]) :: [any()]
  def shuffle(random_generator, list) do
    list
    |> Enum.map(&{random_generator.(0x10000), &1})
    |> Enum.sort()
    |> Enum.map(fn {_, val} -> val end)
  end

  defp remove_values_until_multiple_solutions(solution, [], hint_cells) do
    {length(hint_cells), hints_to_puzzle_grid(solution, hint_cells)}
  end

  defp remove_values_until_multiple_solutions(solution, [cell | tail], acc_hint_cells) do
    candidate = remove_cells_and_propagate(solution, tail ++ acc_hint_cells)

    case has_a_unique_solution(candidate) do
      true ->
        remove_values_until_multiple_solutions(solution, tail, acc_hint_cells)

      false ->
        remove_values_until_multiple_solutions(solution, tail, [cell | acc_hint_cells])
    end
  end

  @spec empty_work_grid() :: work_grid()
  def empty_work_grid do
    all_values = Enum.to_list(1..9)
    List.duplicate(all_values, 81) |> List.to_tuple()
  end

  @spec random_solution(random_generator()) :: work_grid()
  def random_solution(random_generator) do
    empty_grid = empty_work_grid()
    fill_random_grid(random_generator, empty_grid)
  end

  @spec fill_random_grid(random_generator(), work_grid()) :: work_grid()
  def fill_random_grid(random_generator, empty_grid) do
    random_values = random_values(random_generator, 17)
    candidate_grid = fill_cells(random_generator, empty_grid, random_values)

    case find_a_solution(candidate_grid) do
      {:value, solution} -> solution
      :none -> fill_random_grid(random_generator, empty_grid)
    end
  end

  @spec random_values(random_generator(), pos_integer()) :: [value()]
  def random_values(random_generator, count) do
    random_values = for _ <- 1..count, do: random_generator.(9)

    # We need at least 8 different values
    case length(Enum.uniq(random_values)) < 8 do
      true -> random_values(random_generator, count)
      false -> random_values
    end
  end

  @spec fill_cells(random_generator(), work_grid(), [value()]) :: work_grid()
  def fill_cells(_random_generator, grid, []) do
    grid
  end

  def fill_cells(random_generator, grid, [value | tail]) do
    random_cell_x = random_generator.(9)
    random_cell_y = random_generator.(9)

    case get(random_cell_x, random_cell_y, grid) do
      [single_value] when single_value != value ->
        fill_cells(random_generator, grid, [value | tail])

      _ ->
        new_grid = set_grid_value_and_propagate(grid, {random_cell_x, random_cell_y}, value)

        case new_grid do
          :invalid ->
            fill_cells(random_generator, grid, [value | tail])

          _ ->
            fill_cells(random_generator, new_grid, tail)
        end
    end
  end

  @spec set_grid_value_and_propagate(work_grid(), index(), value()) :: work_grid() | :invalid
  def set_grid_value_and_propagate(grid, {x, y}, value) do
    set_grid_values_and_propagate(grid, [{{x, y}, value}])
  end

  @spec set_grid_values_and_propagate(work_grid(), [{index(), value()}]) ::
          work_grid() | :invalid
  def set_grid_values_and_propagate(grid, [{{x, y}, value} | tail]) do
    result =
      for ix <- 1..9, iy <- 1..9, reduce: {grid, tail} do
        :invalid ->
          :invalid

        {acc_grid, acc_list} ->
          cell_values = get(ix, iy, grid)

          cond do
            ix == x and iy == y ->
              {put(x, y, [value], acc_grid), acc_list}

            ix == x ->
              set_grid_value_and_propagate_update_cell(
                {ix, iy},
                cell_values,
                value,
                acc_grid,
                acc_list
              )

            iy == y ->
              set_grid_value_and_propagate_update_cell(
                {ix, iy},
                cell_values,
                value,
                acc_grid,
                acc_list
              )

            div(ix - 1, 3) == div(x - 1, 3) and div(iy - 1, 3) == div(y - 1, 3) ->
              set_grid_value_and_propagate_update_cell(
                {ix, iy},
                cell_values,
                value,
                acc_grid,
                acc_list
              )

            true ->
              {acc_grid, acc_list}
          end
      end

    case result do
      :invalid -> :invalid
      {new_grid, []} -> new_grid
      {new_grid, new_list} -> set_grid_values_and_propagate(new_grid, new_list)
    end
  end

  defp set_grid_value_and_propagate_update_cell({cell_x, cell_y}, cell_values, value, acc_grid, acc_list) do
    case Enum.member?(cell_values, value) do
      true ->
        new_cell_values = List.delete(cell_values, value)

        case new_cell_values do
          [] -> :invalid
          [single_value] -> {acc_grid, [{{cell_x, cell_y}, single_value} | acc_list]}
          _ -> {put(cell_x, cell_y, new_cell_values, acc_grid), acc_list}
        end

      false ->
        {acc_grid, acc_list}
    end
  end

  @spec hints_to_puzzle_grid(work_grid(), [index()]) :: puzzle_grid()
  def hints_to_puzzle_grid(grid, hint_cells) do
    empty_grid =
      for x <- 1..9, y <- 1..9, into: %{} do
        {{x, y}, 0}
      end

    Enum.reduce(hint_cells, empty_grid, fn {index_x, index_y} = index, map ->
      [value] = get(index_x, index_y, grid)
      Map.put(map, index, value)
    end)
  end

  @spec work_to_puzzle_grid(work_grid()) :: puzzle_grid()
  def work_to_puzzle_grid(grid) do
    grid
    |> to_list()
    |> Enum.reduce(%{}, fn {position, vals}, map ->
      case vals do
        [value] -> Map.put(map, position, value)
        _ -> Map.put(map, position, 0)
      end
    end)
  end

  @spec remove_cells_and_propagate(work_grid(), [index()]) :: work_grid()
  def remove_cells_and_propagate(grid, hint_cells) do
    empty_grid = empty_work_grid()

    Enum.reduce(hint_cells, empty_grid, fn {index_x, index_y} = index, map ->
      [value] = get(index_x, index_y, grid)
      set_grid_value_and_propagate(map, index, value)
    end)
  end

  @spec find_a_solution(work_grid()) :: {:value, work_grid()} | :none
  def find_a_solution(grid) do
    case find_solutions(grid, 1, []) do
      {:value, [solution]} -> {:value, solution}
      {:incomplete, []} -> :none
    end
  end

  @spec has_a_unique_solution(work_grid()) :: boolean()
  def has_a_unique_solution(grid) do
    case find_solutions(grid, 2, []) do
      {:value, [_solution1, _solution2]} -> false
      {:incomplete, [_solution]} -> true
      {:incomplete, []} -> false
    end
  end

  @spec find_solutions(work_grid(), pos_integer(), [work_grid()]) ::
          {:value, [work_grid()]} | {:incomplete, [work_grid()]}
  def find_solutions(grid, count, acc_solutions) do
    case get_undecided_cell(grid) do
      :complete when length(acc_solutions) + 1 == count ->
        {:value, [grid | acc_solutions]}

      :complete ->
        {:incomplete, [grid | acc_solutions]}

      {:incomplete, {x, y}, values} ->
        test_solution(grid, {x, y}, values, count, acc_solutions)
    end
  end

  @spec test_solution(work_grid(), index(), [value()], pos_integer(), [work_grid()]) ::
          {:value, [work_grid()]} | {:incomplete, [work_grid()]}
  def test_solution(_grid, {_x, _y}, [], _count, acc_solutions) do
    {:incomplete, acc_solutions}
  end

  def test_solution(grid, {x, y}, [value | tail], count, acc_solutions) do
    grid1 = set_grid_value_and_propagate(grid, {x, y}, value)

    case grid1 do
      :invalid ->
        test_solution(grid, {x, y}, tail, count, acc_solutions)

      _ ->
        case find_solutions(grid1, count, acc_solutions) do
          {:value, all_solutions} ->
            {:value, all_solutions}

          {:incomplete, new_acc_solutions} ->
            test_solution(grid, {x, y}, tail, count, new_acc_solutions)
        end
    end
  end

  @spec get_undecided_cell(work_grid()) :: :complete | {:incomplete, index(), [value()]}
  def get_undecided_cell(grid) do
    for x <- 1..9, y <- 1..9, reduce: :complete do
      :complete ->
        case get(x, y, grid) do
          [_v1, _v2 | _] = list -> {:incomplete, {x, y}, list}
          _ -> :complete
        end

      {:incomplete, {other_x, other_y}, other_list} ->
        case get(x, y, grid) do
          [_v1, _v2 | _] = list when length(list) < length(other_list) ->
            {:incomplete, {x, y}, list}

          _ ->
            {:incomplete, {other_x, other_y}, other_list}
        end
    end
  end

  @spec print(puzzle_grid() | work_grid()) :: :ok
  def print(grid) do
    for x <- 1..9 do
      for y <- 1..9 do
        val = get(x, y, grid)

        case val do
          0 -> IO.write(" ")
          [single_val] when is_integer(single_val) -> IO.write("#{single_val}")
          val when is_integer(val) -> IO.write("#{val}")
          [] -> IO.write("X")
          _ when is_list(val) -> IO.write(".")
        end
      end

      IO.write("\n")
    end
  end

  @spec is_move_valid(puzzle_grid(), index(), value()) :: boolean()
  def is_move_valid(grid, {x, y} = position, move_value) do
    updated_grid = Map.put(grid, position, move_value)

    {line, col, square} =
      Enum.reduce(updated_grid, {[], [], []}, fn
        {_position, 0}, acc ->
          acc

        {{ix, iy}, value}, {acc_line, acc_col, acc_square} ->
          new_line = if ix == x, do: [value | acc_line], else: acc_line
          new_col = if iy == y, do: [value | acc_col], else: acc_col

          new_square =
            if div(ix - 1, 3) == div(x - 1, 3) and div(iy - 1, 3) == div(y - 1, 3) do
              [value | acc_square]
            else
              acc_square
            end

          {new_line, new_col, new_square}
      end)

    is_set_valid(line) and is_set_valid(col) and is_set_valid(square)
  end

  defp is_set_valid(list) do
    Enum.uniq(list) == Enum.sort(list)
  end

  @spec is_solved(puzzle_grid()) :: boolean()
  def is_solved(puzzle) do
    Enum.all?(puzzle, fn {_position, value} -> value != 0 end)
  end
end