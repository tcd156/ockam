defmodule Ockam.Examples.Session.SimpleRouting do
  @moduledoc """
  Simple routing session example

  Creates a spawner for sessions and establishes a routing session
  with a simple forwarding data worker.

  Usage:
  ```
  {:ok, spawner} = Ockam.Examples.Session.SimpleRouting.create_spawner() # create a responder spawner

  {:ok, initiator} = Ockam.Examples.Session.SimpleRouting.create_initiator([spawner]) # creates an initiator using a route to spawner

  Ockam.Examples.Session.SimpleRouting.run_local() # creates local spawner and initiator and sends a message through
  ```
  """

  alias Ockam.Session.Routing.Pluggable, as: Routing
  alias Ockam.Session.Spawner

  alias Ockam.Session.ForwardingDataWorker, as: DataWorker

  def create_spawner() do
    responder_options = [
      worker_mod: DataWorker,
      worker_options: [messages: [:message_from_options]]
    ]

    spawner_options = [
      worker_mod: Routing.Responder,
      worker_options: responder_options
    ]

    Spawner.create(spawner_options)
  end

  def create_responder() do
    responder_options = [
      worker_mod: DataWorker,
      worker_options: [messages: [:message_from_options]]
    ]

    Routing.Responder.create(responder_options)
  end

  def create_initiator(spawner_route) do
    Routing.Initiator.create(
      worker_mod: DataWorker,
      worker_options: [messages: [:message_from_options_initiator]],
      init_route: spawner_route
    )
  end

  def run_local() do
    {:ok, responder} = create_responder()

    {:ok, responder_inner} = Ockam.AsymmetricWorker.get_inner_address(responder)

    {:ok, initiator} = create_initiator([responder_inner])

    Routing.Initiator.wait_for_session(initiator)

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

    Routing.Initiator.wait_for_session(initiator)

    Ockam.Node.register_address("me")

    Ockam.Router.route(%{
      onward_route: [initiator, "me"],
      return_route: ["me"],
      payload: "Hi me!"
    })

    :sys.get_state(Ockam.Node.whereis(initiator))
  end
end
