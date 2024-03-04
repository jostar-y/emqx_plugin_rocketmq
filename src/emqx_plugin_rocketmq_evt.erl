-module(emqx_plugin_rocketmq_evt).

-include_lib("emqx/include/emqx.hrl").

-export([
    eventmsg_publish/1
]).

eventmsg_publish(
    Message = #message{
        id = Id,
        from = ClientId,
        qos = QoS,
        flags = Flags,
        topic = Topic,
        payload = Payload,
        timestamp = Timestamp
    }
) ->
    with_basic_columns(
        'message.publish',
        #{
            id => emqx_guid:to_hexstr(Id),
            clientid => ClientId,
            username => emqx_message:get_header(username, Message, undefined),
            payload => Payload,
            peerhost => ntoa(emqx_message:get_header(peerhost, Message, undefined)),
            topic => Topic,
            qos => QoS,
            flags => Flags,
            pub_props => printable_maps(emqx_message:get_header(properties, Message, #{})),
            publish_received_at => Timestamp
        }
    ).

with_basic_columns(EventName, Columns) when is_map(Columns) ->
    Columns#{
        event => EventName,
        timestamp => erlang:system_time(millisecond),
        node => node()
    }.

ntoa(undefined) -> undefined;
ntoa({IpAddr, Port}) -> iolist_to_binary([inet:ntoa(IpAddr), ":", integer_to_list(Port)]);
ntoa(IpAddr) -> iolist_to_binary(inet:ntoa(IpAddr)).


printable_maps(undefined) ->
    #{};
printable_maps(Headers) ->
    maps:fold(
        fun
            (K, V0, AccIn) when K =:= peerhost; K =:= peername; K =:= sockname ->
                AccIn#{K => ntoa(V0)};
            ('User-Property', V0, AccIn) when is_list(V0) ->
                AccIn#{
                    'User-Property' => maps:from_list(V0),
                    'User-Property-Pairs' => [
                        #{
                            key => Key,
                            value => Value
                        }
                        || {Key, Value} <- V0
                    ]
                };
            (_K, V, AccIn) when is_tuple(V) ->
                AccIn;
            (K, V, AccIn) ->
                AccIn#{K => V}
        end,
        #{'User-Property' => #{}},
        Headers
    ).