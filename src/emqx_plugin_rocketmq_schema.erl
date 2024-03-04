-module(emqx_plugin_rocketmq_schema).

-include_lib("hocon/include/hoconsc.hrl").

-export([
    roots/0
    , fields/1
    , desc/1
]).

-import(hoconsc, [enum/1]).

roots() -> [plugin_rocketmq].

fields(plugin_rocketmq) ->
    [
        {connection, ?HOCON(?R_REF(connection), #{desc => ?DESC("connection")})},
        {producer, ?HOCON(?R_REF(producer), #{desc => ?DESC("producer")})},
        {topics, ?HOCON(?ARRAY(?R_REF(topics)),
            #{
                required => true,
                default => [],
                desc => ?DESC("topics")
            })}
    ];
fields(connection) ->
    [
        {bootstrap_hosts, bootstrap_hosts()},
        {client_id, ?HOCON(string(),
            #{
                default => <<"emqx_plugin_rocketmq_connection">>,
                desc => ?DESC("client_id")
            })},
        {access_key, ?HOCON(binary(),
            #{
                default => <<>>,
                desc => ?DESC("access_key")
            })},
        {secret_key, emqx_schema_secret:mk(#{default => <<>>, desc => ?DESC("secret_key")})}
    ];
fields(bootstrap_host) ->
    [
        {host, ?HOCON(string(),
            #{
                validator => emqx_schema:servers_validator(
                    #{default_port => 9876}, _Required = true)
            }
        )}
    ];
fields(producer) ->
    [
        {send_buffer, ?HOCON(emqx_schema:bytesize(),
            #{
                default => "1024KB",
                desc => ?DESC("send_buffer")
            }
        )},
        {refresh_interval, ?HOCON(emqx_schema:timeout_duration(),
            #{
                default => <<"3s">>,
                desc => ?DESC("refresh_interval")
            }
        )}
    ];
fields(topics) ->
    [
        {filter, ?HOCON(binary(),
            #{
                desc => ?DESC("topics_filter"),
                default => <<"#">>
            })},
        {rocketmq_topic, ?HOCON(binary(),
            #{
                desc => ?DESC("topics_rocketmq_topic"),
                default => <<"emqx_test">>
            })},
        {tag, ?HOCON(binary(),
            #{
                default => <<"emq_msg_publish">>,
                desc => ?DESC("tag")
            }
        )},
        {rocketmq_message, ?HOCON(binary(),
            #{
                desc => ?DESC("topics_rocketmq_message"),
                default => <<"${.}">>
            })}
    ].

desc(_) -> undefined.

bootstrap_hosts() ->
    Meta = #{desc => ?DESC("bootstrap_hosts")},
    emqx_schema:servers_sc(Meta, #{default_port => 9876}).