defmodule Ockam.Messaging.PipeChannel.Handshake do
  alias Ockam.Messaging.PipeChannel.Metadata
  alias Ockam.Message

  @behaviour Ockam.Session.Handshake

  @spec init(Keyword.t(), map()) :: {:ok, Message.t(), map()}
  def init(handshake_options, state) do
    spawner_route = Map.fetch!(state, :init_route)

    ## TODO: use pipe_mod instead of sender_mod and receiver_mod
    receiver_mod = Keyword.fetch!(handshake_options, :receiver_mod)
    receiver_options = Keyword.get(handshake_options, :receiver_options, [])

    {:ok, receiver} = receiver_mod.create(receiver_options)

    handshake_msg = %{
      onward_route: spawner_route,
      return_route: [receiver],
      payload:
        Metadata.encode(%Metadata{
          channel_route: [state.inner_address],
          receiver_route: [receiver]
        })
    }

    {:ok, handshake_msg, Map.put(state, :receiver, receiver)}
  end

  def handle_initiator(handshake_options, message, state) do
    payload = Message.payload(message)

    %Metadata{
      channel_route: channel_route,
      receiver_route: remote_receiver_route
    } = Metadata.decode(payload)

    spawner_route = Map.fetch!(state, :init_route)

    receiver_route = make_receiver_route(spawner_route, remote_receiver_route)

    sender_mod = Keyword.fetch!(handshake_options, :sender_mod)
    sender_options = Keyword.get(handshake_options, :sender_options, [])

    {:ok, sender} =
      sender_mod.create(Keyword.merge([receiver_route: receiver_route], sender_options))

    ## TODO: replace sender and channel_route with a single route
    {:ok, [sender: sender, channel_route: channel_route], state}
  end

  def handle_responder(handshake_options, message, state) do
    payload = Message.payload(message)

    ## We ignore receiver route here and rely on return route tracing
    %Metadata{channel_route: channel_route} = Metadata.decode(payload)

    receiver_route = Message.return_route(message)

    sender_options = Keyword.get(handshake_options, :sender_options, [])
    receiver_options = Keyword.get(handshake_options, :receiver_options, [])

    sender_mod = Keyword.fetch!(handshake_options, :sender_mod)
    receiver_mod = Keyword.fetch!(handshake_options, :receiver_mod)

    {:ok, receiver} = receiver_mod.create(receiver_options)

    {:ok, sender} =
      sender_mod.create(Keyword.merge([receiver_route: receiver_route], sender_options))

    response = %{
      onward_route: [sender | channel_route],
      return_route: [state.inner_address],
      payload:
        Metadata.encode(%Metadata{
          channel_route: [state.inner_address],
          receiver_route: [receiver]
        })
    }

    {:ok, response, [sender: sender, channel_route: channel_route], state}
  end

  defp make_receiver_route(spawner_route, remote_receiver_route) do
    Enum.take(spawner_route, Enum.count(spawner_route) - 1) ++ remote_receiver_route
  end
end
