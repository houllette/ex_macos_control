defmodule ExMacOSControl.Contacts do
  @moduledoc "Contacts and groups addressed by ID. Changes are explicitly saved through Contacts."
  alias ExMacOSControl.{Automation, Resources}
  @app "com.apple.AddressBook"
  @fields [
    id: "o.id()",
    name: "o.name()",
    first_name: "o.firstName()",
    last_name: "o.lastName()",
    organization: "o.organization()",
    note: "o.note()",
    vcard: "o.vcard()"
  ]
  @schema [
    first_name: {"firstName", :string},
    last_name: {"lastName", :string},
    organization: {"organization", :string},
    note: {"note", :string},
    company: {"company", :boolean}
  ]
  @address_schema [
    label: {"label", :string},
    street: {"street", :string},
    city: {"city", :string},
    state: {"state", :string},
    postal_code: {"zip", :string},
    country: {"country", :string},
    country_code: {"countryCode", :string}
  ]
  def list_contacts(opts \\ []), do: Resources.list(@app, "app.people", [id: "o.id()", name: "o.name()"], %{}, opts)

  def get_contact(id, opts \\ []),
    do:
      Resources.get(
        @app,
        "app.people",
        @fields ++
          [
            emails: "o.emails().map(function(e){return {id:e.id(),label:e.label(),value:e.value()};})",
            phones: "o.phones().map(function(p){return {id:p.id(),label:p.label(),value:p.value()};})",
            addresses:
              "o.addresses().map(function(a){return {id:a.id(),label:a.label(),street:a.street(),city:a.city(),state:a.state(),postal_code:a.zip(),country:a.country(),country_code:a.countryCode()};})"
          ],
        id,
        %{},
        opts
      )

  def list_groups(opts \\ []), do: Resources.list(@app, "app.groups", [id: "o.id()", name: "o.name()"], %{}, opts)

  def create_contact(attrs, opts \\ []) do
    with :ok <- Automation.options(attrs, Keyword.keys(@schema)),
         true <-
           Enum.any?([:first_name, :last_name, :organization], &(is_binary(attrs[&1]) and String.trim(attrs[&1]) != "")) do
      Resources.create(@app, "app.people", "Person", @schema, attrs, %{}, opts, "app.save();")
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("A contact needs a name or organization")
    end
  end

  def update_contact(id, attrs, opts \\ []),
    do: Resources.update(@app, "app.people", @schema, id, attrs, %{}, opts, "app.save();")

  def delete_contact(id, opts \\ []), do: Resources.delete(@app, "app.people", id, %{}, opts, "app.save();")

  def create_group(name, opts \\ []) do
    with :ok <- Automation.required_string(name, "Group name") do
      Resources.create(@app, "app.groups", "Group", [name: {"name", :string}], [name: name], %{}, opts, "app.save();")
    end
  end

  def rename_group(id, name, opts \\ []) do
    with :ok <- Automation.required_string(name, "Group name") do
      Resources.update(@app, "app.groups", [name: {"name", :string}], id, [name: name], %{}, opts, "app.save();")
    end
  end

  def delete_group(id, opts \\ []), do: Resources.delete(@app, "app.groups", id, %{}, opts, "app.save();")

  def selection(opts \\ []),
    do: Automation.query(@app, "return app.selection().map(function(o){return {id:o.id(),name:o.name()};});", %{}, opts)

  def add_address(id, attrs, opts \\ []) do
    with :ok <- Automation.required_string(id, "Contact ID"),
         {:ok, properties, _} <- Resources.properties(attrs, @address_schema),
         true <- map_size(properties) > 0 do
      Automation.action(
        @app,
        "byId(app.people,input.id).addresses.push(app.Address(input.properties));app.save();",
        %{id: id, properties: properties},
        opts
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Address needs at least one field")
    end
  end

  def add_to_group(id, group_id, opts \\ []),
    do:
      Automation.action(
        @app,
        "app.add(byId(app.people,input.id),{to:byId(app.groups,input.group_id)}); app.save();",
        %{id: id, group_id: group_id},
        opts
      )

  def remove_from_group(id, group_id, opts \\ []),
    do:
      Automation.action(
        @app,
        "app.remove(byId(app.people,input.id),{from:byId(app.groups,input.group_id)}); app.save();",
        %{id: id, group_id: group_id},
        opts
      )

  def add_email(id, value, label \\ "work", opts \\ []), do: add_value(id, value, label, "Email", "emails", opts)
  def add_phone(id, value, label \\ "work", opts \\ []), do: add_value(id, value, label, "Phone", "phones", opts)

  defp add_value(id, value, label, type, collection, opts) do
    with :ok <- Automation.required_string(id, "Contact ID"),
         :ok <- Automation.required_string(value, "Contact value"),
         :ok <- Automation.required_string(label, "Contact label") do
      Automation.action(
        @app,
        "var o=byId(app.people,input.id); o.#{collection}.push(app.#{type}({value:input.value,label:input.label})); app.save();",
        %{id: id, value: value, label: label},
        opts
      )
    end
  end
end
