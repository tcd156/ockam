defmodule Ockam.Examples.Session.PipeChannel do
  alias Ockam.Session.Routing.Pluggable, as: Session
  alias Ockam.Session.Spawner

  alias Ockam.Messaging.Delivery.ResendPipe
  alias Ockam.Messaging.PipeChannel

  def create_spawner() do
    spawner_options = [
      worker_mod: Session.Responder,
      worker_options: [
        worker_mod: PipeChannel.Simple,
        handshake: PipeChannel.Handshake,
        handshake_options: [
          sender_mod: ResendPipe.sender(),
          receiver_mod: ResendPipe.receiver(),
          sender_options: [confirm_timeout: 200]
        ]
      ]
    ]

    Spawner.create(spawner_options)
  end

  def create_responder() do
    responder_options = [
      worker_mod: PipeChannel.Simple,
      handshake: PipeChannel.Handshake,
      handshake_options: [
        sender_mod: ResendPipe.sender(),
        receiver_mod: ResendPipe.receiver(),
        sender_options: [confirm_timeout: 200]
      ]
    ]

    Session.Responder.create(responder_options)
  end

  def create_initiator(spawner_route) do
    Session.Initiator.create(
      init_route: spawner_route,
      worker_mod: PipeChannel.Simple,
      worker_options: [],
      handshake: PipeChannel.Handshake,
      handshake_options: [
        sender_mod: ResendPipe.sender(),
        receiver_mod: ResendPipe.receiver(),
        sender_options: [confirm_timeout: 200]
      ]
    )
  end

  def run_local() do
    {:ok, responder} = create_responder()

    {:ok, responder_inner} = Ockam.AsymmetricWorker.get_inner_address(responder)

    {:ok, initiator} = create_initiator([responder_inner])

    Session.Initiator.wait_for_session(initiator)

    Ockam.Node.register_address("me")

    Ockam.Router.route(%{
      onward_route: [initiator, "me"],
      return_route: ["me"],
      payload: "Hi me!"
    })

    :sys.get_state(Ockam.Node.whereis(initiator))
  end

  def run_local_with_spawner() do
    {:ok, spawner} = create_spawner()
    {:ok, initiator} = create_initiator([spawner])

    Session.Initiator.wait_for_session(initiator)

    Ockam.Node.register_address("me")

    Ockam.Router.route(%{
      onward_route: [initiator, "me"],
      return_route: ["me"],
      payload: "Hi me!"
    })

    :sys.get_state(Ockam.Node.whereis(initiator))
  end
end
