defmodule AtomvmSudokuEx.Dom do
  @moduledoc """
  DOM manipulation utilities for generating JavaScript to manipulate the DOM.
  """

  defstruct name: nil, attributes: [], children: []

  @type dom_element :: %__MODULE__{
          name: iodata() | atom(),
          attributes: [dom_attribute()],
          children: [dom_node()]
        }

  @type dom_node :: text_node() | dom_element()
  @type dom_attribute :: {name :: iodata() | atom(), value :: iodata()}
  @type text_node :: {:text, iodata()} | binary()

  @doc """
  Generate a script to call appendChild method on an element with another element
  """
  @spec append_child_script(iodata(), dom_element() | iodata(), pos_integer()) ::
          {iodata(), pos_integer()}
  def append_child_script(query_selector, element, element_var_id) do
    element_method(query_selector, "appendChild", element, element_var_id)
  end

  @doc """
  Generate a script to call replaceChildren method on an element with another element
  """
  @spec replace_children_script(iodata(), dom_element() | iodata(), pos_integer()) ::
          {iodata(), pos_integer()}
  def replace_children_script(query_selector, element, element_var_id) do
    element_method(query_selector, "replaceChildren", element, element_var_id)
  end

  @doc """
  Generate a script to call replaceWith method on an element with another element
  """
  @spec replace_with_script(iodata(), dom_element() | iodata(), pos_integer()) ::
          {iodata(), pos_integer()}
  def replace_with_script(query_selector, element, element_var_id) do
    element_method(query_selector, "replaceWith", element, element_var_id)
  end

  defp element_method(query_selector, method, element, element_var_id) do
    {create_element_script, new_element_var_id, parameter} =
      case is_struct(element, __MODULE__) do
        true ->
          {script, new_id} = create_element_script(element, element_var_id)
          {script, new_id, ["e", Integer.to_string(element_var_id)]}

        false ->
          {[], element_var_id, ["\"", escape(element), "\""]}
      end

    append_script = [
      create_element_script,
      "document.querySelector(\"",
      escape(query_selector),
      "\").",
      method,
      "(",
      parameter,
      ");"
    ]

    {append_script, new_element_var_id}
  end

  @doc """
  Generate a script to call createElement method with an element
  """
  @spec create_element_script(dom_element(), pos_integer()) :: {iodata(), pos_integer()}
  def create_element_script(
        %__MODULE__{name: element_name, attributes: attributes, children: children},
        element_var_id
      ) do
    create_script = [
      "const e",
      Integer.to_string(element_var_id),
      "=document.createElement(\"",
      escape(element_name),
      "\");"
    ]

    attribute_script =
      for {attribute_name, attribute_value} <- attributes do
        [
          "e",
          Integer.to_string(element_var_id),
          ".setAttribute(\"",
          escape(attribute_name),
          "\",\"",
          escape(attribute_value),
          "\");"
        ]
      end

    {create_children_scripts, next_id} =
      Enum.reduce(children, {[], element_var_id + 1}, fn child, {acc_s, acc_id} ->
        {child_script, new_acc_id} =
          case child do
            {:text, text} ->
              {[
                 "e",
                 Integer.to_string(element_var_id),
                 ".append(\"",
                 escape(text),
                 "\");"
               ], acc_id}

            text when is_binary(text) ->
              {[
                 "e",
                 Integer.to_string(element_var_id),
                 ".append(\"",
                 escape(text),
                 "\");"
               ], acc_id}

            %__MODULE__{} = child_node ->
              {child_create_script, child_next_id} = create_element_script(child_node, acc_id)

              {[
                 child_create_script,
                 "e",
                 Integer.to_string(element_var_id),
                 ".append(e",
                 Integer.to_string(acc_id),
                 ");"
               ], child_next_id}
          end

        {[child_script | acc_s], new_acc_id}
      end)

    {[create_script, attribute_script, Enum.reverse(create_children_scripts)], next_id}
  end

  defp escape(atom) when is_atom(atom) do
    escape(Atom.to_string(atom))
  end

  defp escape(list) when is_list(list) do
    escape(IO.iodata_to_binary(list))
  end

  defp escape(bin) when is_binary(bin) do
    escape(String.to_charlist(bin), [])
  end

  defp escape([], acc) do
    Enum.reverse(acc)
  end

  defp escape([?" | tail], acc) do
    escape(tail, [?", ?\\ | acc])
  end

  defp escape([h | tail], acc) do
    escape(tail, [h | acc])
  end
end