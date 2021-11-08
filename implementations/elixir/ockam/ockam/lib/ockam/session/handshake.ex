defmodule Ockam.Session.Handshake do
  @type message() :: Ockam.Message.t()

  @callback init(options :: Keyword.t(), state :: map()) ::
              {:ok, message(), state :: map()} | {:error, any()}

  ## TODO: non-terminating handshake support
  ## TODO: error result
  ## TODO: explicit structure fields in result
  @callback handle_initiator(
              handshake_options :: Keyword.t(),
              message :: message(),
              state :: map()
            ) ::
              {:ok, worker_options :: Keyword.t(), state :: map()}
  @callback handle_responder(
              handshake_options :: Keyword.t(),
              message :: message(),
              state :: map()
            ) ::
              {:ok, response :: message(), worker_options :: Keyword.t(), state :: map()}
end
