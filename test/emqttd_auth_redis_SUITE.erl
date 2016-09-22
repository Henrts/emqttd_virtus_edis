%%--------------------------------------------------------------------
%% Copyright (c) 2012-2016 Feng Lee <feng@emqtt.io>.
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

-module(emqttd_auth_redis_SUITE).

-compile(export_all).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("common_test/include/ct.hrl").

-include("emqttd_auth_redis.hrl").

-define(INIT_ACL, [{"mqtt_acl:test1", "publish topic1"},
                   {"mqtt_acl:test2", "subscribe topic2"},
                   {"mqtt_acl:test3", "pubsub topic3"}]).

-define(INIT_AUTH, [{"mqtt_user:root", "is_superuser", "1"},
                    {"mqtt_user:user1", "password", "testpwd"}]).

all() -> 
    [{group, emqttd_auth_redis}].

groups() -> 
    [{emqttd_auth_redis, [sequence],
     [check_acl,
      check_auth]}].

init_per_suite(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    application:start(lager),
    application:set_env(emqttd, conf, filename:join([DataDir, "emqttd.conf"])),
    application:ensure_all_started(emqttd),
    application:set_env(emqttd_auth_redis, conf, filename:join([DataDir, "emqttd_auth_redis.conf"])),
    application:ensure_all_started(emqttd_auth_redis),
    {ok, Connection} = ecpool_worker:client(gproc_pool:pick_worker({ecpool, emqttd_auth_redis})), [{connection, Connection} | Config].

end_per_suite(_Config) ->
    application:stop(emqttd_auth_redis),
    application:stop(ecpool),
    application:stop(eredis),
    application:stop(emqttd),
    emqttd_mnesia:ensure_stopped().

check_acl(Config) ->
    Connection = proplists:get_value(connection, Config),
    Keys = [Key || {Key, _Value} <- ?INIT_ACL],
    [eredis:q(Connection, ["SADD", Key, Value]) || {Key, Value} <- ?INIT_ACL],
    User1 = #mqtt_client{client_id = <<"client1">>, username = <<"test1">>},
    User2 = #mqtt_client{client_id = <<"client2">>, username = <<"test2">>},
    User3 = #mqtt_client{client_id = <<"client3">>, username = <<"test3">>},
    User4 = #mqtt_client{client_id = <<"client4">>, username = <<"$$user4">>},
    deny = emqttd_access_control:check_acl(User1, subscribe, <<"topic1">>),
    allow = emqttd_access_control:check_acl(User1, publish, <<"topic1">>),

    deny = emqttd_access_control:check_acl(User2, publish, <<"topic2">>),
    allow = emqttd_access_control:check_acl(User2, subscribe, <<"topic2">>),
    
    allow = emqttd_access_control:check_acl(User3, publish, <<"topic3">>),
    allow = emqttd_access_control:check_acl(User3, subscribe, <<"topic3">>),
    
    allow = emqttd_access_control:check_acl(User4, publish, <<"a/b/c">>),
    eredis:q(Connection, ["DEL" | Keys]).

check_auth(Config) ->
    Connection = proplists:get_value(connection, Config),
    Keys = [Key || {Key, _Filed, _Value} <- ?INIT_AUTH],
    [eredis:q(Connection, ["HSET", Key, Filed, Value]) || {Key, Filed, Value} <- ?INIT_AUTH],

    User1 = #mqtt_client{client_id = <<"client1">>, username = <<"user1">>},
    User2 = #mqtt_client{client_id = <<"client2">>, username = <<"root">>},
    User3 = #mqtt_client{client_id = <<"client3">>},
    ok = emqttd_access_control:auth(User1, <<"testpwd">>),
    {error, _} = emqttd_access_control:auth(User1, <<"pwderror">>),

    ok = emqttd_access_control:auth(User2, <<"pass">>),
    ok = emqttd_access_control:auth(User2, <<>>),
    {error, username_undefined} = emqttd_access_control:auth(User3, <<>>),
    eredis:q(Connection, ["DEL" | Keys]).



