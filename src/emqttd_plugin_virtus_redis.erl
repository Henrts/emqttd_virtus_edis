%%--------------------------------------------------------------------
%% Copyright (c) 2015-2016 Feng Lee <feng@emqtt.io>.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqttd_plugin_virtus_redis).

-include("emqttd_virtus_redis.hrl").
-include_lib("eredis/include/eredis.hrl").

-include_lib("emqttd/include/emqttd.hrl").
 
-include_lib("emqttd/include/emqttd_protocol.hrl").

-export([load/0, unload/0]).

-export([on_client_connected/3]).
-export([on_message_publish/2]).

%% Called when the plugin loaded
load() ->
    lager:error("Connected ", []),
    {ok, SuperCmd} = gen_conf:value(?APP, supercmd),
    ok = emqttd_access_control:register_mod(
            auth, emqttd_virtus_redis, {SuperCmd, env(authcmd), env(password_hash)}),
    ok = with_cmd_enabled(aclcmd, fun(AclCmd) ->
            emqttd_access_control:register_mod(acl, emqttd_acl_redis, {SuperCmd, AclCmd, env(acl_nomatch)})
        end),
    ok = with_cmd_enabled(subcmd, fun(SubCmd) ->
            emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [SubCmd]),
	       emqttd:hook('message.publish', fun ?MODULE:on_message_publish/2, [SubCmd])
        end).

env(Key) -> {ok, Val} = gen_conf:value(?APP, Key), Val.

on_client_connected(?CONNACK_ACCEPT, Client = #mqtt_client{client_pid = ClientPid}, SubCmd) ->
    lager:error("EMQTT PLUGIN ERLANG CONNECTED _------"),
    case emqttd_virtus_redis_client:query(SubCmd, Client) of
        {ok, Values}   -> emqttd_client:subscribe(ClientPid, topics(Values));
        {error, Error} -> lager:error("Redis Error: ~p, Cmd: ~p", [Error, SubCmd])
    end,
    {ok, Client};

on_client_connected(_ConnAck, _Client, _LoadCmd) ->
    lager:error("EMQTT PLUGIN ERLANG CONNECTED _------"),
    ok.

on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message = #mqtt_message{topic = Topic}, _Env) ->
    lager:error("erlang received message ~p", [Topic]),
    case emqttd_virtus_redis_client:query(["PUBLISH", Topic, Message]) of
 	{ok, Result} -> lager:error("RESULT ~p", [Result]);
	{error, Error2} -> lager:error("Redis Error Publish ~p, Cmd:", [Error2])
    end,
    {ok, Message}.

unload() ->
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3),
    emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqttd_access_control:unregister_mod(auth, emqttd_virtus_redis),
    with_cmd_enabled(aclcmd, fun(_AclCmd) ->
            emqttd_access_control:unregister_mod(acl, emqttd_acl_redis)
        end).

with_cmd_enabled(Name, Fun) ->
    case gen_conf:value(?APP, Name) of
        {ok, Cmd} -> Fun(Cmd);
        undefined -> ok
    end.

topics(Values) ->
    topics(Values, []).
topics([], Acc) ->
    Acc;
topics([Topic, Qos | Vals], Acc) ->
    topics(Vals, [{Topic, i(Qos)}|Acc]).

i(S) -> list_to_integer(binary_to_list(S)).

