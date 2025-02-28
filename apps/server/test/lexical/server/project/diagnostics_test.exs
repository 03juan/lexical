defmodule Lexical.Server.Project.DiagnosticsTest do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.Protocol.Notifications.PublishDiagnostics
  alias Lexical.Server.Project
  alias Lexical.Server.Transport
  alias Mix.Task.Compiler

  use ExUnit.Case
  use Patch

  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures

  setup do
    project = project()

    {:ok, _} = start_supervised(Lexical.Document.Store)
    {:ok, _} = start_supervised({Project.Dispatch, project})
    {:ok, _} = start_supervised({Project.Diagnostics, project})

    {:ok, project: project}
  end

  def diagnostic(file_path, opts \\ []) do
    defaults = [
      file: Document.Path.ensure_path(file_path),
      severity: :error,
      message: "stuff broke",
      position: 1,
      compiler_name: "Elixir"
    ]

    values = Keyword.merge(defaults, opts)
    struct(Compiler.Diagnostic, values)
  end

  def with_patched_tranport(_) do
    test = self()

    patch(Transport, :write, fn message ->
      send(test, {:transport, message})
    end)

    :ok
  end

  defp open_file(project, contents) do
    uri = file_uri(project, "lib/project.ex")
    :ok = Document.Store.open(uri, contents, 0)
    {:ok, document} = Document.Store.fetch(uri)
    document
  end

  describe "clearing diagnostics on compile" do
    setup [:with_patched_tranport]

    test "it clears a file's diagnostics if it's not dirty", %{
      project: project
    } do
      document = open_file(project, "defmodule Foo")

      file_diagnostics_message =
        file_diagnostics(diagnostics: [diagnostic(document.uri)], uri: document.uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{}}

      Document.Store.get_and_update(document.uri, &Document.mark_clean/1)

      Project.Dispatch.broadcast(project, project_diagnostics(diagnostics: []))

      assert_receive {:transport, %PublishDiagnostics{diagnostics: nil}}
    end

    test "it clears a file's diagnostics if it has been closed", %{
      project: project
    } do
      document = open_file(project, "defmodule Foo")

      file_diagnostics_message =
        file_diagnostics(diagnostics: [diagnostic(document.uri)], uri: document.uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{}}, 500

      Document.Store.close(document.uri)
      Project.Dispatch.broadcast(project, project_diagnostics(diagnostics: []))

      assert_receive {:transport, %PublishDiagnostics{diagnostics: nil}}
    end

    test "it adds a diagnostic to the last line if they're out of bounds", %{project: project} do
      document = open_file(project, "defmodule Dummy do\n  .\nend\n")
      # only 3 lines in the file, but elixir compiler gives us a line number of 4
      diagnostic =
        diagnostic("lib/project.ex",
          position: {4, 1},
          message: "missing terminator: end (for \"do\" starting at line 1)"
        )

      file_diagnostics_message = file_diagnostics(diagnostics: [diagnostic], uri: document.uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{lsp: %{diagnostics: [diagnostic]}}}, 500

      assert %Compiler.Diagnostic{} = diagnostic
      assert diagnostic.position == {4, 1}
    end
  end
end
