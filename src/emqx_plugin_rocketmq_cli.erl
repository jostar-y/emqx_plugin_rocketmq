-module(emqx_plugin_rocketmq_cli).

-export([cmd/1]).

cmd(["reload"]) ->
    emqx_plugin_rocketmq:reload(),
    emqx_ctl:print("topics configuration reload complete.\n");

cmd(_) ->
    emqx_ctl:usage([{"emqx_plugin_rocketmq reload", "Reload topics"}]).
