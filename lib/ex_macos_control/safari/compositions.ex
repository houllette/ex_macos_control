defmodule ExMacOSControl.Safari.Compositions do
  @moduledoc false
  alias ExMacOSControl.{Automation, Composition, Desktop, Error, Safari, Validation, Wait}
  alias ExMacOSControl.Safari.Page

  @execution [:timeout, :max_output_bytes]
  @waiting @execution ++ [:interval]

  def open_page(url, opts \\ []) do
    with :ok <- Automation.required_string(url, "URL") do
      Desktop.with_lock(
        fn -> do_open_page(url) end,
        opts
      )
    end
  end

  def close_page(page, opts \\ [])

  def close_page(%Page{owned: true} = page, opts) do
    Automation.action(
      "com.apple.Safari",
      """
      var w=app.windows.byId(input.window_id);
      if(w.exists()){
        if(w.tabs.length!==1)throw new Error('Owned Safari window has additional tabs; refusing cleanup');
        app.close(w);
      }
      """,
      %{window_id: page.window_id},
      opts
    )
  end

  def close_page(_page, _opts), do: Automation.invalid("Only an owned Safari page may be closed by this helper")

  def with_page(url, opts \\ [], fun) when is_function(fun, 1) do
    with :ok <- waiting_options(opts) do
      Composition.run(
        fn -> do_with_page(url, opts, fun) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  def current_page(opts \\ []) do
    with {:ok, target} <-
           Automation.query(
             "com.apple.Safari",
             """
             if(app.windows.length===0)throw new Error('Safari window not found');
             var w=app.windows[0],t=w.currentTab();
             return {window_id:w.id(),tab_index:t.index(),url:t.url()};
             """,
             %{},
             opts
           ) do
      {:ok, %Page{window_id: target.window_id, tab_index: target.tab_index, url: target.url}}
    end
  end

  def snapshot(%Page{} = page, opts \\ []) do
    dom(
      page,
      "return {title:document.title,url:location.href,text:document.body?document.body.innerText:'',selection:String(window.getSelection())};",
      %{},
      opts
    )
  end

  def wait_for_ready(%Page{} = page, opts \\ []) do
    poll(
      page,
      "return document.readyState==='complete' && (input.url==='about:blank' || location.href!=='about:blank');",
      %{url: page.url},
      opts
    )
  end

  def wait_for_selector(%Page{} = page, selector, opts \\ []) do
    with :ok <- Automation.required_string(selector, "CSS selector") do
      poll(page, "return document.querySelector(input.selector)!==null;", %{selector: selector}, opts)
    end
  end

  def navigate_and_wait(%Page{} = page, url, opts \\ []) do
    with :ok <- Automation.required_string(url, "URL"),
         :ok <- waiting_options(opts) do
      Composition.run(fn -> navigate(page, url, Keyword.take(opts, [:interval])) end, Keyword.take(opts, @execution))
    end
  end

  def text(%Page{} = page, selector, opts \\ []) do
    with :ok <- Automation.required_string(selector, "CSS selector") do
      dom(page, element() <> "return e.textContent;", %{selector: selector}, opts)
    end
  end

  def attribute(%Page{} = page, selector, attribute, opts \\ []) do
    with :ok <- Automation.required_string(selector, "CSS selector"),
         :ok <- Automation.required_string(attribute, "Attribute name") do
      dom(
        page,
        element() <> "return e.getAttribute(input.attribute);",
        %{selector: selector, attribute: attribute},
        opts
      )
    end
  end

  def extract(%Page{} = page, selectors, opts \\ []) do
    if is_map(selectors) and map_size(selectors) > 0 and
         Enum.all?(selectors, fn {key, value} -> is_binary(key) and is_binary(value) and value != "" end) do
      extract_fields(page, selectors, opts)
    else
      Automation.invalid("Selectors must be a non-empty map of string names to CSS selectors")
    end
  end

  defp extract_fields(page, selectors, opts) do
    case dom(
           page,
           """
           var result={};Object.keys(input.selectors).forEach(function(key){
             var e=document.querySelector(input.selectors[key]);
             if(!e)throw new Error('Element not found');
             Object.defineProperty(result,key,{value:e.textContent,enumerable:true});
           });return result;
           """,
           %{selectors: selectors},
           opts
         ) do
      {:ok, result} when is_map(result) -> {:ok, Map.new(result, fn {key, value} -> {to_string(key), value} end)}
      {:error, _} = error -> error
      _ -> Automation.invalid("Safari extraction did not return named fields")
    end
  end

  def fill(%Page{} = page, selector, value, opts \\ []) do
    with :ok <- Automation.required_string(selector, "CSS selector"),
         true <- is_binary(value),
         :ok <- waiting_options(opts) do
      Composition.run(
        fn -> do_fill(page, selector, value, opts) end,
        Keyword.take(opts, @execution)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Field value must be text")
    end
  end

  def fill_fields(%Page{} = page, fields, opts \\ []) do
    with :ok <- Validation.items(fields),
         true <-
           Enum.all?(fields, fn item ->
             match?({selector, value} when is_binary(selector) and is_binary(value), item)
           end),
         :ok <- waiting_options(opts) do
      Composition.run(
        fn -> do_fill_fields(page, fields, opts) end,
        Keyword.take(opts, @execution)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Fields must be a list of {selector, text} pairs")
    end
  end

  def click(%Page{} = page, selector, opts \\ []) do
    with :ok <- Automation.required_string(selector, "CSS selector"),
         :ok <- waiting_options(opts) do
      Composition.run(
        fn -> do_click(page, selector, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  def click_and_wait(%Page{} = page, selector, expected_selector, opts \\ []) do
    with :ok <- Automation.required_string(expected_selector, "Expected CSS selector"),
         :ok <- waiting_options(opts) do
      Composition.run(
        fn -> do_click_and_wait(page, selector, expected_selector, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  def extract_text(url, selector, opts \\ []) do
    with :ok <- Automation.required_string(selector, "CSS selector") do
      with_page(url, opts, &read_text_when_ready(&1, selector, opts))
    end
  end

  defp read_text_when_ready(page, selector, opts) do
    with :ok <- wait_for_selector(page, selector, Keyword.take(opts, [:interval])), do: text(page, selector)
  end

  defp navigate(page, url, opts) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

    with {:ok, previous} <-
           Composition.step(:navigation_marker, fn ->
             dom(page, "window.__exmc_navigation=input.token;return location.href;", %{token: token})
           end),
         :ok <- Composition.effect(:navigate_page, fn -> Safari.navigate(page.window_id, page.tab_index, url) end) do
      same_document = hd(String.split(previous, "#", parts: 2)) == hd(String.split(url, "#", parts: 2))

      poll(
        page,
        "return document.readyState==='complete' && (window.__exmc_navigation!==input.token || (input.same_document && location.href===input.url));",
        %{token: token, url: url, same_document: same_document},
        opts
      )
    end
  end

  defp poll(page, body, params, opts) do
    with :ok <- waiting_options(opts) do
      predicate = &dom(page, body, params, Keyword.merge(Keyword.take(opts, @execution), timeout: &1))
      Composition.step(:wait_for_page_state, &Wait.until/2, [predicate, Keyword.take(opts, [:timeout, :interval])])
    end
  end

  defp dom_action(page, body, params) do
    case dom(page, body <> "return true;", params, []) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
      _ -> {:error, Error.execution_error("Safari did not acknowledge the action")}
    end
  end

  defp dom(page, body, params, opts \\ []) do
    encoded = params |> Jason.encode!() |> Jason.encode!(escape: :javascript_safe)
    code = "JSON.stringify((function(input){" <> body <> "})(JSON.parse(" <> encoded <> ")))"

    Automation.query(
      "com.apple.Safari",
      """
      var w=byId(app.windows,input.window_id);
      if(input.owned && w.tabs.length!==1)throw new Error('Owned Safari window has additional tabs');
      var t=w.tabs[input.tab_index-1];if(!t.exists())throw new Error('Tab not found');
      return JSON.parse(app.doJavaScript(input.code,{in:t}));
      """,
      %{window_id: page.window_id, tab_index: page.tab_index, owned: page.owned, code: code},
      opts
    )
  end

  defp element, do: "var e=document.querySelector(input.selector);if(!e)throw new Error('Element not found');"

  defp waiting_options(opts) do
    with :ok <- Automation.options(opts, @waiting),
         true <- is_integer(Keyword.get(opts, :interval, 50)) and Keyword.get(opts, :interval, 50) > 0 do
      :ok
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Interval must be a positive integer")
    end
  end

  defp do_open_page(url) do
    Composition.effect(:open_page, fn ->
      source = """
      on run argv
        tell application id "com.apple.Safari"
          make new document with properties {URL:item 1 of argv}
          return id of front window
        end tell
      end run
      """

      with {:ok, output} <- ExMacOSControl.run_applescript(source, args: [url]),
           {id, ""} when id > 0 <- Integer.parse(String.trim(output)) do
        {:ok, %Page{window_id: id, tab_index: 1, url: url, owned: true}}
      else
        {:error, _} = error -> error
        _ -> {:error, Error.execution_error("Safari did not return a window ID", outcome: :unknown)}
      end
    end)
  end

  defp do_with_page(url, opts, fun) do
    with {:ok, page} <- open_page(url) do
      Composition.resource(
        page,
        &use_ready_page(&1, opts, fun),
        &close_page/1
      )
    end
  end

  defp use_ready_page(page, opts, fun) do
    with :ok <- wait_for_ready(page, Keyword.take(opts, [:interval])), do: fun.(page)
  end

  defp do_fill(page, selector, value, opts) do
    with :ok <- wait_interactable(page, selector, true, Keyword.take(opts, [:interval])),
         :ok <-
           Composition.effect(:fill_field, fn ->
             dom_action(
               page,
               element() <>
                 """
                 if(e.disabled||e.readOnly)throw new Error('Element is not editable');
                 var proto=Object.getPrototypeOf(e),descriptor;
                 while(proto&&!descriptor){descriptor=Object.getOwnPropertyDescriptor(proto,'value');proto=Object.getPrototypeOf(proto);}
                 if(!descriptor||!descriptor.set)throw new Error('Element has no value setter');
                 descriptor.set.call(e,input.value);
                 e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));
                 """,
               %{selector: selector, value: value}
             )
           end) do
      poll(
        page,
        "var e=document.querySelector(input.selector);return !!e && e.value===input.value;",
        %{selector: selector, value: value},
        Keyword.take(opts, [:interval])
      )
    end
  end

  defp do_fill_fields(page, fields, opts) do
    Composition.map(fields, :fill_field, fn {selector, value} ->
      fill(page, selector, value, Keyword.take(opts, [:interval]))
    end)
  end

  defp do_click(page, selector, opts) do
    with :ok <- wait_interactable(page, selector, false, Keyword.take(opts, [:interval])) do
      Composition.effect(:click_element, fn ->
        dom_action(page, element() <> "if(e.disabled)throw new Error('Element is disabled');e.click();", %{
          selector: selector
        })
      end)
    end
  end

  defp wait_interactable(page, selector, editable, opts) do
    poll(
      page,
      "var e=document.querySelector(input.selector);return !!e && !e.disabled && (!input.editable || !e.readOnly);",
      %{selector: selector, editable: editable},
      opts
    )
  end

  defp do_click_and_wait(page, selector, expected_selector, opts) do
    with :ok <- click(page, selector, Keyword.take(opts, [:interval])),
         do: wait_for_selector(page, expected_selector, Keyword.take(opts, [:interval]))
  end
end
