defmodule Ockam.Session.Routing.Pluggable do
  @moduledoc """
  Simple routing session logic.
  Initiator sends an empty message to the spawner on start
  and waits for a response from the responder.
  """

  @doc """
  Shared function for data stage of the session

  State MUST have :data_state and :worker_mod keys
  """
  @spec handle_data_message(Ockam.Message.t(), %{data_state: any(), worker_mod: atom()}) :: %{
          data_state: any()
        }
  def handle_data_message(message, state) do
    data_state = Map.fetch!(state, :data_state)
    worker_mod = Map.fetch!(state, :worker_mod)

    case worker_mod.handle_message(message, data_state) do
      {:ok, new_data_state} ->
        {:ok, Map.put(state, :data_state, new_data_state)}

      {:error, error} ->
        {:error, {:data_error, error}}

      {:stop, reason, new_data_state} ->
        {:stop, reason, Map.put(state, :data_state, new_data_state)}
    end
  end
end

## TODO asymmetric worker for session
## The main issue is that if internal worker is asymmetric
## it might override the internal address

## First option: non-buffering session, messages are dropped if the session is not ready yet
defmodule Ockam.Session.Routing.Pluggable.Initiator do
  @moduledoc """
  Simple routing session initiator

  Upon starting sends a message with empty payload to the responder and
  waits for a response in the :handshake stage

  After receiving a handshake response, starts the data worker on the same process and
  moves to the :data stage

  Data worker initial state is the same as the session worker initial state
  Data worker is started with `worker_options` merged with
  handshake response message return route as `:route`
  and handshake payload as `:handshake_data`

  In the :data stage processes all messages with the data worker module

  Options:

  `worker_mod` - data worker module
  `worker_options` - data worker options
  `init_route` - route to responder (or spawner)
  """
  use Ockam.AsymmetricWorker

  alias Ockam.Message
  alias Ockam.Router

  alias Ockam.Session.Routing.Pluggable, as: RoutingSession

  require Logger

  def get_stage(worker) do
    Ockam.Worker.call(worker, :get_stage)
  end

  def wait_for_session(worker, interval \\ 100, timeout \\ 5000)

  def wait_for_session(_worker, _interval, expire) when expire < 0 do
    {:error, :timeout}
  end

  def wait_for_session(worker, interval, timeout) do
    case get_stage(worker) do
      :data ->
        :ok

      :handshake ->
        :timer.sleep(interval)
        wait_for_session(worker, interval, timeout - interval)
    end
  end

  @impl true
  def inner_setup(options, state) do
    init_route = Keyword.fetch!(options, :init_route)

    base_state = state
    ## rename to data_mod
    worker_mod = Keyword.fetch!(options, :worker_mod)
    worker_options = Keyword.get(options, :worker_options, [])

    handshake = Keyword.get(options, :handshake, Ockam.Session.Handshake.Default)
    handshake_options = Keyword.get(options, :handshake_options, [])

    state =
      Map.merge(state, %{
        init_route: init_route,
        worker_mod: worker_mod,
        worker_options: worker_options,
        base_state: base_state,
        handshake: handshake,
        handshake_options: handshake_options
      })

    state = send_handshake(handshake_options, state)

    {:ok, Map.put(state, :stage, :handshake)}
  end

  def send_handshake(handshake_options, state) do
    handshake = Map.fetch!(state, :handshake)
    {:ok, handshake_msg, state} = handshake.init(handshake_options, state)
    Ockam.Router.route(handshake_msg)
    state
  end

  @impl true
  def handle_call(:get_stage, _from, state) do
    {:reply, Map.get(state, :stage), state}
  end

  @impl true
  def handle_message(message, %{stage: :handshake} = state) do
    case message_type(message, state) do
      :inner ->
        handle_handshake_message(message, state)

      _ ->
        Logger.info("Ignoring non-inner message in handshake stage: #{inspect(message)}")
        {:ok, state}
    end
  end

  def handle_message(message, %{stage: :data} = state) do
    RoutingSession.handle_data_message(message, state)
  end

  def handle_handshake_message(message, state) do
    handshake = Map.fetch!(state, :handshake)
    handshake_options = Map.fetch!(state, :handshake_options)

    case handshake.handle_initiator(handshake_options, message, state) do
      {:ok, options, state} ->
        switch_to_data_stage(options, state)

      {:error, err} ->
        ## TODO: error handling in Ockam.Worker
        {:error, err}
    end
  end

  def switch_to_data_stage(handshake_options, state) do
    base_state = Map.get(state, :base_state)
    worker_mod = Map.fetch!(state, :worker_mod)
    worker_options = Map.fetch!(state, :worker_options)

    options = Keyword.merge(worker_options, handshake_options)

    case worker_mod.setup(options, base_state) do
      {:ok, data_state} ->
        {:ok, Map.merge(state, %{data_state: data_state, stage: :data})}

      {:error, err} ->
        {:stop, {:cannot_start_data_worker, {:error, err}, options, base_state}, state}
    end
  end
end

## Single handshake responder
defmodule Ockam.Session.Routing.Pluggable.Responder do
  @moduledoc """
  Simple routing session responder

  Started with :initiator_route and :handshake_data
  On start initializes the data worker and if successful sends a handshake response

  Data worker is started with `:initiator_route` as `:route`
  and `:handshake_data` as `:handshake_data` options

  All messages are processed with the data worker module
  """
  use Ockam.AsymmetricWorker

  alias Ockam.Message
  alias Ockam.Session.Routing.Pluggable, as: RoutingSession

  require Logger

  @impl true
  def inner_setup(options, state) do
    base_state = state
    worker_mod = Keyword.fetch!(options, :worker_mod)
    worker_options = Keyword.get(options, :worker_options, [])

    handshake = Keyword.get(options, :handshake, Ockam.Session.Handshake.Default)
    handshake_options = Keyword.get(options, :handshake_options, [])

    state =
      Map.merge(state, %{
        worker_mod: worker_mod,
        worker_options: worker_options,
        base_state: base_state,
        stage: :handshake,
        handshake: handshake,
        handshake_options: handshake_options
      })

    case Keyword.get(options, :init_message) do
      nil ->
        ## Stay in the handshake stage, wait for init message
        {:ok, state}

      %{payload: _} = message ->
        handle_handshake_message(message, state)
    end
  end

  @impl true
  def handle_message(message, %{stage: :handshake} = state) do
    case message_type(message, state) do
      :inner ->
        handle_handshake_message(message, state)

      _ ->
        ## TODO: buffering option?
        Logger.debug("Ignoring non-inner message #{inspect(message)} in handshake stage")
        {:ok, state}
    end
  end

  def handle_message(message, %{stage: :data} = state) do
    RoutingSession.handle_data_message(message, state)
  end

  def handle_handshake_message(message, state) do
    handshake = Map.fetch!(state, :handshake)
    handshake_options = Map.fetch!(state, :handshake_options)

    case handshake.handle_responder(handshake_options, message, state) do
      {:ok, response, options, state} ->
        switch_to_data_stage(response, options, state)

      {:error, err} ->
        {:error, err}
    end
  end

  defp switch_to_data_stage(response, handshake_options, state) do
    worker_mod = Map.fetch!(state, :worker_mod)
    worker_options = Map.fetch!(state, :worker_options)
    base_state = Map.fetch!(state, :base_state)

    options = Keyword.merge(worker_options, handshake_options)

    case worker_mod.setup(options, base_state) do
      {:ok, data_state} ->
        send_handshake_response(response)
        ## TODO: use data_state instead of state futher on?
        {:ok, Map.merge(state, %{data_state: data_state, stage: :data})}

      {:error, err} ->
        Logger.error(
          "Error starting responder data module: #{worker_mod}, reason: #{inspect(err)}"
        )

        ## TODO: should we send handshake error?
        {:error, err}
    end
  end

  def send_handshake_response(response) do
    Ockam.Router.route(response)
  end
end

defmodule Ockam.Session.Handshake.Default do
  alias Ockam.Message

  @behaviour Ockam.Session.Handshake

  @spec init(Keyword.t(), map()) :: {:ok, Message.t(), map()}
  def init(_options, state) do
    init_route = Map.fetch!(state, :init_route)

    {:ok,
     %{
       onward_route: init_route,
       return_route: [state.inner_address],
       payload: ""
     }, state}
  end

  def handle_initiator(_options, message, state) do
    data_route = Message.return_route(message)
    handshake_data = Message.payload(message)
    ## TODO: use special data types?
    case handshake_data == "" do
      true ->
        {:ok, [route: data_route], state}

      false ->
        {:error, {:invalid_handshake_message, message}}
    end
  end

  def handle_responder(_options, message, state) do
    initiator_route = Message.return_route(message)
    handshake_data = Message.payload(message)

    response = %{
      onward_route: initiator_route,
      return_route: [state.inner_address],
      payload: handshake_data
    }

    {:ok, response, [route: initiator_route], state}
  end
end
