defmodule ExMacOSControl.Safari.Compositions do
  @moduledoc false
  alias ExMacOSControl.{Automation, Composition, Desktop, Error, Validation, Wait}
  alias ExMacOSControl.Desktop.Session
  alias ExMacOSControl.Safari.Page

  @instance """
  function safariInstance(){
    ObjC.import('AppKit');
    var all=$.NSRunningApplication.runningApplicationsWithBundleIdentifier($('com.apple.Safari'));
    if(Number(all.count)!==1)throw new Error('Safari application instance is missing or ambiguous');
    var p=all.firstObject,started=p.launchDate;
    if(started.isNil())throw new Error('Safari launch identity unavailable');
    return {application_pid:Number(p.processIdentifier),application_started_at:Number(started.timeIntervalSince1970)};
  }
  function guardInstance(expected){
    if(expected.application_pid===null && expected.application_started_at===null)return;
    var actual=safariInstance();
    if(actual.application_pid!==expected.application_pid || actual.application_started_at!==expected.application_started_at)
      throw new Error('Safari application instance changed');
  }
  """
  @document_guard """
  if(guard.expected_url!==null && location.href!==guard.expected_url)throw new Error('Safari document URL changed');
  if(guard.document_token!==null && document.__exmc_document!==guard.document_token)throw new Error('Safari document changed');
  """

  @execute_dom """
  function runDOM(tab){
    var reply=JSON.parse(app.doJavaScript(input.code,{in:tab}));
    if(!reply || reply.exmc_dom!==1)throw new Error('Invalid Safari document acknowledgement');
    if(reply.ok!==true)throw new Error(reply.error || 'Safari document operation failed');
    return reply.result;
  }
  """

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
      @instance <>
        "guardInstance(input);" <>
        @execute_dom <>
        """
        var windows=app.windows(),w=null;
        for(var i=0;i<windows.length;i++){if(windows[i].id()===input.window_id){w=windows[i];break;}}
        if(w){
          var tabs=w.tabs();
          if(tabs && tabs.length>0){
            if(tabs.length!==1)throw new Error('Owned Safari window has additional tabs; refusing cleanup');
            if(input.document_token!==null || input.expected_url!==null)
              runDOM(tabs[0]);
            app.close(w);
          }
        }
        """,
      Map.merge(target(page), %{code: browser_code(page, "return true;", %{})}),
      opts
    )
  end

  def close_page(_page, _opts), do: Automation.invalid("Only an owned Safari page may be closed by this helper")

  def with_page(url, opts \\ [], fun) when is_function(fun, 1) do
    with :ok <- waiting_options(opts) do
      Session.with_apps(
        ["com.apple.Safari"],
        fn -> do_with_page(url, opts, fun) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  def current_page(opts \\ []) do
    with {:ok, target} <-
           Automation.query(
             "com.apple.Safari",
             @instance <>
               """
               var instance=safariInstance();
               if(app.windows.length===0)throw new Error('Safari window not found');
               var w=app.windows[0],t=w.currentTab();
               guardInstance(instance);
               return {window_id:w.id(),tab_index:t.index(),url:t.url(),application_pid:instance.application_pid,application_started_at:instance.application_started_at};
               """,
             %{},
             opts
           ) do
      {:ok, struct!(Page, target)}
    end
  end

  @doc "Pins the current URL and document instance. Reloads and navigation invalidate this returned handle."
  def pin_document(%Page{} = page, opts \\ []) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

    with {:ok, pinned} <-
           dom(
             page,
             """
             if(!document.__exmc_document)Object.defineProperty(document,'__exmc_document',{value:input.token});
             return {document_token:document.__exmc_document,expected_url:location.href};
             """,
             %{token: token},
             opts
           ) do
      {:ok, %{page | document_token: pinned.document_token, expected_url: pinned.expected_url}}
    end
  end

  @doc "Navigates deliberately and returns a newly pinned handle for the resulting document."
  def navigate_page(%Page{} = page, url, opts \\ []) do
    with :ok <- waiting_options(opts) do
      Composition.run(fn -> navigate_and_pin(page, url, opts) end, Keyword.take(opts, @execution))
    end
  end

  defp navigate_and_pin(page, url, opts) do
    with :ok <- navigate_and_wait(page, url, Keyword.take(opts, [:interval])),
         do: pin_document(%{unpin(page) | url: url})
  end

  defp unpin(page), do: %{page | document_token: nil, expected_url: nil}

  defp target(page),
    do:
      Map.take(Map.from_struct(page), [
        :window_id,
        :tab_index,
        :owned,
        :application_pid,
        :application_started_at,
        :document_token,
        :expected_url
      ])

  defp browser_code(page, body, params) do
    encoded = params |> Jason.encode!() |> Jason.encode!(escape: :javascript_safe)

    guard =
      page
      |> Map.from_struct()
      |> Map.take([:document_token, :expected_url])
      |> Jason.encode!()
      |> Jason.encode!(escape: :javascript_safe)

    "JSON.stringify((function(){try{return {exmc_dom:1,ok:true,result:(function(input,guard){" <>
      @document_guard <>
      body <>
      "})(JSON.parse(" <>
      encoded <>
      "),JSON.parse(" <>
      guard <>
      "))};}catch(e){return {exmc_dom:1,ok:false,error:String(e.message||e)};}})())"
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
           Enum.all?(fields, &valid_field?/1),
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
         :ok <- Composition.effect(:navigate_page, fn -> dispatch_navigation(page, previous, url) end) do
      same_document =
        previous != url and hd(String.split(previous, "#", parts: 2)) == hd(String.split(url, "#", parts: 2))

      poll(
        unpin(page),
        "return document.readyState==='complete' && (window.__exmc_navigation!==input.token || (input.same_document && location.href===input.url));",
        %{token: token, url: url, same_document: same_document},
        opts
      )
    end
  end

  defp dispatch_navigation(page, previous, url) when previous == url,
    do: dom_action(page, "location.reload();", %{})

  defp dispatch_navigation(page, _previous, url), do: dom_action(page, "location.href=input.url;", %{url: url})

  defp valid_field?({selector, value}) when is_binary(selector) and is_binary(value),
    do: String.trim(selector) != "" and not String.contains?(selector, <<0>>)

  defp valid_field?(_), do: false

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
    code = browser_code(page, body, params)

    Automation.query(
      "com.apple.Safari",
      @instance <>
        "guardInstance(input);" <>
        @execute_dom <>
        """
        var windows=app.windows(),w=null;
        for(var i=0;i<windows.length;i++){if(windows[i].id()===input.window_id){w=windows[i];break;}}
        if(!w)throw new Error('Safari window not found');
        var tabs=w.tabs();
        if(!tabs || tabs.length===0)throw new Error('Safari window has no tabs');
        if(input.owned && tabs.length!==1)throw new Error('Owned Safari window has additional tabs');
        var t=tabs[input.tab_index-1];if(!t)throw new Error('Tab not found');
        return runDOM(t);
        """,
      Map.put(target(page), :code, code),
      opts
    )
  end

  defp element,
    do:
      "var matches=document.querySelectorAll(input.selector);if(matches.length!==1)throw new Error('Missing or ambiguous element');var e=matches[0];"

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
      with {:ok, data} <-
             Automation.query(
               "com.apple.Safari",
               @instance <>
                 """
                 // A normal app query launches Safari when this explicit open requires it.
                 app.windows();var before=safariInstance();
                 app.documents.push(app.Document({url:input.url}));
                 guardInstance(before);var w=app.windows()[0];
                 return {window_id:w.id(),tab_index:1,url:input.url,owned:true,
                   application_pid:before.application_pid,application_started_at:before.application_started_at};
                 """,
               %{url: url}
             ),
           true <-
             is_integer(data[:window_id]) and is_integer(data[:application_pid]) and
               is_number(data[:application_started_at]) do
        {:ok, struct!(Page, data)}
      else
        {:error, _} = error -> error
        _ -> {:error, Error.execution_error("Safari did not return a bound window identity", outcome: :unknown)}
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
