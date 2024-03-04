-module(emqx_plugin_rocketmq).

-include_lib("emqx/include/logger.hrl").
-include("emqx_plugin_rocketmq.hrl").
-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_hooks.hrl").

-export([
    load/0
    , unload/0
    , reload/0
]).

-export([
    on_message_publish/1
]).

-define(evt_mod, emqx_plugin_rocketmq_evt).

load() ->
    _ = ets:new(?PLUGIN_ROCKETMQ_TAB, [named_table, public, set, {keypos, 1}, {read_concurrency, true}]),
    load(read_config()).

load(Conf = #{connection := _, producer := _, topics := Topics}) ->
    {ok, _} = start_resource(Conf),
    topic_parse(Topics),
    hook('message.publish', {?MODULE, on_message_publish, []});
load(_) ->
    {error, "config_error"}.

hook(HookPoint, MFA) ->
    emqx_hooks:add(HookPoint, MFA, _Property = ?HP_HIGHEST).

reload() ->
    ets:delete_all_objects(?PLUGIN_ROCKETMQ_TAB),
    reload(read_config()).

reload(#{topics := Topics}) ->
    topic_parse(Topics).

on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}) ->
    {ok, Message};
on_message_publish(Message = #message{from = From}) ->
    case select(Message) of
        {true, Querys} when Querys =/= [] ->
            Context = #{key => From},
            query(Querys, Context);
        _ ->
            ok
    end,
    {ok, Message}.

read_config() ->
    case hocon:load(rocketmq_config_file()) of
        {ok, RawConf} ->
            case emqx_config:check_config(emqx_plugin_rocketmq_schema, RawConf) of
                {_, #{plugin_rocketmq := Conf}} ->
                    ?SLOG(info, #{
                        msg => "emqx_plugin_rocketmq config",
                        config => Conf
                    }),
                    Conf;
                _ ->
                    ?SLOG(error, #{
                        msg => "bad_hocon_file",
                        file => rocketmq_config_file()
                    }),
                    {error, bad_hocon_file}

            end;
        {error, Error} ->
            ?SLOG(error, #{
                msg => "bad_hocon_file",
                file => rocketmq_config_file(),
                reason => Error
            }),
            {error, bad_hocon_file}
    end.

rocketmq_config_file() ->
    Env = os:getenv("EMQX_PLUGIN_ROCKETMQ_CONF"),
    case Env =:= "" orelse Env =:= false of
        true -> "etc/emqx_plugin_rocketmq.hocon";
        false -> Env
    end.

start_resource(Conf) ->
    ResId = ?PLUGIN_ROCKETMQ_RESOURCE_ID,
    ok = emqx_resource:create_metrics(ResId),
    Result = emqx_resource:create_local(
        ResId,
        ?PLUGIN_ROCKETMQ_RESOURCE_GROUP,
        emqx_plugin_rocketmq_producer,
        Conf,
        #{}),
    start_resource_if_enabled(Result).

start_resource_if_enabled({ok, _Result = #{error := undefined, id := ResId}}) ->
    {ok, ResId};
start_resource_if_enabled({ok, #{error := Error, id := ResId}}) ->
    ?SLOG(error, #{
        msg => "start resource error",
        error => Error,
        resource_id => ResId
    }),
    emqx_resource:stop(ResId),
    error.

unload() ->
    unhook('message.publish', {?MODULE, on_message_publish}),
    emqx_resource:remove_local(?PLUGIN_ROCKETMQ_RESOURCE_ID).

unhook(HookPoint, MFA) ->
    emqx_hooks:del(HookPoint, MFA).

topic_parse([]) ->
    ok;
topic_parse([#{
    filter := Filter,
    rocketmq_topic := RocketmqTopic,
    tag := Tag,
    rocketmq_message := RocketmqMsg
} | T]) ->
    Item = {Filter, RocketmqTopic, Tag, emqx_placeholder:preproc_tmpl(RocketmqMsg)},
    ets:insert(?PLUGIN_ROCKETMQ_TAB, Item),
    topic_parse(T);
topic_parse([_ | T]) ->
    topic_parse(T).

select(Message) ->
    select(ets:tab2list(?PLUGIN_ROCKETMQ_TAB), Message, ?evt_mod:eventmsg_publish(Message), []).

select([], _, _, Acc) ->
    {true, Acc};
select([{Filter, RocketmqTopic, Tag, RocketmqMsgTmpl} | T], Message, EvtMsg, Acc) ->
    case match_topic(Message, Filter) of
        true ->
            Msg = emqx_plugin_rocketmq_util:render(RocketmqMsgTmpl, EvtMsg),
            select(T, Message, EvtMsg, [{RocketmqTopic, Tag, Msg} | Acc]);
        false ->
            select(T, Message, EvtMsg, Acc)
    end.

match_topic(_, <<$#, _/binary>>) ->
    false;
match_topic(_, <<$+, _/binary>>) ->
    false;
match_topic(#message{topic = <<"$SYS/", _/binary>>}, _) ->
    false;
match_topic(#message{topic = Topic}, Filter) ->
    emqx_topic:match(Topic, Filter);
match_topic(_, _) ->
    false.

query(Querys, Context) ->
    query_ret(
        emqx_resource:query(?PLUGIN_ROCKETMQ_RESOURCE_ID, {Querys, Context}),
        Querys,
        Context
    ).

query_ret({_, ok}, _, _) ->
    ok;
query_ret(Ret, Querys, Context) ->
    ?SLOG(error,
        #{
            msg => "failed_to_query_rocketmq_resource",
            ret => Ret,
            querys => Querys,
            context => Context
        }).