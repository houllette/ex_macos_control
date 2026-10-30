defmodule ExMacOSControl.ImageEvents do
  @moduledoc "Image metadata and file transformations through Image Events. Output paths must be new files."
  alias ExMacOSControl.Automation
  @app "com.apple.imageevents"

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
end
