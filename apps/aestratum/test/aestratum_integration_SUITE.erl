-module(aestratum_integration_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0,
         groups/0,
         suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_group/2,
         end_per_group/2,
         init_per_testcase/2,
         end_per_testcase/2
        ]).

-export([server_start/1,
         client_start/1,
         new_key_block/1,
         client_stop/1
        ]).

-define(SERVER_NODE, dev1).
-define(CLIENT1_NODE, aestratum_client1).

-define(CLIENT1_ACCOUNT, <<"ak_DummyPubKeyDoNotEverUse999999999999999999999999991">>).

all() ->
    [{group, all}].

groups() ->
    [{all, [sequence],
      [{group, single_client}]
     },

     {single_client, [sequence],
      [server_start,
       client_start,
       new_key_block,
       client_stop
      ]}
    ].

suite() ->
    [].

init_per_suite(Cfg) ->
    CtCfg = [{symlink_name, "latest.aestratum"},
              {test_module, ?MODULE}] ++ Cfg,

    ServerNodeCfg =
        #{<<"mining">> =>
            #{<<"autostart">> => false},
          <<"stratum">> =>
            #{<<"enabled">> => true,
              <<"connection">> =>
                  #{<<"port">> => 9999,
                    <<"max_connections">> => 1024,
                    <<"num_acceptors">> => 100,
                    <<"transport">> => <<"tcp">>},
              <<"session">> =>
                  #{<<"extra_nonce_bytes">> => 4,
                    <<"initial_share_target">> =>
                        115790322390251417039241401711187164934754157181743688420499462401711837020160,
                    <<"max_share_target">> =>
                        115790322390251417039241401711187164934754157181743688420499462401711837020160,
                    <<"desired_solve_time">> => 30,
                    <<"max_solve_time">> => 60,
                    <<"share_target_diff_threshold">> => 5.0,
                    <<"max_jobs">> => 20,
                    <<"max_workers">> => 10,
                    <<"msg_timeout">> => 15},
              <<"reward">> =>
                  #{<<"reward_last_rounds">> => 2,
                    <<"beneficiaries">> =>
                        [<<"ak_2hJJGh3eJA2v9yLz73To7P8LvoHdz3arku3WXvgbCfwQyaL4nK:3.3">>,
                         <<"ak_241xf1kQiexbSvWKfn5uve7ugGASjME93zDbr6SGQzYSCMTeQS:2.2">>],
                    <<"keys">> => #{<<"dir">> => <<"stratum_keys">>}}
             }},

    Client1NodeCfg =
        #{<<"connection">> =>
            #{<<"transport">> => <<"tcp">>,
              <<"host">> => <<"localhost">>,
              <<"port">> => 9999,
              <<"req_timeout">> => 15,
              <<"req_retries">> => 3},
          <<"user">> =>
            #{<<"account">> => ?CLIENT1_ACCOUNT,
              <<"worker">> => <<"worker1">>},
          <<"miners">> =>
            [#{<<"exec">> => <<"mean29-generic">>,
                <<"exec_group">> => <<"aecuckoo">>,
                <<"extra_args">> => <<"">>,
                <<"hex_enc_hdr">> => false,
                <<"repeats">> => 100,
                <<"edge_bits">> => 29}]
        },

    Cfg1 = aecore_suite_utils:init_per_suite([?SERVER_NODE], ServerNodeCfg, CtCfg),
    Cfg2 = aestratum_client_suite_utils:init_per_suite([?CLIENT1_NODE], Client1NodeCfg, Cfg1),
    [{nodes, [aecore_suite_utils:node_tuple(?SERVER_NODE),
              aestratum_client_suite_utils:node_tuple(?CLIENT1_NODE)]}] ++ Cfg2.

end_per_suite(_Cfg) ->
    ok.

init_per_group(single_client, Cfg) ->
    Nodes = ?config(nodes, Cfg),
    SNode = proplists:get_value(?SERVER_NODE, Nodes),
    C1Node = proplists:get_value(?CLIENT1_NODE, Nodes),
    aecore_suite_utils:start_node(?SERVER_NODE, Cfg),
    aecore_suite_utils:connect(SNode),
    aestratum_client_suite_utils:start_node(?CLIENT1_NODE, Cfg),
    aestratum_client_suite_utils:connect(C1Node),
    Cfg;
init_per_group(_Group, Cfg) ->
    Cfg.

end_per_group(single_client, Cfg) ->
    RpcFun = fun(M, F, A) -> rpc(?SERVER_NODE, M, F, A) end,
    {ok, DbCfg} = aecore_suite_utils:get_node_db_config(RpcFun),
    aecore_suite_utils:stop_node(?SERVER_NODE, Cfg),
    aecore_suite_utils:delete_node_db_if_persisted(DbCfg),
    aestratum_client_suite_utils:stop_node(?CLIENT1_NODE, Cfg),
    ok;
end_per_group(_Group, _Cfg) ->
    ok.

init_per_testcase(_Case, Cfg) ->
    Cfg.

end_per_testcase(_Case, _Cfg) ->
    ok.

server_start(_Cfg) ->
    ensure_app_started(?SERVER_NODE, aestratum),
    await_server_status(?SERVER_NODE, #{session => #{account => ?CLIENT1_ACCOUNT,
                                                     phase => authorized}}),
    ok.

client_start(_Cfg) ->
    ensure_app_started(?CLIENT1_NODE, aestratum_client),
    await_client_status(?CLIENT1_NODE, #{session => #{phase => authorized}}),
    ok.

new_key_block(Cfg) ->
    %% Nodes = ?config(nodes, Cfg),
    %% SNode = proplists:get_value(?SERVER_NODE, Nodes),
    %% aecore_suite_utils:mine_key_blocks(SNode, 1),
    %% SS = server_status(?SERVER_NODE),
    %% CS = client_status(?CLIENT1_NODE),
    %% ct:pal("S: ~p~nC: ~p", [SS, CS]),
    ok.

client_stop(_Cfg) ->
    %% The client's connection handler is stopped and so the client is
    %% disconnected from the server.
    %% TODO
    %rpc(?CLIENT1_NODE, aestratum_client, stop, []),
    %?assertEqual([], rpc(?SERVER_NODE, aestratum, status, [])),
    ok.

%%

ensure_app_started(Node, App) ->
    ensure_app_started(Node, App, 5).

ensure_app_started(Node, App, Retries) when Retries > 0 ->
    Apps = [A || {A, _D, _V} <- rpc(Node, application, which_applications, [])],
    case lists:member(App, Apps) of
        true ->
            ok;
        false ->
            timer:sleep(500),
            ensure_app_started(Node, App, Retries - 1)
    end;
ensure_app_started(_Node, App, 0) ->
    error({timeout_waiting_for_app, App}).

await_server_status(Node, ExpStatus) ->
    await_server_status(Node, ExpStatus, 5).

await_client_status(Node, ExpStatus) ->
    await_client_status(Node, ExpStatus, 5).

%% TODO: make it work for more clients
await_server_status(Node, #{session := #{account := Account}} = ExpStatus,
                    Retries) when Retries > 0 ->
    Status = server_account_status(Node, Account),
    case ExpStatus =:= expected_map(ExpStatus, Status) of
        true  -> ok;
        false -> await_server_status(Node, ExpStatus, Retries - 1)
    end;
await_server_status(_Node, ExpStatus, 0) ->
    error({timeout_waiting_for_server_status, ExpStatus}).

await_client_status(Node, ExpStatus, Retries) when Retries > 0 ->
    Status = client_status(Node),
    case ExpStatus =:= expected_map(ExpStatus, Status) of
        true ->
            ok;
        false ->
            timer:sleep(500),
            await_client_status(Node, ExpStatus, Retries - 1)
    end;
await_client_status(_Node, ExpStatus, 0) ->
    error({timeout_waiting_for_client_status, ExpStatus}).

server_status(Node) ->
    rpc(Node, aestratum, status, []).

server_account_status(Node, Account) ->
    rpc(Node, aestratum, status, [Account]).

client_status(Node) ->
    rpc(Node, aestratum_client, status, []).

rpc(Node, Mod, Fun, Args) when Node =:= dev1; Node =:= dev2; Node =:= dev3 ->
    timer:sleep(500),
    rpc:call(aecore_suite_utils:node_name(Node), Mod, Fun, Args, 5000);
rpc(Node, Mod, Fun, Args) ->
    timer:sleep(500),
    rpc:call(aestratum_client_suite_utils:node_name(Node), Mod, Fun, Args, 5000).

%% ExpMap is a map that we expect. We take keys from the ExpMap and values from
%% Map and then we can compare them. This function works with nested maps.
expected_map(ExpMap, Map) ->
    maps:fold(
      fun(K, V, Acc) when is_map(V) ->
              Acc#{K => expected_map(V, maps:get(K, Map, #{}))};
         (K, _V, Acc) ->
              Acc#{K => maps:get(K, Map, #{})}
      end, #{}, ExpMap).

