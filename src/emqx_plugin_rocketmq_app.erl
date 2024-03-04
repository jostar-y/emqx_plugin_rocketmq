-module(emqx_plugin_rocketmq_app).

-behaviour(application).

-emqx_plugin(?MODULE).

-export([ start/2
        , stop/1
        ]).

start(_StartType, _StartArgs) ->
    {ok, Sup} = emqx_plugin_rocketmq_sup:start_link(),
    emqx_plugin_rocketmq:load(),
    emqx_ctl:register_command(emqx_plugin_rocketmq, {emqx_plugin_rocketmq_cli, cmd}),
    {ok, Sup}.

stop(_State) ->
    emqx_ctl:unregister_command(emqx_plugin_rocketmq),
    emqx_plugin_rocketmq:unload().
