defmodule ExMacOSControl.ImageEvents do
  @moduledoc "Image metadata and file transformations through Image Events. Output paths must be new files."
  alias ExMacOSControl.{Automation, Composition, Validation}
  @app "com.apple.imageevents"
  @extensions %{"PNG" => ".png", "JPEG" => ".jpg", "TIFF" => ".tiff", "BMP" => ".bmp", "PSD" => ".psd"}

  def info(path, opts \\ []) do
    with :ok <- input(path) do
      Automation.query(
        @app,
        "var image=app.open(Path(input.path)); try {return {name:image.name(),dimensions:image.dimensions(),resolution:image.resolution(),color_space:image.colorSpace(),bit_depth:image.bitDepth(),file_type:image.fileType()};} finally {app.close(image);}",
        %{path: Path.expand(path)},
        opts
      )
    end
  end

  def scale(path, destination, size, opts \\ []) when is_integer(size) and size > 0,
    do: transform(path, destination, "app.scale(image,{toSize:input.value});", size, opts)

  def rotate(path, destination, angle, opts \\ []) when is_number(angle),
    do: transform(path, destination, "app.rotate(image,{toAngle:input.value});", angle, opts)

  def crop(path, destination, [width, height], opts \\ [])
      when is_integer(width) and is_integer(height) and width > 0 and height > 0,
      do: transform(path, destination, "app.crop(image,{toDimensions:input.value});", [width, height], opts)

  def convert(path, destination, format, opts \\ []),
    do: transform(path, destination, "", nil, Keyword.put(opts, :format, format))

  def flip(path, destination, direction, opts \\ []) when direction in [:horizontal, :vertical] do
    transform(path, destination, "app.flip(image,{#{direction}:true});", nil, opts)
  end

  @doc """
  Applies ordered scale/rotate/crop/flip steps while opening and saving an image
  only once. Steps are keyword pairs, for example `[scale: 800, rotate: 90]`.
  Format defaults to PNG; PNG, JPEG, TIFF, BMP and PSD are supported here.
  Requires a new destination in an existing directory. Original files remain.
  """
  def process(path, destination, steps, opts \\ []) do
    with :ok <- input(path),
         :ok <- validate_steps(steps),
         :ok <- process_options(opts),
         :ok <- Automation.required_string(destination, "Output path"),
         true <- File.dir?(Path.dirname(destination)) and File.lstat(destination) == {:error, :enoent} do
      Automation.action(
        @app,
        """
        var image=app.open(Path(input.path));
        try {
          input.steps.forEach(function(step){
            switch(step[0]){
              case 'scale':app.scale(image,{toSize:step[1]});break;
              case 'rotate':app.rotate(image,{toAngle:step[1]});break;
              case 'crop':app.crop(image,{toDimensions:step[1]});break;
              case 'flip':if(step[1]==='horizontal')app.flip(image,{horizontal:true});else app.flip(image,{vertical:true});break;
            }
          });
          app.save(image,{in:input.destination,as:input.format});
        } finally {app.close(image);}
        """,
        %{
          path: Path.expand(path),
          destination: Path.expand(destination),
          steps: Enum.map(steps, fn {key, value} -> [key, value] end),
          format: Keyword.get(opts, :format, "PNG")
        },
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Image output must be a new file in an existing directory")
    end
  end

  @doc "Processes a batch into a directory, validating all inputs and output collisions before dispatch."
  def process_many(paths, destination, steps, opts \\ []) do
    with :ok <- Validation.items(paths),
         :ok <- Validation.all(paths, &input/1),
         :ok <- validate_steps(steps),
         :ok <- process_options(opts),
         true <- is_binary(destination) and File.dir?(destination),
         extension = Map.fetch!(@extensions, Keyword.get(opts, :format, "PNG")),
         outputs = Enum.map(paths, &Path.join(Path.expand(destination), Path.rootname(Path.basename(&1)) <> extension)),
         true <- Enum.uniq(outputs) == outputs and Enum.all?(outputs, &(File.lstat(&1) == {:error, :enoent})) do
      Composition.run(
        fn -> do_process_many(paths, outputs, steps, opts) end,
        Keyword.take(opts, [:timeout, :max_output_bytes])
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Image destination must exist and all output names must be distinct and new")
    end
  end

  defp process_options(opts) do
    with :ok <- Automation.options(opts, [:format, :timeout, :max_output_bytes]),
         true <- Map.has_key?(@extensions, Keyword.get(opts, :format, "PNG")) do
      :ok
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Unsupported image output format")
    end
  end

  defp validate_steps(steps) do
    if is_list(steps) and length(steps) <= 100 and Keyword.keyword?(steps) and Enum.all?(steps, &valid_step?/1),
      do: :ok,
      else: Automation.invalid("Steps must contain valid scale, rotate, crop or flip operations (at most 100)")
  end

  defp valid_step?({:scale, value}), do: is_integer(value) and value > 0
  defp valid_step?({:rotate, value}), do: is_number(value)
  defp valid_step?({:crop, [width, height]}), do: is_integer(width) and width > 0 and is_integer(height) and height > 0
  defp valid_step?({:flip, value}), do: value in [:horizontal, :vertical]
  defp valid_step?(_), do: false

  defp transform(path, destination, operation, value, opts) do
    with :ok <- input(path),
         :ok <- Automation.required_string(destination, "Output path"),
         :ok <- Automation.options(opts, [:format, :timeout, :max_output_bytes]),
         true <-
           Keyword.get(opts, :format, "PNG") in [
             "PNG",
             "JPEG",
             "JPEG2",
             "TIFF",
             "BMP",
             "PSD",
             "PICT",
             "QuickTime Image"
           ],
         false <- File.exists?(destination) do
      Automation.action(
        @app,
        "var image=app.open(Path(input.path)); try {#{operation} app.save(image,{in:input.destination,as:input.format});} finally {app.close(image);}",
        %{
          path: Path.expand(path),
          destination: Path.expand(destination),
          value: value,
          format: Keyword.get(opts, :format, "PNG")
        },
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Invalid image format or output path already exists")
    end
  end

  defp input(path) do
    if is_binary(path) and File.regular?(path), do: :ok, else: Automation.invalid("Image file does not exist")
  end

  defp do_process_many(paths, outputs, steps, opts) do
    Composition.map(Enum.zip(paths, outputs), :process_image, fn {path, output} ->
      with :ok <- process(path, output, steps, Keyword.take(opts, [:format])), do: {:ok, output}
    end)
  end
end
