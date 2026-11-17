defmodule Lithium.Web.Auth do
  use Guardian, otp_app: :lithium

  def subject_for_token(%Lithium.Accounts.User{id: id}, _claims) when is_integer(id) do
    {:ok, Integer.to_string(id)}
  end

  def subject_for_token(%{email: email}, _claims) when is_binary(email) do
    {:ok, email}
  end

  def subject_for_token(_resource, _claims), do: {:error, :invalid_resource}

  def resource_from_claims(%{"sub" => id, "typ" => "access"}) do
    case Integer.parse(id) do
      {int, ""} ->
        case Lithium.Accounts.get_user(int) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      _ ->
        {:error, :not_found}
    end
  end

  def resource_from_claims(_claims), do: {:error, :not_found}
end
