defmodule ExMacOSControl.Accessibility do
  @moduledoc """
  Bounded accessibility inspection, attributes/actions and state-based waits.

  Targets are process names or Unix PIDs. A path is a list of selectors with
  role, subrole, identifier, title and optional 1-based index. Ambiguous selectors
  are rejected. Key delivery first activates and verifies the target process.
  """
  alias ExMacOSControl.{Automation, Composition, Desktop, Wait}
  @app "com.apple.systemevents"

  def tree(process, opts \\ []) do
    with :ok <- Automation.options(opts, [:path, :depth, :max_nodes, :timeout, :max_output_bytes]),
         :ok <- path(Keyword.get(opts, :path, [])),
         depth = Keyword.get(opts, :depth, 3),
         maximum = Keyword.get(opts, :max_nodes, 200),
         true <- is_integer(depth) and depth in 0..10 and is_integer(maximum) and maximum in 1..1000 do
      query(
        process,
        Keyword.get(opts, :path, []),
        """
        var count=0;
        function walk(o,depth) {
          count++;
          var node={role:attr(o,'AXRole'),subrole:attr(o,'AXSubrole'),identifier:attr(o,'AXIdentifier'),
            title:attr(o,'AXTitle'),value:attr(o,'AXValue'),attributes:o.attributes.name(),actions:o.actions.name(),children:[],truncated:false};
          var children=o.uiElements;
          if(depth===0){node.truncated=children.length>0;return node;}
          for(var i=0;i<children.length;i++) {
            if(count>=input.max_nodes){node.truncated=true;break;}
            node.children.push(walk(children[i],depth-1));
          }
          return node;
        }
        return walk(resolve(false),input.depth);
        """,
        %{depth: depth, max_nodes: maximum},
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Tree depth must be 0..10 and max_nodes must be 1..1000")
    end
  end

  def exists?(process, selectors, opts \\ []), do: query(process, selectors, "return resolve(true)!==null;", %{}, opts)

  def get_attribute(process, selectors, attribute, opts \\ []) do
    with :ok <- Automation.required_string(attribute, "Attribute name") do
      query(
        process,
        selectors,
        "var o=resolve(false),a=o.attributes.byName(input.attribute); if(!a.exists()) throw new Error('Attribute not found'); return a.value();",
        %{attribute: attribute},
        opts
      )
    end
  end

  def set_attribute(process, selectors, attribute, value, opts \\ []) do
    with :ok <- Automation.required_string(attribute, "Attribute name") do
      action(
        process,
        selectors,
        "var a=resolve(false).attributes.byName(input.attribute); if(!a.exists()||!a.settable()) throw new Error('Attribute is unavailable or read-only'); a.value=input.value;",
        %{attribute: attribute, value: value},
        opts
      )
    end
  end

  def perform_action(process, selectors, action, opts \\ []) do
    with :ok <- Automation.required_string(action, "Action name") do
      action(
        process,
        selectors,
        "var a=resolve(false).actions.byName(input.action); if(!a.exists()) throw new Error('Action not found'); app.perform(a);",
        %{action: action},
        opts
      )
    end
  end

  def click(process, selectors, opts \\ []), do: perform_action(process, selectors, "AXPress", opts)

  def press_key_code(process, code, opts \\ []) do
    modifiers = Keyword.get(opts, :using, [])

    with :ok <- Automation.options(opts, [:using, :timeout, :max_output_bytes]),
         true <- is_integer(code) and code in 0..127,
         true <- is_list(modifiers) and Enum.all?(modifiers, &(&1 in [:command, :control, :option, :shift])) do
      modifiers = Enum.map(modifiers, &(Atom.to_string(&1) <> " down"))

      action(
        process,
        [],
        "focus(); app.keyCode(input.code,{using:input.modifiers});",
        %{code: code, modifiers: modifiers},
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Key code must be 0..127 and modifiers must be supported keys")
    end
  end

  def click_menu_path(process, names, opts \\ []) do
    if is_list(names) and length(names) >= 2 and Enum.all?(names, &(is_binary(&1) and &1 != "")) do
      action(
        process,
        [],
        "focus(); var o=p.menuBars[0].menuBarItems.byName(input.names[0]); for(var i=1;i<input.names.length;i++){if(!o.exists()) throw new Error('Menu not found'); app.click(o); o=o.menus[0].menuItems.byName(input.names[i]);} if(!o.exists()||!o.enabled()) throw new Error('Menu item unavailable'); app.click(o);",
        %{names: names},
        opts
      )
    else
      Automation.invalid("Menu path needs at least a menu and an item")
    end
  end

  def wait_for(process, selectors, opts \\ []) do
    with :ok <- Automation.options(opts, [:timeout, :interval, :max_output_bytes]) do
      Wait.until(
        fn remaining ->
          exists?(process, selectors,
            timeout: remaining,
            max_output_bytes: Keyword.get(Automation.execution_options(opts), :max_output_bytes, 10_485_760)
          )
        end,
        Keyword.take(opts, [:timeout, :interval])
      )
    end
  end

  @doc "Waits for a specific attribute value without repeating an action."
  def wait_for_attribute(process, selectors, attribute, value, opts \\ []) do
    with :ok <- path(selectors),
         :ok <- Automation.required_string(attribute, "Attribute name"),
         :ok <- composition_options(opts) do
      wait_state(
        process,
        selectors,
        "var o=resolve(true);return o!==null && attr(o,input.attribute)===input.value;",
        %{attribute: attribute, value: value},
        opts
      )
    end
  end

  @doc "Waits until a target element disappears. Missing processes remain errors."
  def wait_until_gone(process, selectors, opts \\ []) do
    with :ok <- path(selectors), :ok <- composition_options(opts) do
      wait_state(process, selectors, "return resolve(true)===null;", %{}, opts)
    end
  end

  @doc "Waits for an editable AXValue, sets it once and verifies the resulting text."
  def fill(process, selectors, value, opts \\ []) do
    with :ok <- path(selectors),
         true <- is_binary(value),
         :ok <- composition_options(opts) do
      Desktop.with_lock(
        fn -> do_fill(process, selectors, value, opts) end,
        execution_opts(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Field value must be text")
    end
  end

  @doc "Fills a non-empty list of {selector_path, text} pairs in order, stopping on failure."
  def fill_fields(process, fields, opts \\ []) do
    with :ok <- Composition.validate_items(fields),
         :ok <- validate_fields(fields),
         :ok <- composition_options(opts) do
      Desktop.with_lock(
        fn -> do_fill_fields(process, fields, opts) end,
        execution_opts(opts)
      )
    end
  end

  @doc "Sets a checkbox to a desired boolean state, clicking at most once, then verifies AXValue."
  def set_checked(process, selectors, checked, opts \\ []) do
    with :ok <- path(selectors),
         true <- is_boolean(checked),
         :ok <- composition_options(opts) do
      Desktop.with_lock(
        fn -> do_set_checked(process, selectors, checked, opts) end,
        execution_opts(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Checked state must be a boolean")
    end
  end

  @doc "Waits until enabled, clicks once, and waits for an expected element to appear."
  def click_and_wait(process, selectors, expected, opts \\ []) do
    with :ok <- path(selectors), :ok <- path(expected), :ok <- composition_options(opts) do
      Desktop.with_lock(
        fn -> do_click_and_wait(process, selectors, expected, opts) end,
        execution_opts(opts)
      )
    end
  end

  defp toggle_if_needed(_process, _selectors, value, checked) when value == checked, do: :ok
  defp toggle_if_needed(_process, _selectors, 1, true), do: :ok
  defp toggle_if_needed(_process, _selectors, 0, false), do: :ok

  defp toggle_if_needed(process, selectors, _value, _checked),
    do: Composition.step(:toggle_checkbox, fn -> click(process, selectors) end)

  defp actionable(process, selectors, opts),
    do:
      wait_state(
        process,
        selectors,
        "var o=resolve(true);return o!==null && attr(o,'AXEnabled')!==false && o.actions.byName('AXPress').exists();",
        %{},
        opts
      )

  defp wait_state(process, selectors, body, params, opts) do
    Composition.step(:wait_for_element_state, fn ->
      Wait.until(
        fn remaining ->
          query(process, selectors, body, params, Keyword.put(execution_opts(opts), :timeout, remaining))
        end,
        Keyword.take(opts, [:timeout, :interval])
      )
    end)
  end

  defp validate_fields(fields) do
    Enum.reduce_while(fields, :ok, fn
      {selectors, value}, :ok when is_binary(value) ->
        case path(selectors) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end

      _, :ok ->
        {:halt, Automation.invalid("Fields must contain {selector_path, text} pairs")}
    end)
  end

  defp composition_options(opts) do
    with :ok <- Automation.options(opts, [:timeout, :interval, :max_output_bytes]),
         true <- is_integer(Keyword.get(opts, :interval, 50)) and Keyword.get(opts, :interval, 50) > 0 do
      :ok
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Interval must be a positive integer")
    end
  end

  defp execution_opts(opts), do: Keyword.take(opts, [:timeout, :max_output_bytes])
  defp wait_opts(opts), do: Keyword.take(opts, [:interval])

  defp path(selectors) do
    valid =
      is_list(selectors) and length(selectors) <= 20 and
        Enum.all?(selectors, fn step ->
          is_map(step) and Map.keys(step) -- [:role, :subrole, :title, :identifier, :index] == [] and
            map_size(step) > 0 and
            Enum.all?(step, fn
              {:index, value} -> is_integer(value) and value > 0
              {_key, value} -> is_binary(value)
            end)
        end)

    if valid, do: :ok, else: Automation.invalid("Invalid accessibility selector path")
  end

  defp action(process, selectors, body, params, opts) do
    case query(process, selectors, body <> "\nreturn true;", params, opts) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
      _ -> Automation.invalid("Accessibility action did not acknowledge completion")
    end
  end

  defp query(process, selectors, body, params, opts) do
    with :ok <- path(selectors),
         true <- (is_binary(process) and process != "") or (is_integer(process) and process > 0) do
      Automation.query(@app, prelude() <> body, Map.merge(params, %{process: process, path: selectors}), opts)
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Process must be a name or Unix PID")
    end
  end

  defp prelude do
    # Dereferencing can replace PID predicates with ambiguous process names.
    # Keep process and child specifiers scoped throughout traversal.
    """
    var matches=typeof input.process==='number' ? app.processes.whose({unixId:input.process}) : app.processes.whose({name:input.process});
    if(matches.length!==1) throw new Error('Missing or ambiguous process');
    var p=matches[0];
    function attr(o,name){var a=o.attributes.byName(name); return a.exists()?a.value():null;}
    function resolve(optional){
      var o=p;
      for(var i=0;i<input.path.length;i++){
        var s=input.path[i], elements=o.uiElements, children=[];
        for(var j=0;j<elements.length;j++){
          var c=elements[j];
          if((s.role===undefined||attr(c,'AXRole')===s.role) && (s.subrole===undefined||attr(c,'AXSubrole')===s.subrole) &&
            (s.identifier===undefined||attr(c,'AXIdentifier')===s.identifier) && (s.title===undefined||attr(c,'AXTitle')===s.title))children.push(c);
        }
        if(s.index!==undefined){o=children[s.index-1]; if(!o){if(optional)return null;throw new Error('Element not found');}}
        else {if(children.length===0&&optional)return null;if(children.length!==1)throw new Error('Missing or ambiguous element');o=children[0];}
      }
      return o;
    }
    function focus(){
      // System Events can report false even when this PID owns the foreground.
      ObjC.import('AppKit');
      var pid=p.unixId(),running=$.NSRunningApplication.runningApplicationWithProcessIdentifier(pid);
      if(running.isNil())throw new Error('Target process exited');
      function active(){
        var front=$.NSWorkspace.sharedWorkspace.frontmostApplication;
        return !front.isNil()&&Number(front.processIdentifier)===pid;
      }
      if(!active())running.activateWithOptions($.NSApplicationActivateIgnoringOtherApps);
      for(var i=0;i<40&&!active();i++) $.NSThread.sleepForTimeInterval(0.025);
      if(!active())throw new Error('Target process did not become frontmost');
    }
    """
  end

  defp do_fill(process, selectors, value, opts) do
    with :ok <-
           wait_state(
             process,
             selectors,
             "var o=resolve(true);if(!o)return false;var a=o.attributes.byName('AXValue');return attr(o,'AXEnabled')!==false && a.exists() && a.settable();",
             %{},
             wait_opts(opts)
           ),
         :ok <- Composition.step(:fill_field, fn -> set_attribute(process, selectors, "AXValue", value) end) do
      wait_for_attribute(process, selectors, "AXValue", value, wait_opts(opts))
    end
  end

  defp do_fill_fields(process, fields, opts) do
    Composition.map(fields, :fill_field, fn {selectors, value} ->
      fill(process, selectors, value, wait_opts(opts))
    end)
  end

  defp do_set_checked(process, selectors, checked, opts) do
    with :ok <- actionable(process, selectors, wait_opts(opts)),
         {:ok, value} <- Composition.step(:checkbox_state, fn -> get_attribute(process, selectors, "AXValue") end),
         :ok <- toggle_if_needed(process, selectors, value, checked) do
      wait_for_attribute(process, selectors, "AXValue", if(checked, do: 1, else: 0), wait_opts(opts))
    end
  end

  defp do_click_and_wait(process, selectors, expected, opts) do
    with :ok <- actionable(process, selectors, wait_opts(opts)),
         :ok <- Composition.step(:click_element, fn -> click(process, selectors) end) do
      Composition.step(:wait_for_result, fn -> wait_for(process, expected, wait_opts(opts)) end)
    end
  end
end
