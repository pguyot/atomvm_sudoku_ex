# Copyright 2023 Paul Guyot <pguyot@kallisys.net>
# SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

defmodule AtomvmSudokuEx.SudokuGridTest do
  use ExUnit.Case
  alias AtomvmSudokuEx.SudokuGrid

  def random_generator(n) do
    case Process.get(:rand_seed) do
      nil -> :rand.seed(:exs1024s, {123, 123534, 345345})
      _ -> :ok
    end
    :rand.uniform(n)
  end

  @tag timeout: 120_000
  test "create solution" do
    solution = SudokuGrid.random_solution(&random_generator/1)
    assert_solution_is_valid(solution)
  end

  @tag timeout: 120_000
  test "create puzzle" do
    {hints, puzzle, solution} = SudokuGrid.random_puzzle(&random_generator/1)
    assert hints < 54
    assert length(SudokuGrid.to_list(puzzle)) == 81
    assert count_hints(puzzle) == hints
    assert length(SudokuGrid.to_list(solution)) == 81
    assert count_hints(solution) == 81
    assert SudokuGrid.is_solved(solution)
  end

  @tag timeout: 10_000
  test "create proper puzzle" do
    {puzzle, solution} = SudokuGrid.parallel_random_puzzle(&random_generator/1, 25, 5000)
    assert length(SudokuGrid.to_list(puzzle)) == 81
    assert count_hints(puzzle) <= 25
    assert length(SudokuGrid.to_list(solution)) == 81
    assert count_hints(solution) == 81
    assert SudokuGrid.is_solved(solution)
  end

  test "is_move_valid" do
    empty_grid = for x <- 1..9, y <- 1..9, into: %{}, do: {{x, y}, 0}
    assert SudokuGrid.is_move_valid(empty_grid, {1, 1}, 1)
    
    grid1 = Map.put(empty_grid, {1, 1}, 1)
    refute SudokuGrid.is_move_valid(grid1, {1, 9}, 1)  # Same row
    refute SudokuGrid.is_move_valid(grid1, {9, 1}, 1)  # Same column
    refute SudokuGrid.is_move_valid(grid1, {2, 2}, 1)  # Same 3x3 square
  end

  test "is_solved" do
    empty_grid = for x <- 1..9, y <- 1..9, into: %{}, do: {{x, y}, 0}
    refute SudokuGrid.is_solved(empty_grid)
    
    # Full yet invalid grid (all rows have same number)
    full_yet_invalid_grid = for x <- 1..9, y <- 1..9, into: %{}, do: {{x, y}, x}
    assert SudokuGrid.is_solved(full_yet_invalid_grid)
  end

  defp assert_solution_is_valid(solution) do
    assert length(SudokuGrid.to_list(solution)) == 81
    
    # Each cell should have exactly one value
    for x <- 1..9, y <- 1..9 do
      assert length(SudokuGrid.get(x, y, solution)) == 1
    end
    
    # Each row should contain 1-9
    for y <- 1..9 do
      row_values = for x <- 1..9, do: hd(SudokuGrid.get(x, y, solution))
      assert Enum.sort(row_values) == Enum.to_list(1..9)
    end
    
    # Each column should contain 1-9
    for x <- 1..9 do
      col_values = for y <- 1..9, do: hd(SudokuGrid.get(x, y, solution))
      assert Enum.sort(col_values) == Enum.to_list(1..9)
    end
    
    # Each 3x3 square should contain 1-9
    for sx <- 0..2, sy <- 0..2 do
      square_values = for x <- (sx * 3 + 1)..(sx * 3 + 3), 
                          y <- (sy * 3 + 1)..(sy * 3 + 3), 
                          do: hd(SudokuGrid.get(x, y, solution))
      assert Enum.sort(square_values) == Enum.to_list(1..9)
    end
  end

  defp count_hints(puzzle) do
    puzzle
    |> SudokuGrid.to_list()
    |> Enum.count(fn {{_x, _y}, v} -> v != 0 end)
  end
end