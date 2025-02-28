defmodule Lexical.RemoteControl.CompileTracer do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.ModuleMappings

  import RemoteControl.Api.Messages

  def trace({:on_module, module_binary, filename}, %Macro.Env{} = env) do
    message = extract_module_updated(env.module, module_binary, filename)
    ModuleMappings.update(env.module, env.file)
    RemoteControl.notify_listener(message)
    maybe_report_progress(env.file)

    :ok
  end

  def trace(_event, _env) do
    :ok
  end

  defp maybe_report_progress(file) do
    if Path.extname(file) == ".ex" do
      file
      |> progress_message()
      |> RemoteControl.notify_listener()
    end
  end

  defp progress_message(file) do
    relative_path = Path.relative_to_cwd(file)

    label =
      if String.starts_with?(relative_path, "deps") do
        "mix deps.compile"
      else
        "mix compile"
      end

    project_progress(label: label, message: relative_path)
  end

  def extract_module_updated(module, module_binary, filename) do
    unless Code.ensure_loaded?(module) do
      erlang_filename =
        filename
        |> ensure_filename()
        |> String.to_charlist()

      :code.load_binary(module, erlang_filename, module_binary)
    end

    functions = module.__info__(:functions)
    macros = module.__info__(:macros)

    struct =
      if function_exported?(module, :__struct__, 0) do
        module.__struct__()
        |> Map.from_struct()
        |> Enum.map(fn {k, v} ->
          %{field: k, required?: !is_nil(v)}
        end)
      end

    module_updated(
      name: module,
      functions: functions,
      macros: macros,
      struct: struct
    )
  end

  defp ensure_filename(:none) do
    unique = System.unique_integer([:positive, :monotonic])
    Path.join(System.tmp_dir(), "file-#{unique}.ex")
  end

  defp ensure_filename(filename) when is_binary(filename) do
    filename
  end
end
