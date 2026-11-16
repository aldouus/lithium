ExUnit.start()

defmodule Lithium.TestData do
  def isolate! do
    root = Path.join(System.tmp_dir!(), "lithium-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    previous = Application.get_env(:lithium, :data_root)
    Application.put_env(:lithium, :data_root, root)

    ExUnit.Callbacks.on_exit(fn ->
      if previous do
        Application.put_env(:lithium, :data_root, previous)
      else
        Application.delete_env(:lithium, :data_root)
      end

      File.rm_rf(root)
    end)

    root
  end
end
