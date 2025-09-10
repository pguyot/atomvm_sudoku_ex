defmodule AtomvmSudokuEx.IsSetValidTest do
  use ExUnit.Case
  alias AtomvmSudokuEx.SudokuGrid

  # Access the private function for testing
  defp is_set_valid(list) do
    length(Enum.uniq(list)) == length(list)
  end

  defp current_buggy_is_set_valid(list) do
    Enum.uniq(list) == Enum.sort(list)
  end

  test "current buggy implementation fails valid cases" do
    # These should be valid (no duplicates) but current implementation rejects them
    assert current_buggy_is_set_valid([1, 2, 3]) == true   # sorted, so passes
    assert current_buggy_is_set_valid([3, 1, 2]) == false  # not sorted, so fails! BUG!
    assert current_buggy_is_set_valid([1, 4, 7, 6, 2]) == false  # not sorted, so fails! BUG!
  end

  test "current buggy implementation correctly detects duplicates" do
    # These should be invalid (duplicates) and current implementation correctly rejects them
    assert current_buggy_is_set_valid([1, 1, 2]) == false  # duplicates, correctly fails
    assert current_buggy_is_set_valid([1, 4, 6, 6, 2]) == false  # duplicates, correctly fails
  end

  test "correct implementation works for all cases" do
    # Valid cases (no duplicates) - should return true
    assert is_set_valid([1, 2, 3]) == true
    assert is_set_valid([3, 1, 2]) == true
    assert is_set_valid([1, 4, 7, 6, 2]) == true
    assert is_set_valid([]) == true

    # Invalid cases (duplicates) - should return false  
    assert is_set_valid([1, 1, 2]) == false
    assert is_set_valid([1, 4, 6, 6, 2]) == false
    assert is_set_valid([1, 2, 3, 3]) == false
  end

  test "demonstrate the bug with sudoku validation" do
    empty_grid = for x <- 1..9, y <- 1..9, into: %{}, do: {{x, y}, 0}
    
    # Put a 1 at {1,1} 
    grid1 = Map.put(empty_grid, {1, 1}, 1)
    
    # Now test if we can put a 2 at {1,2} - this SHOULD be valid
    # Row 1 would be [1, 2] after this move - no duplicates, should be valid
    assert SudokuGrid.is_move_valid(grid1, {1, 2}, 2) == true, 
           "Should be able to put 2 at {1,2} when {1,1} has 1"
  end
end