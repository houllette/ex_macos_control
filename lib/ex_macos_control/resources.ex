defmodule ExMacOSControl.Resources do
  @moduledoc false

  alias ExMacOSControl.Automation

  def list(bundle, collection, fields, params, opts) do
    with :ok <- Automation.options(opts, [:limit, :offset, :timeout, :max_output_bytes]),
         {:ok, paging} <- Automation.page(opts) do
      Automation.query(
        bundle,
        "return page(#{collection}()).map(function(o) { return #{object(fields)}; });",
        Map.merge(params, paging),
        Automation.execution_options(opts)
      )
    end
  end

  def get(bundle, collection, fields, id, params, opts) do
    with :ok <- Automation.required_string(id, "Object ID") do
      Automation.query(
        bundle,
        "var o = byId(#{collection}, input.id); return #{object(fields)};",
        Map.merge(params, %{id: id}),
        opts
      )
    end
  end

  def create(bundle, collection, constructor, schema, attrs, params, opts, after_code \\ "") do
    with {:ok, properties, dates} <- properties(attrs, schema) do
      Automation.query(
        bundle,
        """
        input.dates.forEach(function(key) { input.properties[key] = input.properties[key] === null ? null : new Date(input.properties[key]); });
        var o = app.#{constructor}(input.properties);
        #{collection}.push(o);
        #{after_code}
        return o.id();
        """,
        Map.merge(params, %{properties: properties, dates: dates}),
        opts
      )
    end
  end

  def update(bundle, collection, schema, id, attrs, params, opts, after_code \\ "") do
    with :ok <- Automation.required_string(id, "Object ID"),
         {:ok, properties, dates} <- properties(attrs, schema) do
      Automation.action(
        bundle,
        """
        var o = byId(#{collection}, input.id);
        Object.keys(input.properties).forEach(function(key) {
          var value = input.properties[key];
          o[key] = input.dates.indexOf(key) >= 0 && value !== null ? new Date(value) : value;
        });
        #{after_code}
        """,
        Map.merge(params, %{id: id, properties: properties, dates: dates}),
        opts
      )
    end
  end

  def delete(bundle, collection, id, params, opts, after_code \\ "") do
    with :ok <- Automation.required_string(id, "Object ID") do
      Automation.action(
        bundle,
        "app.delete(byId(#{collection}, input.id)); #{after_code}",
        Map.merge(params, %{id: id}),
        opts
      )
    end
  end

  def properties(attrs, schema) do
    with :ok <- Automation.options(attrs, Keyword.keys(schema)) do
      Enum.reduce_while(attrs, {:ok, %{}, []}, fn {key, value}, accumulator ->
        reduce_property(Keyword.fetch!(schema, key), value, accumulator)
      end)
    end
  end

  defp reduce_property({name, type}, raw, {:ok, properties, dates}) do
    case value(raw, type) do
      {:ok, converted} ->
        {:cont, {:ok, Map.put(properties, name, converted), if(type == :date, do: [name | dates], else: dates)}}

      error ->
        {:halt, error}
    end
  end

  defp value(value, :string) when is_binary(value), do: {:ok, value}
  defp value(value, :boolean) when is_boolean(value), do: {:ok, value}
  defp value(value, :integer) when is_integer(value), do: {:ok, value}
  defp value(value, :date), do: Automation.date(value)
  defp value(_value, _type), do: Automation.invalid("Invalid property value")

  defp object(fields),
    do: "{" <> Enum.map_join(fields, ",", fn {key, expr} -> Jason.encode!(key) <> ":" <> expr end) <> "}"
end
