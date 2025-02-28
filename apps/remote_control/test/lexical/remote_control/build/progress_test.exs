defmodule Lexical.RemoteControl.Build.ProgressTest do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build.Progress

  import Lexical.RemoteControl.Api.Messages

  use ExUnit.Case
  use Patch
  use Progress

  setup do
    test_pid = self()
    patch(RemoteControl, :notify_listener, fn msg -> send(test_pid, msg) end)
    :ok
  end

  test "it should send begin/complete event and return the result" do
    result = with_progress "foo", fn -> :ok end

    assert result == :ok
    assert_received project_progress(label: "mix foo", stage: :begin)
    assert_received project_progress(label: "mix foo", stage: :complete)
  end

  test "it should send begin/complete event even there is an exception" do
    assert_raise(Mix.Error, fn ->
      with_progress "compile", fn -> raise Mix.Error, "can't compile" end
    end)

    assert_received project_progress(label: "mix compile", stage: :begin)
    assert_received project_progress(label: "mix compile", stage: :complete)
  end
end
