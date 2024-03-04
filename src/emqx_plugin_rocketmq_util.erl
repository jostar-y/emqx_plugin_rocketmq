-module(emqx_plugin_rocketmq_util).

-include_lib("emqx/include/logger.hrl").

-export([
    client_id/1
    , hosts/1
    , acl_info/2
    , workers_tab/1
    , render/2
]).

client_id(ClientId) ->
    erlang:binary_to_atom(<<"emqx_plugin:rocketmq_client:", (bin(ClientId))/binary>>, utf8).

bin(Bin) when is_binary(Bin) -> Bin;
bin(Str) when is_list(Str) -> list_to_binary(Str);
bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8).

hosts(Hosts) ->
    lists:map(
        fun(#{hostname := Host, port := Port}) -> {Host, Port} end,
        emqx_schema:parse_servers(Hosts, #{default_port => 9876})
    ).

acl_info(<<>>, _) ->
    #{};
acl_info(AccessKey, SecretKey) when is_binary(AccessKey) ->
    #{
        access_key => AccessKey,
        secret_key => emqx_maybe:define(emqx_secret:unwrap(SecretKey), <<>>)
    };
acl_info(_, _) ->
    #{}.

workers_tab(Topic) ->
    erlang:binary_to_atom(<<"emqx_plugin_rocketmq_", (bin(Topic))/binary>>, utf8).

render(Template, Message) ->
    Opts = #{
        var_trans => fun
                         (undefined) -> <<"">>;
                         (X) -> emqx_utils_conv:bin(X)
                     end,
        return => full_binary
    },
    emqx_placeholder:proc_tmpl(Template, Message, Opts).