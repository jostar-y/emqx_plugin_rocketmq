-module(emqx_plugin_rocketmq_producer).

-behaviour(emqx_resource).

-include_lib("emqx_resource/include/emqx_resource.hrl").
-include_lib("emqx/include/logger.hrl").
-include("emqx_plugin_rocketmq.hrl").

-export([
    query_mode/1
    , callback_mode/0
    , on_start/2
    , on_get_status/2
    , on_stop/2
    , on_query_async/4
]).

query_mode(_) ->
    simple_async_internal_buffer.

callback_mode() ->
    async_if_possible.

on_start(
    InstId,
    #{
        connection := Connection,
        producer := Producer
    }
) ->
    #{
        bootstrap_hosts := Hosts0,
        client_id := ClientId0,
        access_key := AccessKey,
        secret_key := SecretKey
    } = Connection,
    ClientId = emqx_plugin_rocketmq_util:client_id(ClientId0),
    Hosts = emqx_plugin_rocketmq_util:hosts(Hosts0),
    AclInfo = emqx_plugin_rocketmq_util:acl_info(AccessKey, SecretKey),

    #{
        send_buffer := SendBuff,
        refresh_interval := RefreshInterval
    } = Producer,
    ProducerOpts = #{
        tcp_opts => [{sndbuf, SendBuff}],
        ref_topic_route_interval => RefreshInterval,
        acl_info => emqx_secret:wrap(AclInfo)
    },

    State = #{
        client_id => ClientId,
        producers_opts => ProducerOpts
    },

    case rocketmq:ensure_supervised_client(ClientId, Hosts, #{acl_info => AclInfo}) of
        {ok, _} ->
            {ok, State};
        {error, Reason} ->
            ?SLOG(error, #{
                msg => "emqx_plugin_rocketmq_producer on_start failed",
                instId => InstId,
                reason => Reason
            }),
            {error, Reason}
    end.

on_get_status(
    _InstId,
    #{client_id := ClientId}
) ->
    case rocketmq_client_sup:find_client(ClientId) of
        {ok, Pid} ->
            status_result(rocketmq_client:get_status(Pid));
        _ ->
            ?status_connecting
    end.

on_stop(_InstId, #{client_id := ClientId}) ->
    ?SLOG(info, #{
        msg => "rocketmq_client_on_stop",
        client_id => ClientId
    }),
    Producers = persistent_term:get({?EMQX_PLUGIN_ROCKETMQ_APP, ?EMQX_PLUGIN_ROCKETMQ_PRODUCERS}, []),
    lists:foreach(
        fun
            ({_, TProducers}) ->
                deallocate_producers(ClientId, TProducers);
            (TProducers) ->
                ?SLOG(error, #{
                    msg => "bad_producers",
                    producers => TProducers
                }),
                ok
        end, Producers),
    deallocate_client(ClientId),
    persistent_term:erase({?EMQX_PLUGIN_ROCKETMQ_APP, ?EMQX_PLUGIN_ROCKETMQ_PRODUCERS}),
    ok.

on_query_async(
    InstId,
    {Querys, Context},
    _,
    #{
        client_id := ClientId,
        producers_opts := ProducerOpts
    }
) ->
    try
        send_msg(Querys, Context, ClientId, ProducerOpts)
    catch
        Error:Reason :Stack ->
            ?SLOG(error, #{
                msg => "emqx_plugin_rocketmq_producer on_query_async error",
                error => Error,
                instId => InstId,
                reason => Reason,
                stack => Stack
            }),
            {error, {Error, Reason}}
    end.

%%%===================================================================
%%% External functions
%%%===================================================================

status_result(true) -> ?status_connected;
status_result(_) -> ?status_connecting.

deallocate_client(ClientId) ->
    _ = with_log_at_error(
        fun() -> ok = rocketmq:stop_and_delete_supervised_client(ClientId) end,
        #{
            msg => "failed_to_delete_rocketmq_client",
            client_id => ClientId
        }
    ),
    ok.

deallocate_producers(ClientId, Producers) ->
    _ = with_log_at_error(
        fun() -> _ = rocketmq:stop_and_delete_supervised_producers(Producers) end,
        #{
            msg => "failed_to_delete_rocketmq_producer",
            client_id => ClientId
        }
    ).

with_log_at_error(Fun, Log) ->
    try
        Fun()
    catch
        C:E ->
            ?SLOG(error, Log#{
                exception => C,
                reason => E
            })
    end.

send_msg([], _, _, _) ->
    ok;
send_msg([{RocketmqTopic, Tag, Msg} | T], Context, ClientId, ProducerOpts) ->
    Producers = get_producers(RocketmqTopic, ClientId, ProducerOpts),
    do_send_msg(Producers, {Msg, Context#{tag => Tag}}),
    send_msg(T, Context, ClientId, ProducerOpts).

do_send_msg(Producers, Data) ->
    rocketmq:send(Producers, Data).

get_producers(Topic, ClientId, ProducerOpts) ->
    ProducersL = persistent_term:get({?EMQX_PLUGIN_ROCKETMQ_APP, ?EMQX_PLUGIN_ROCKETMQ_PRODUCERS}, []),
    case lists:keyfind(Topic, 1, ProducersL) of
        {_, Producers} ->
            Producers;
        _ ->
            WorkersTab = emqx_plugin_rocketmq_util:workers_tab(Topic),
            ProducerGroup = iolist_to_binary([atom_to_list(ClientId), "_", Topic]),
            {ok, Producers} = rocketmq:ensure_supervised_producers(
                ClientId, ProducerGroup, Topic, ProducerOpts#{name => WorkersTab}
            ),
            persistent_term:put({?EMQX_PLUGIN_ROCKETMQ_APP, ?EMQX_PLUGIN_ROCKETMQ_PRODUCERS},
                [{Topic, Producers} | ProducersL]),
            Producers
    end.
