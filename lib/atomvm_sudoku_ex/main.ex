defmodule AtomvmSudokuEx.Main do
  use GenServer
  alias AtomvmSudokuEx.{Dom, SudokuGrid}

  @process_name :main

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: @process_name)
  end

  defstruct countdown: nil, start: nil, grid: nil, solution: nil, help_uses: 0

  @count_down 10
  @max_processing_time @count_down * 1000 - 500

  @impl true
  def init(_args) do
    Popcorn.Wasm.register(@process_name)

    loader_script = loader_init_script(@count_down)
    Popcorn.Wasm.run_js(loader_script)

    start = :erlang.system_time(:millisecond)

    main_process = self()
    spawn_link(fn -> generate_grid(main_process) end)

    {:ok, %__MODULE__{countdown: @count_down, start: start}, 1000}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(_request, _from, state) do
    {:reply, {:error, :unimplemented}, state}
  end

  @impl true
  def handle_info(:timeout, state) do
    update_script = loader_update_script(state.countdown)
    Popcorn.Wasm.run_js(update_script)

    case state.countdown do
      0 -> {:noreply, state}
      n -> {:noreply, %{state | countdown: n - 1}, 1000}
    end
  end

  def handle_info({:puzzle, puzzle, solution}, state) do
    IO.puts("Received puzzle message with #{map_size(puzzle)} cells")
    end_time = :erlang.system_time(:millisecond)
    delta = end_time - state.start
    IO.puts("Creating puzzle script...")
    puzzle_script = create_puzzle_script(puzzle, delta)
    IO.puts("Running puzzle script...")
    Popcorn.Wasm.run_js(puzzle_script)

    Enum.each(puzzle, fn {{x, y}, val} ->
      case val do
        0 ->
          cell_id = puzzle_cell_id(x, y)
          {:ok, cell_ref} = Popcorn.Wasm.run_js("() => document.querySelector('##{cell_id}')")
          {:ok, _ref} = Popcorn.Wasm.register_event_listener(:click, [
            target_node: cell_ref,
            custom_data: {x, y}
          ])

        _ ->
          :ok
      end
    end)

    {:ok, help_button_ref} = Popcorn.Wasm.run_js("() => document.querySelector('button.help')")
    {:ok, _ref} = Popcorn.Wasm.register_event_listener(:click, [
      target_node: help_button_ref,
      custom_data: :help
    ])

    {:noreply, %{state | grid: puzzle, solution: solution, start: end_time}}
  end

  def handle_info({:wasm_event, :click, _event_data, :help}, state) do
    {update_script, new_grid} = help_script(state.grid, state.solution)
    Popcorn.Wasm.run_js(update_script)

    {:noreply, %{state | grid: new_grid, help_uses: state.help_uses + 1}}
  end

  def handle_info({:wasm_event, :click, _event_data, {_x, _y} = position}, state) do
    end_time = :erlang.system_time(:millisecond)
    old_value = Map.get(state.grid, position)
    new_value = find_next_value(state.grid, position, old_value)
    new_grid = Map.put(state.grid, position, new_value)
    update_script = puzzle_update_value_script(position, new_value)
    Popcorn.Wasm.run_js(update_script)

    case SudokuGrid.is_solved(new_grid) do
      true ->
        solved_script = puzzle_solved_script(end_time - state.start, state.help_uses)
        Popcorn.Wasm.run_js(solved_script)

      false ->
        :ok
    end

    {:noreply, %{state | grid: new_grid}}
  end

  def handle_info(msg, state) do
    IO.puts("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  defp loader_init_script(count_down) do
    {script, _} = Dom.append_child_script("#root", loader_element(count_down), 1)
    "() => { void (#{script}); }"
  end

  defp loader_update_script(n) when n > 0 do
    {script, _} = Dom.replace_children_script(".loader-countdown", Integer.to_string(n), 1)
    "() => { void (#{script}); }"
  end

  defp loader_update_script(0) do
    {script, _} = Dom.replace_children_script("#loader", late_loader_element(), 1)
    "() => { void (#{script}); }"
  end

  defp create_puzzle_script(puzzle, delta) do
    {script, _} = Dom.replace_with_script("#loader", puzzle_table(puzzle, delta), 1)
    script_str = IO.iodata_to_binary(script)
    # Ensure the function doesn't return the result of the DOM operation
    final_script = "() => { void (#{script_str}); }"
    IO.puts("Generated puzzle script: #{String.slice(final_script, 0, 200)}...")
    final_script
  end

  defp loader_element(n) do
    %Dom{
      name: "div",
      attributes: [{"id", "loader"}],
      children: [
        %Dom{
          name: "div",
          attributes: [{"class", "loader-countdown"}],
          children: [Integer.to_string(n)]
        },
        %Dom{
          name: "p",
          attributes: [{"class", "loader-caption"}],
          children: ["Creating a completely random new grid"]
        }
      ]
    }
  end

  defp late_loader_element do
    %Dom{
      name: "div",
      attributes: [{"class", "late-loader-caption"}],
      children: ["Sorry, AtomVM is still creating a grid..."]
    }
  end

  defp puzzle_table(puzzle, delta) do
    %Dom{
      name: "table",
      attributes: [{"class", "sudoku-grid"}],
      children: [
        puzzle_caption(delta),
        puzzle_help_header(),
        puzzle_tbody(puzzle)
      ]
    }
  end

  defp puzzle_tbody(puzzle) do
    %Dom{
      name: "tbody",
      children: for(x <- 1..9, do: puzzle_row(x, puzzle))
    }
  end

  defp puzzle_caption(delta) do
    %Dom{
      name: "caption",
      children: ["Grid generated by AtomVM in #{delta}ms"]
    }
  end

  defp puzzle_help_header do
    %Dom{
      name: "thead",
      children: [
        %Dom{
          name: "tr",
          attributes: [{"colspan", "9"}],
          children: [
            %Dom{
              name: "th",
              attributes: [{"colspan", "9"}],
              children: [help_button()]
            }
          ]
        }
      ]
    }
  end

  defp help_button do
    %Dom{
      name: "button",
      attributes: [{"class", "help"}],
      children: ["help"]
    }
  end

  defp puzzle_row(x, puzzle) do
    %Dom{
      name: "tr",
      children: for(y <- 1..9, do: puzzle_cell(x, y, puzzle))
    }
  end

  @spec puzzle_cell_id(1..9, 1..9) :: String.t()
  defp puzzle_cell_id(x, y) do
    "cell-#{x}-#{y}"
  end

  defp puzzle_cell(x, y, puzzle) do
    {children, class} =
      case Map.get(puzzle, {x, y}) do
        0 -> {[], "input"}
        hint -> {[Integer.to_string(hint)], "hint"}
      end

    id = puzzle_cell_id(x, y)

    %Dom{
      name: "td",
      attributes: [{"class", class}, {"id", id}],
      children: children
    }
  end

  defp generate_grid(parent) do
    IO.puts("Starting grid generation...")
    random_generator = fn x -> rem(:rand.uniform(x * 1000), x) + 1 end

    IO.puts("Calling parallel_random_puzzle with max_processing_time: #{@max_processing_time}")
    start_time = :erlang.system_time(:millisecond)
    
    {puzzle, solution} =
      SudokuGrid.parallel_random_puzzle(random_generator, 25, 4, @max_processing_time)

    end_time = :erlang.system_time(:millisecond)
    IO.puts("Grid generation completed in #{end_time - start_time}ms")

    send(parent, {:puzzle, puzzle, solution})
  end

  defp find_next_value(grid, position, old_value) do
    candidate = rem(old_value + 1, 10)

    case SudokuGrid.is_move_valid(grid, position, candidate) do
      true -> candidate
      false -> find_next_value(grid, position, candidate)
    end
  end

  defp puzzle_update_value_script({x, y}, new_value) do
    id = puzzle_cell_id(x, y)

    content =
      case new_value do
        0 -> ""
        _ -> Integer.to_string(new_value)
      end

    {script, _} = Dom.replace_children_script("##{id}", content, 1)
    "() => { void (#{script}); }"
  end

  defp puzzle_solved_script(delta_ms, help_uses) do
    solved_caption_text =
      case help_uses do
        0 -> "Grid solved in #{div(delta_ms, 1000)}s without using help"
        1 -> "Grid solved in #{div(delta_ms, 1000)}s with 1 use of help"
        n -> "Grid solved in #{div(delta_ms, 1000)}s with #{n} uses of help"
      end

    {script, _} = Dom.replace_children_script(".sudoku-grid caption", solved_caption_text, 1)
    "() => { void (#{script}); }"
  end

  defp help_script(grid, solution) do
    {errors, hints} =
      Enum.reduce(grid, {[], []}, fn {{x, y}, val}, {acc_errors, acc_hints} ->
        case Map.get(solution, {x, y}) do
          ^val ->
            {acc_errors, acc_hints}

          _other_val when val != 0 ->
            {[{x, y} | acc_errors], acc_hints}

          other_val when val == 0 ->
            {acc_errors, [{{x, y}, other_val} | acc_hints]}
        end
      end)

    case {errors, hints} do
      {[], []} ->
        {script, _} =
          Dom.replace_children_script(
            ".sudoku-grid caption",
            "Grid is solved, cannot help further with it",
            1
          )

        {"() => { void (#{script}); }", grid}

      {[], _} ->
        help_with(&help_with_hint/2, grid, hints)

      {[_ | _], _} ->
        help_with(&help_with_error/2, grid, errors)
    end
  end

  defp help_with(fun, grid, helps) do
    [{_, first_help} | _] =
      Enum.sort(Enum.map(helps, fn help -> {:rand.uniform(), help} end))

    fun.(grid, first_help)
  end

  defp help_with_hint(grid, {{x, y}, val}) do
    {raw_script, _} = Dom.replace_children_script("##{puzzle_cell_id(x, y)}", Integer.to_string(val), 1)
    script = "() => { void (#{raw_script}); }"
    new_grid = Map.put(grid, {x, y}, val)
    {script, new_grid}
  end

  defp help_with_error(grid, {x, y}) do
    {raw_script, _} = Dom.replace_children_script("##{puzzle_cell_id(x, y)}", "", 1)
    script = "() => { void (#{raw_script}); }"
    new_grid = Map.put(grid, {x, y}, 0)
    {script, new_grid}
  end
end