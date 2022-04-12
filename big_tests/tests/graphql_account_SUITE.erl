-module(graphql_account_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile([export_all, nowarn_export_all]).

-import(distributed_helper, [mim/0, require_rpc_nodes/1, rpc/4]).
-import(graphql_helper, [execute/3, execute_auth/2, get_listener_port/1,
                         get_listener_config/1, get_ok_value/2, get_err_msg/1]).

-define(NOT_EXISTING_JID, <<"unknown987@unknown">>).

suite() ->
    require_rpc_nodes([mim]) ++ escalus:suite().

all() ->
    [{group, user_account_handler},
     {group, admin_account_handler}].

groups() ->
    [{user_account_handler, [parallel], user_account_handler()},
     {admin_account_handler, [], admin_account_handler()}].

user_account_handler() ->
    [user_unregister,
     user_change_password].

admin_account_handler() ->
    [admin_list_users,
     admin_count_users,
     admin_get_active_users_number,
     admin_check_password,
     admin_check_password_hash,
     admin_check_plain_password_hash,
     admin_check_user,
     admin_register_user,
     admin_register_random_user,
     admin_remove_non_existing_user,
     admin_remove_existing_user,
     admin_ban_user,
     admin_change_user_password,
     admin_list_old_users_domain,
     admin_list_old_users_all,
     admin_remove_old_users_domain,
     admin_remove_old_users_all].

init_per_suite(Config) ->
    Config1 = [{ctl_auth_mods, mongoose_helper:auth_modules()} | Config],
    Config2 = escalus:init_per_suite(Config1),
    dynamic_modules:save_modules(domain_helper:host_type(), Config2).

end_per_suite(Config) ->
    dynamic_modules:restore_modules(Config),
    escalus:end_per_suite(Config).

init_per_group(admin_account_handler, Config) ->
    Mods = [{mod_last, config_parser_helper:default_mod_config(mod_last)}],
    dynamic_modules:ensure_modules(domain_helper:host_type(), Mods),
    dynamic_modules:ensure_modules(domain_helper:secondary_host_type(), Mods),
    Config1 = escalus:create_users(Config, escalus:get_users([alice])),
    graphql_helper:init_admin_handler(Config1);
init_per_group(user_account_handler, Config) ->
    [{schema_endpoint, user} | Config];
init_per_group(_, Config) ->
    Config.

end_per_group(admin_account_handler, Config) ->
    escalus_fresh:clean(),
    escalus:delete_users(Config, escalus:get_users([alice])),
    dynamic_modules:restore_modules(Config);
end_per_group(user_account_handler, _Config) ->
    escalus_fresh:clean();
end_per_group(_, _Config) ->
    ok.

init_per_testcase(C, Config) when C =:= admin_list_old_users_all;
                                  C =:= admin_list_old_users_domain;
                                  C =:= admin_remove_old_users_all;
                                  C =:= admin_remove_old_users_domain ->
    {_, AuthMods} = lists:keyfind(ctl_auth_mods, 1, Config),
    case lists:member(ejabberd_auth_ldap, AuthMods) of
        true -> {skip, not_fully_supported_with_ldap};
        false ->
            Config1 = escalus:create_users(Config, escalus:get_users([alice, bob, alice_bis])),
            escalus:init_per_testcase(C, Config1)
    end;
init_per_testcase(admin_register_user = C, Config) ->
    Config1 = [{user, {<<"gql_admin_registration_test">>, domain_helper:domain()}} | Config],
    escalus:init_per_testcase(C, Config1);
init_per_testcase(admin_check_plain_password_hash = C, Config) ->
    {_, AuthMods} = lists:keyfind(ctl_auth_mods, 1, Config),
    case lists:member(ejabberd_auth_ldap, AuthMods) of
        true ->
            {skip, not_fully_supported_with_ldap};
        false ->
            AuthOpts = mongoose_helper:auth_opts_with_password_format(plain),
            Config1 = mongoose_helper:backup_and_set_config_option(
                        Config, {auth, domain_helper:host_type()}, AuthOpts),
            Config2 = escalus:create_users(Config1, escalus:get_users([carol])),
            escalus:init_per_testcase(C, Config2)
    end;
init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(C, Config) when C =:= admin_list_old_users_all;
                                 C =:= admin_list_old_users_domain;
                                 C =:= admin_remove_old_users_all;
                                 C =:= admin_remove_old_users_domain ->
    escalus:delete_users(Config, escalus:get_users([alice, bob, alice_bis]));
end_per_testcase(admin_register_user = C, Config) ->
    {Username, Domain} = proplists:get_value(user, Config),
    rpc(mim(), mongoose_account_api, unregister_user, [Username, Domain]),
    escalus:end_per_testcase(C, Config);
end_per_testcase(admin_check_plain_password_hash, Config) ->
    mongoose_helper:restore_config(Config),
    escalus:delete_users(Config, escalus:get_users([carol]));
end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).

user_unregister(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}], fun user_unregister_story/2).

user_unregister_story(Config, Alice) ->
    Ep = ?config(schema_endpoint, Config),
    Password = lists:last(escalus_users:get_usp(Config, alice)),
    BinJID = escalus_client:full_jid(Alice),
    Creds = {BinJID, Password},
    Query = <<"mutation { account { unregister } }">>,

    Path = [data, account, unregister],
    Resp = execute(Ep, #{query => Query}, Creds),
    ?assertNotEqual(nomatch, binary:match(get_ok_value(Path, Resp), <<"successfully unregistered">>)),
    % Ensure the user is removed
    AllUsers = rpc(mim(), mongoose_account_api, list_users, [domain_helper:domain()]),
    LAliceJID = jid:to_binary(jid:to_lower((jid:binary_to_bare(BinJID)))),
    ?assertNot(lists:member(LAliceJID, AllUsers)).
    
user_change_password(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}], fun user_change_password_story/2).

user_change_password_story(Config, Alice) ->
    Ep = ?config(schema_endpoint, Config),
    Password = lists:last(escalus_users:get_usp(Config, alice)),
    Creds = {escalus_client:full_jid(Alice), Password},
    % Set an empty password
    Resp1 = execute(Ep, user_change_password_body(<<>>), Creds),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp1), <<"Empty password">>)),
    % Set a correct password
    Path = [data, account, changePassword],
    Resp2 = execute(Ep, user_change_password_body(<<"kaczka">>), Creds),
    ?assertNotEqual(nomatch, binary:match(get_ok_value(Path, Resp2), <<"Password changed">>)).

admin_list_users(Config) ->
    % An unknown domain
    Resp = execute_auth(list_users_body(<<"unknown-domain">>), Config),
    ?assertEqual([], get_ok_value([data, account, listUsers], Resp)),
    % A domain with users
    Domain = domain_helper:domain(),
    Username = jid:nameprep(escalus_users:get_username(Config, alice)),
    JID = <<Username/binary, "@", Domain/binary>>,
    Resp2 = execute_auth(list_users_body(Domain), Config),
    Users = get_ok_value([data, account, listUsers], Resp2),
    ?assert(lists:member(JID, Users)).
    
admin_count_users(Config) ->
    % An unknown domain
    Resp = execute_auth(count_users_body(<<"unknown-domain">>), Config),
    ?assertEqual(0, get_ok_value([data, account, countUsers], Resp)),
    % A domain with at least one user
    Domain = domain_helper:domain(),
    Resp2 = execute_auth(count_users_body(Domain), Config),
    ?assert(0 < get_ok_value([data, account, countUsers], Resp2)).

admin_get_active_users_number(Config) ->
    % Check non-existing domain
    Resp = execute_auth(get_active_users_number_body(<<"unknown-domain">>, 5), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp), <<"Cannot count">>)),
    % Check an existing domain without active users
    Resp2 = execute_auth(get_active_users_number_body(domain_helper:domain(), 5), Config),
    ?assertEqual(0, get_ok_value([data, account, countActiveUsers], Resp2)).

admin_check_password(Config) ->
    Password = lists:last(escalus_users:get_usp(Config, alice)),
    BinJID = escalus_users:get_jid(Config, alice),
    Path = [data, account, checkPassword],
    % A correct password
    Resp1 = execute_auth(check_password_body(BinJID, Password), Config),
    ?assertMatch(#{<<"correct">> := true, <<"message">> := _}, get_ok_value(Path, Resp1)),
    % An incorrect password
    Resp2 = execute_auth(check_password_body(BinJID, <<"incorrect_pw">>), Config),
    ?assertMatch(#{<<"correct">> := false, <<"message">> := _}, get_ok_value(Path, Resp2)),
    % A non-existing user
    Resp3 = execute_auth(check_password_body(?NOT_EXISTING_JID, Password), Config),
    ?assertEqual(null, get_ok_value(Path, Resp3)).

admin_check_password_hash(Config) ->
    UserSCRAM = escalus_users:get_jid(Config, alice),
    EmptyHash = list_to_binary(get_md5(<<>>)),
    Method = <<"md5">>,
    % SCRAM password user
    Resp1 = execute_auth(check_password_hash_body(UserSCRAM, EmptyHash, Method), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp1), <<"SCRAM password">>)),
    % A non-existing user
    Resp2 = execute_auth(check_password_hash_body(?NOT_EXISTING_JID, EmptyHash, Method), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp2), <<"not exist">>)).

admin_check_plain_password_hash(Config) ->
    UserJID = escalus_users:get_jid(Config, carol),
    Password = lists:last(escalus_users:get_usp(Config, carol)),
    Method = <<"md5">>,
    Hash = list_to_binary(get_md5(Password)),
    WrongHash = list_to_binary(get_md5(<<"wrong password">>)),
    Path = [data, account, checkPasswordHash],
    % A correct hash
    Resp = execute_auth(check_password_hash_body(UserJID, Hash, Method), Config),
    ?assertMatch(#{<<"correct">> := true, <<"message">> := _}, get_ok_value(Path, Resp)),
    % An incorrect hash
    Resp2 = execute_auth(check_password_hash_body(UserJID, WrongHash, Method), Config),
    ?assertMatch(#{<<"correct">> := false, <<"message">> := _}, get_ok_value(Path, Resp2)),
    % A not-supported hash method
    Resp3 = execute_auth(check_password_hash_body(UserJID, Hash, <<"a">>), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp3), <<"not supported">>)).

admin_check_user(Config) ->
    BinJID = escalus_users:get_jid(Config, alice),
    Path = [data, account, checkUser],
    % An existing user
    Resp1 = execute_auth(check_user_body(BinJID), Config),
    ?assertMatch(#{<<"exist">> := true, <<"message">> := _}, get_ok_value(Path, Resp1)),
    % A non-existing user
    Resp2 = execute_auth(check_user_body(?NOT_EXISTING_JID), Config),
    ?assertMatch(#{<<"exist">> := false, <<"message">> := _}, get_ok_value(Path, Resp2)).

admin_register_user(Config) ->
    Password = <<"my_password">>,
    {Username, Domain} = proplists:get_value(user, Config),
    Path = [data, account, registerUser, message],
    % Register a new user
    Resp1 = execute_auth(register_user_body(Domain, Username, Password), Config),
    ?assertNotEqual(nomatch, binary:match(get_ok_value(Path, Resp1), <<"successfully registered">>)),
    % Try to register a user with existing name
    Resp2 = execute_auth(register_user_body(Domain, Username, Password), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp2), <<"already registered">>)).

admin_register_random_user(Config) ->
    Password = <<"my_password">>,
    Domain = domain_helper:domain(),
    Path = [data, account, registerUser],
    % Register a new user
    Resp1 = execute_auth(register_user_body(Domain, null, Password), Config),
    #{<<"message">> := Msg, <<"jid">> := JID} = get_ok_value(Path, Resp1),
    {Username, Server} = jid:to_lus(jid:from_binary(JID)),

    ?assertNotEqual(nomatch, binary:match(Msg, <<"successfully registered">>)),
    {ok, _} = rpc(mim(), mongoose_account_api, unregister_user, [Username, Server]).

admin_remove_non_existing_user(Config) ->
    Resp = execute_auth(remove_user_body(?NOT_EXISTING_JID), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp), <<"not exist">>)).

admin_remove_existing_user(Config) ->
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
        Path = [data, account, removeUser, message],
        BinJID = escalus_client:full_jid(Alice),
        Resp4 = execute_auth(remove_user_body(BinJID), Config),
        ?assertNotEqual(nomatch, binary:match(get_ok_value(Path, Resp4),
                                              <<"successfully unregister">>))
    end).

admin_ban_user(Config) ->
    Path = [data, account, banUser, message],
    Reason = <<"annoying">>,
    % Ban not existing user
    Resp1 = execute_auth(ban_user_body(?NOT_EXISTING_JID, Reason), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp1), <<"not allowed">>)),
    % Ban an existing user
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
        BinJID = escalus_client:full_jid(Alice),
        Resp2 = execute_auth(ban_user_body(BinJID, Reason), Config),
        ?assertNotEqual(nomatch, binary:match(get_ok_value(Path, Resp2), <<"successfully banned">>))
    end).

admin_change_user_password(Config) ->
    Path = [data, account, changeUserPassword, message],
    NewPassword = <<"new password">>,
    % Change password of not existing user
    Resp1 = execute_auth(change_user_password_body(?NOT_EXISTING_JID, NewPassword), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp1), <<"not allowed">>)),
    % Set an empty password
    Resp2 = execute_auth(change_user_password_body(?NOT_EXISTING_JID, <<>>), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Resp2), <<"Empty password">>)),
    % Change password of an existing user
    escalus:fresh_story(Config, [{alice, 1}], fun(Alice) ->
        BinJID = escalus_client:full_jid(Alice),
        Resp3 = execute_auth(change_user_password_body(BinJID, NewPassword), Config),
        ?assertNotEqual(nomatch, binary:match(get_ok_value(Path, Resp3), <<"Password changed">>))
    end).

admin_remove_old_users_domain(Config) ->
    [AliceName, Domain, _] = escalus_users:get_usp(Config, alice),
    [BobName, Domain, _] = escalus_users:get_usp(Config, bob),
    [AliceBisName, BisDomain, _] = escalus_users:get_usp(Config, alice_bis),

    Now = erlang:system_time(seconds),
    set_last(AliceName, Domain, Now),
    set_last(BobName, Domain, Now - 86400 * 30),

    Path = [data, account, removeOldUsers, users],
    Resp = execute_auth(remove_old_users_body(Domain, 10), Config),
    ?assertEqual(1, length(get_ok_value(Path, Resp))),
    ?assertMatch({user_does_not_exist, _}, check_account(BobName, Domain)),
    ?assertMatch({ok, _}, check_account(AliceName, Domain)),
    ?assertMatch({ok, _}, check_account(AliceBisName, BisDomain)).

admin_remove_old_users_all(Config) ->
    [AliceName, Domain, _] = escalus_users:get_usp(Config, alice),
    [BobName, Domain, _] = escalus_users:get_usp(Config, bob),
    [AliceBisName, BisDomain, _] = escalus_users:get_usp(Config, alice_bis),

    Now = erlang:system_time(seconds),
    OldTime = Now - 86400 * 30,
    set_last(AliceName, Domain, Now),
    set_last(BobName, Domain, OldTime),
    set_last(AliceBisName, BisDomain, OldTime),

    Path = [data, account, removeOldUsers, users],
    Resp = execute_auth(remove_old_users_body(null, 10), Config),
    ?assertEqual(2, length(get_ok_value(Path, Resp))),
    ?assertMatch({user_does_not_exist, _}, check_account(BobName, Domain)),
    ?assertMatch({ok, _}, check_account(AliceName, Domain)),
    ?assertMatch({user_does_not_exist, _}, check_account(AliceBisName, BisDomain)).

admin_list_old_users_domain(Config) ->
    [AliceName, Domain, _] = escalus_users:get_usp(Config, alice),
    [BobName, Domain, _] = escalus_users:get_usp(Config, bob),

    Now = erlang:system_time(seconds),
    set_last(AliceName, Domain, Now),
    set_last(BobName, Domain, Now - 86400 * 30),

    LBob = escalus_utils:jid_to_lower(escalus_users:get_jid(Config, bob)),

    Path = [data, account, listOldUsers],
    Resp = execute_auth(list_old_users_body(Domain, 10), Config),
    Users = get_ok_value(Path, Resp),
    ?assertEqual(1, length(Users)),
    ?assert(lists:member(LBob, Users)).

admin_list_old_users_all(Config) ->
    [AliceName, Domain, _] = escalus_users:get_usp(Config, alice),
    [BobName, Domain, _] = escalus_users:get_usp(Config, bob),
    [AliceBisName, BisDomain, _] = escalus_users:get_usp(Config, alice_bis),

    Now = erlang:system_time(seconds),
    OldTime = Now - 86400 * 30,
    set_last(AliceName, Domain, Now),
    set_last(BobName, Domain, OldTime),
    set_last(AliceBisName, BisDomain, OldTime),

    LBob = escalus_utils:jid_to_lower(escalus_users:get_jid(Config, bob)),
    LAliceBis = escalus_utils:jid_to_lower(escalus_users:get_jid(Config, alice_bis)),

    Path = [data, account, listOldUsers],
    Resp = execute_auth(list_old_users_body(null, 10), Config),
    Users = get_ok_value(Path, Resp),
    ?assertEqual(2, length(Users)),
    ?assert(lists:member(LBob, Users)),
    ?assert(lists:member(LAliceBis, Users)).

%% Helpers

get_md5(AccountPass) ->
    lists:flatten([io_lib:format("~.16B", [X])
                   || X <- binary_to_list(crypto:hash(md5, AccountPass))]).

set_last(User, Domain, TStamp) ->
    rpc(mim(), mod_last, store_last_info,
        [domain_helper:host_type(), escalus_utils:jid_to_lower(User), Domain, TStamp, <<>>]).

check_account(Username, Domain) ->
    rpc(mim(), mongoose_account_api, check_account, [Username, Domain]).

%% Request bodies

list_users_body(Domain) ->
    Query = <<"query Q1($domain: String!) { account { listUsers(domain: $domain) } }">>,
    OpName = <<"Q1">>,
    Vars = #{<<"domain">> => Domain},
    #{query => Query, operationName => OpName, variables => Vars}.

count_users_body(Domain) ->
    Query = <<"query Q1($domain: String!) { account { countUsers(domain: $domain) } }">>,
    OpName = <<"Q1">>,
    Vars = #{<<"domain">> => Domain},
    #{query => Query, operationName => OpName, variables => Vars}.

get_active_users_number_body(Domain, Days) ->
    Query = <<"query Q1($domain: String!, $days: Int!)
              { account { countActiveUsers(domain: $domain, days: $days) } }">>,
    OpName = <<"Q1">>,
    Vars = #{<<"domain">> => Domain, <<"days">> => Days},
    #{query => Query, operationName => OpName, variables => Vars}.

check_password_body(User, Password) ->
    Query = <<"query Q1($user: JID!, $password: String!) 
              { account { checkPassword(user: $user, password: $password) {correct message} } }">>,
    OpName = <<"Q1">>,
    Vars = #{<<"user">> => User, <<"password">> => Password},
    #{query => Query, operationName => OpName, variables => Vars}.

check_password_hash_body(User, PasswordHash, HashMethod) ->
    Query = <<"query Q1($user: JID!, $hash: String!, $method: String!)
              { account { checkPasswordHash(user: $user, passwordHash: $hash, hashMethod: $method)
              {correct message} } }">>,
    OpName = <<"Q1">>,
    Vars = #{<<"user">> => User, <<"hash">> => PasswordHash, <<"method">> => HashMethod},
    #{query => Query, operationName => OpName, variables => Vars}.

check_user_body(User) ->
    Query = <<"query Q1($user: JID!) 
              { account { checkUser(user: $user) {exist message} } }">>,
    OpName = <<"Q1">>,
    Vars = #{<<"user">> => User},
    #{query => Query, operationName => OpName, variables => Vars}.

register_user_body(Domain, Username, Password) ->
    Query = <<"mutation M1($domain: String!, $username: String, $password: String!)
              { account { registerUser(domain: $domain, username: $username, password: $password) 
              { jid message } } }">>,
    OpName = <<"M1">>,
    Vars = #{<<"domain">> => Domain, <<"username">> => Username, <<"password">> => Password},
    #{query => Query, operationName => OpName, variables => Vars}.

remove_user_body(User) ->
    Query = <<"mutation M1($user: JID!) 
              { account { removeUser(user: $user) { jid message } } }">>,
    OpName = <<"M1">>,
    Vars = #{<<"user">> => User},
    #{query => Query, operationName => OpName, variables => Vars}.

remove_old_users_body(Domain, Days) ->
    Query = <<"mutation M1($domain: String, $days: Int!) 
              { account { removeOldUsers(domain: $domain, days: $days) { message users } } }">>,
    OpName = <<"M1">>,
    Vars = #{<<"domain">> => Domain, <<"days">> => Days},
    #{query => Query, operationName => OpName, variables => Vars}.

list_old_users_body(Domain, Days) ->
    Query = <<"query Q1($domain: String, $days: Int!)
              { account { listOldUsers(domain: $domain, days: $days) } }">>,
    OpName = <<"Q1">>,
    Vars = #{<<"domain">> => Domain, <<"days">> => Days},
    #{query => Query, operationName => OpName, variables => Vars}.

ban_user_body(JID, Reason) ->
    Query = <<"mutation M1($user: JID!, $reason: String!) 
              { account { banUser(user: $user, reason: $reason) { jid message } } }">>,
    OpName = <<"M1">>,
    Vars = #{<<"user">> => JID, <<"reason">> => Reason},
    #{query => Query, operationName => OpName, variables => Vars}.

change_user_password_body(JID, NewPassword) ->
    Query = <<"mutation M1($user: JID!, $newPassword: String!) 
              { account { changeUserPassword(user: $user, newPassword: $newPassword) { jid message } } }">>,
    OpName = <<"M1">>,
    Vars = #{<<"user">> => JID, <<"newPassword">> => NewPassword},
    #{query => Query, operationName => OpName, variables => Vars}.

user_change_password_body(NewPassword) ->
    Query = <<"mutation M1($newPassword: String!)
              { account { changePassword(newPassword: $newPassword) } }">>,
    OpName = <<"M1">>,
    Vars = #{<<"newPassword">> => NewPassword},
    #{query => Query, operationName => OpName, variables => Vars}.