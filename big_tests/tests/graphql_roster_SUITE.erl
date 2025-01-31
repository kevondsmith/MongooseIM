-module(graphql_roster_SUITE).

-compile([export_all, nowarn_export_all]).

-import(distributed_helper, [mim/0, require_rpc_nodes/1, rpc/4]).
-import(graphql_helper, [execute_user/3, execute_auth/2, get_listener_port/1,
                         get_listener_config/1, get_ok_value/2, get_err_msg/1,
                         get_err_msg/2, make_creds/1, user_to_jid/1, user_to_bin/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("exml/include/exml.hrl").
-include_lib("escalus/include/escalus.hrl").
-include_lib("../../include/mod_roster.hrl").

suite() ->
    require_rpc_nodes([mim]) ++ escalus:suite().

all() ->
    [{group, user_roster},
     {group, admin_roster}].

groups() ->
    [{user_roster, [], user_roster_handler()},
     {admin_roster, [], admin_roster_handler()}].

user_roster_handler() ->
    [user_add_and_delete_contact,
     user_try_add_nonexistent_contact,
     user_add_contacts,
     user_try_delete_nonexistent_contact,
     user_delete_contacts,
     user_invite_accept_and_cancel_subscription,
     user_decline_subscription_ask,
     user_list_contacts,
     user_get_contact,
     user_get_nonexistent_contact
    ].

admin_roster_handler() ->
    [admin_add_and_delete_contact,
     admin_try_add_nonexistent_contact,
     admin_try_add_contact_to_nonexistent_user,
     admin_try_add_contact_with_unknown_domain,
     admin_add_contacts,
     admin_try_delete_nonexistent_contact,
     admin_try_delete_contact_with_unknown_domain,
     admin_delete_contacts,
     admin_invite_accept_and_cancel_subscription,
     admin_decline_subscription_ask,
     admin_try_subscribe_with_unknown_domain,
     admin_set_mutual_subscription,
     admin_set_mutual_subscription_try_connect_nonexistent_users,
     admin_set_mutual_subscription_try_disconnect_nonexistent_users,
     admin_subscribe_to_all,
     admin_subscribe_to_all_with_wrong_user,
     admin_subscribe_all_to_all,
     admin_subscribe_all_to_all_with_wrong_user,
     admin_list_contacts,
     admin_list_contacts_wrong_user,
     admin_get_contact,
     admin_get_contact_wrong_user
    ].

init_per_suite(Config) ->
    Config2 = escalus:init_per_suite(Config),
    dynamic_modules:save_modules(domain_helper:host_type(), Config2).

end_per_suite(Config) ->
    dynamic_modules:restore_modules(Config),
    escalus:end_per_suite(Config).

init_per_group(admin_roster, Config) ->
    graphql_helper:init_admin_handler(Config);
init_per_group(user_roster, Config) ->
    [{schema_endpoint, user} | Config].

end_per_group(admin_roster, _Config) ->
    escalus_fresh:clean();
end_per_group(user_roster, _Config) ->
    escalus_fresh:clean().

init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).

-define(ADD_CONTACT_PATH, [data, roster, addContact]).
-define(ADD_CONTACTS_PATH, [data, roster, addContacts]).
-define(DELETE_CONTACT_PATH, [data, roster, deleteContact]).
-define(DELETE_CONTACTS_PATH, [data, roster, deleteContacts]).
-define(LIST_CONTACTS_PATH, [data, roster, listContacts]).
-define(GET_CONTACT_PATH, [data, roster, getContact]).
-define(SUBSCRIBE_ALL_TO_ALL_PATH, [data, roster, subscribeAllToAll]).
-define(SUBSCRIBE_TO_ALL_PATH, [data, roster, subscribeToAll]).
-define(MUTUAL_SUBSCRIPTION_PATH, [data, roster, setMutualSubscription]).

-define(NONEXISTENT_DOMAIN_USER, <<"abc@abc">>).
-define(NONEXISTENT_USER, <<"abc@", (domain_helper:domain())/binary>>).
-define(NONEXISTENT_USER2, <<"abc2@", (domain_helper:domain())/binary>>).
-define(DEFAULT_GROUPS, [<<"Family">>]).

%% Admin test cases

admin_add_and_delete_contact(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_add_and_delete_contact_story/3).

admin_add_and_delete_contact_story(Config, Alice, Bob) ->
    Res = admin_add_contact(Alice, Bob, Config),
    ?assertNotEqual(nomatch, binary:match(get_ok_value(?ADD_CONTACT_PATH, Res),
                                          <<"successfully">>)),
    check_contacts([Bob], Alice),

    Res2 = execute_auth(admin_delete_contact_body(Alice, Bob), Config),
    ?assertNotEqual(nomatch, binary:match(get_ok_value(?DELETE_CONTACT_PATH, Res2),
                                          <<"successfully">>)),
    check_contacts([], Alice).

admin_try_add_nonexistent_contact(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}], fun admin_try_add_nonexistent_contact/2).

admin_try_add_nonexistent_contact(Config, Alice) ->
    Contact = ?NONEXISTENT_DOMAIN_USER,
    Res = admin_add_contact(Alice, Contact, Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), Contact)),
    check_contacts([], Alice).

admin_try_add_contact_to_nonexistent_user(Config) ->
    User = ?NONEXISTENT_USER,
    Contact = ?NONEXISTENT_USER2,
    Res = admin_add_contact(User, Contact, Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), User)),
    check_contacts([], User).

admin_try_add_contact_with_unknown_domain(Config) ->
    User = ?NONEXISTENT_DOMAIN_USER,
    Contact = ?NONEXISTENT_USER2,
    Res = admin_add_contact(User, Contact, Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"not found">>)).

admin_try_delete_nonexistent_contact(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_try_delete_nonexistent_contact_story/3).

admin_try_delete_nonexistent_contact_story(Config, Alice, Bob) ->
    Res = execute_auth(admin_delete_contact_body(Alice, Bob), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"not exist">>)).

admin_try_delete_contact_with_unknown_domain(Config) ->
    User = ?NONEXISTENT_DOMAIN_USER,
    Res = execute_auth(admin_delete_contact_body(User, User), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"not found">>)).

admin_add_contacts(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_add_contacts_story/3).

admin_add_contacts_story(Config, Alice, Bob) ->
    Res = execute_auth(admin_add_contacts_body(Alice, [Bob, ?NONEXISTENT_DOMAIN_USER]), Config),
    [R1, null] = get_ok_value(?ADD_CONTACTS_PATH, Res),
    ?assertNotEqual(nomatch, binary:match(R1, <<"successfully">>)),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"does not exist">>)).

admin_delete_contacts(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_delete_contacts_story/3).

admin_delete_contacts_story(Config, Alice, Bob) ->
    execute_auth(admin_add_contacts_body(Alice, [Bob]), Config),
    Res = execute_auth(admin_delete_contacts_body(Alice, [Bob, ?NONEXISTENT_DOMAIN_USER]), Config),
    [R1, null] = get_ok_value(?DELETE_CONTACTS_PATH, Res),
    ?assertNotEqual(nomatch, binary:match(R1, <<"successfully">>)),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"does not exist">>)).

admin_invite_accept_and_cancel_subscription(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_invite_accept_and_cancel_subscription_story/3).

admin_invite_accept_and_cancel_subscription_story(Config, Alice, Bob) ->
    % Add contacts
    admin_add_contact(Alice, Bob, Config),
    admin_add_contact(Bob, Alice, Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Bob, 1)),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Alice, 1)),
    % Send invitation to subscribe 
    execute_auth(admin_subscription_body(Alice, Bob, <<"INVITE">>), Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Alice)),
    escalus:assert(is_presence_with_type, [<<"subscribe">>], escalus:wait_for_stanza(Bob)),
    ?assertMatch(#roster{ask = out, subscription = none}, get_roster(Alice, Bob)),
    % Accept invitation 
    execute_auth(admin_subscription_body(Bob, Alice, <<"ACCEPT">>), Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Bob)),
    IsSub = fun(S) -> escalus_pred:is_presence_with_type(<<"subscribed">>, S) end,
    escalus:assert_many([is_roster_set, IsSub, is_presence],
                        escalus:wait_for_stanzas(Alice, 3)),
    ?assertMatch(#roster{ask = none, subscription = from}, get_roster(Bob, Alice)),
    % Cancel subscription
    execute_auth(admin_subscription_body(Alice, Bob, <<"CANCEL">>), Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Alice)),
    ?assertMatch(#roster{ask = none, subscription = none}, get_roster(Alice, Bob)).

admin_decline_subscription_ask(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_decline_subscription_ask_story/3).

admin_decline_subscription_ask_story(Config, Alice, Bob) ->
    % Add contacts
    execute_auth(admin_add_contact_body(Alice, Bob, null, null), Config),
    execute_auth(admin_add_contact_body(Bob, Alice, null, null), Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Bob, 1)),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Alice, 1)),
    % Send invitation to subscribe 
    execute_auth(admin_subscription_body(Bob, Alice, <<"INVITE">>), Config),
    ?assertMatch(#roster{ask = in, subscription = none}, get_roster(Alice, Bob)),
    ?assertMatch(#roster{ask = out, subscription = none}, get_roster(Bob, Alice)),
    % Decline the invitation 
    execute_auth(admin_subscription_body(Alice, Bob, <<"DECLINE">>), Config),
    ?assertMatch(does_not_exist, get_roster(Alice, Bob)),
    ?assertMatch(#roster{ask = none, subscription = none}, get_roster(Bob, Alice)).

admin_try_subscribe_with_unknown_domain(Config) ->
    Bob = ?NONEXISTENT_DOMAIN_USER,
    Alice = ?NONEXISTENT_USER,
    Res = execute_auth(admin_subscription_body(Bob, Alice, <<"INVITE">>), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"not found">>)).

admin_set_mutual_subscription(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_set_mutual_subscription_story/3).

admin_set_mutual_subscription_story(Config, Alice, Bob) ->
    Res = execute_auth(admin_mutual_subscription_body(Alice, Bob, <<"CONNECT">>), Config),
    ?assertNotEqual(nomatch, binary:match(get_ok_value(?MUTUAL_SUBSCRIPTION_PATH, Res),
                                          <<"successfully">>)),
    ?assertMatch(#roster{ask = none, subscription = both}, get_roster(Alice, Bob)),
    ?assertMatch(#roster{ask = none, subscription = both}, get_roster(Bob, Alice)),

    Res2 = execute_auth(admin_mutual_subscription_body(Alice, Bob, <<"DISCONNECT">>), Config),
    ?assertNotEqual(nomatch, binary:match(get_ok_value(?MUTUAL_SUBSCRIPTION_PATH, Res2),
                                          <<"successfully">>)),
    ?assertMatch(does_not_exist, get_roster(Alice, Bob)),
    ?assertMatch(does_not_exist, get_roster(Bob, Alice)).

admin_set_mutual_subscription_try_connect_nonexistent_users(Config) ->
    Alice = ?NONEXISTENT_DOMAIN_USER,
    Bob = ?NONEXISTENT_USER,
    Res = execute_auth(admin_mutual_subscription_body(Alice, Bob, <<"CONNECT">>), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"not found">>)).

admin_set_mutual_subscription_try_disconnect_nonexistent_users(Config) ->
    Alice = ?NONEXISTENT_DOMAIN_USER,
    Bob = ?NONEXISTENT_USER,
    Res = execute_auth(admin_mutual_subscription_body(Alice, Bob, <<"DISCONNECT">>), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"not found">>)).

admin_subscribe_to_all(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}, {kate, 1}],
                                    fun admin_subscribe_to_all_story/4).

admin_subscribe_to_all_story(Config, Alice, Bob, Kate) ->
    Res = execute_auth(admin_subscribe_to_all_body(Alice, [Bob, Kate]), Config),
    check_if_created_succ(?SUBSCRIBE_TO_ALL_PATH, Res),

    check_contacts([Bob, Kate], Alice),
    check_contacts([Alice], Bob),
    check_contacts([Alice], Kate).

admin_subscribe_to_all_with_wrong_user(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_subscribe_to_all_with_wrong_user_story/3).

admin_subscribe_to_all_with_wrong_user_story(Config, Alice, Bob) ->
    Kate = ?NONEXISTENT_DOMAIN_USER,
    Res = execute_auth(admin_subscribe_to_all_body(Alice, [Bob, Kate]), Config),
    check_if_created_succ(?SUBSCRIBE_TO_ALL_PATH, Res, [true, false]),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"does not exist">>)),

    check_contacts([Bob], Alice),
    check_contacts([Alice], Bob).

admin_subscribe_all_to_all(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}, {kate, 1}],
                                    fun admin_subscribe_all_to_all_story/4).

admin_subscribe_all_to_all_story(Config, Alice, Bob, Kate) ->
    Res = execute_auth(admin_subscribe_all_to_all_body([Alice, Bob, Kate]), Config),
    check_if_created_succ(?SUBSCRIBE_ALL_TO_ALL_PATH, Res),

    check_contacts([Bob, Kate], Alice),
    check_contacts([Alice, Kate], Bob),
    check_contacts([Alice, Bob], Kate).

admin_subscribe_all_to_all_with_wrong_user(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_subscribe_all_to_all_with_wrong_user_story/3).

admin_subscribe_all_to_all_with_wrong_user_story(Config, Alice, Bob) ->
    Kate = ?NONEXISTENT_DOMAIN_USER,
    Res = execute_auth(admin_subscribe_all_to_all_body([Alice, Bob, Kate]), Config),
    check_if_created_succ(?SUBSCRIBE_ALL_TO_ALL_PATH, Res, [true, false, false]),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(1, Res), <<"does not exist">>)),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(2, Res), <<"does not exist">>)),

    check_contacts([Bob], Alice),
    check_contacts([Alice], Bob).

admin_list_contacts(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_list_contacts_story/3).

admin_list_contacts_story(Config, Alice, Bob) ->
    BobBin = escalus_utils:jid_to_lower(escalus_client:short_jid(Bob)),
    BobName = escalus_client:username(Bob),
    admin_add_contact(Alice, Bob, Config),
    Res = execute_auth(admin_list_contacts_body(Alice), Config),
    [#{<<"subscription">> := <<"NONE">>, <<"ask">> := <<"NONE">>, <<"jid">> := BobBin,
       <<"name">> := BobName, <<"groups">> := ?DEFAULT_GROUPS}] =
        get_ok_value([data, roster, listContacts], Res).

admin_list_contacts_wrong_user(Config) ->
    % User with a non-existent domain
    Res = execute_auth(admin_list_contacts_body(?NONEXISTENT_DOMAIN_USER), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"not found">>)),
    % Non-existent user with existent domain
    Res2 = execute_auth(admin_list_contacts_body(?NONEXISTENT_USER), Config),
    ?assertEqual([], get_ok_value(?LIST_CONTACTS_PATH, Res2)).

admin_get_contact(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun admin_get_contact_story/3).

admin_get_contact_story(Config, Alice, Bob) ->
    BobBin = escalus_utils:jid_to_lower(escalus_client:short_jid(Bob)),
    BobName = escalus_client:username(Bob),
    admin_add_contact(Alice, Bob, Config),
    Res = execute_auth(admin_get_contact_body(Alice, Bob), Config),
    #{<<"subscription">> := <<"NONE">>, <<"ask">> := <<"NONE">>, <<"jid">> := BobBin,
      <<"name">> := BobName, <<"groups">> := ?DEFAULT_GROUPS} =
        get_ok_value([data, roster, getContact], Res).

admin_get_contact_wrong_user(Config) ->
    % User with a non-existent domain
    Res = execute_auth(admin_get_contact_body(?NONEXISTENT_DOMAIN_USER, ?NONEXISTENT_USER), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"not found">>)),
    % Non-existent user with existent domain
    Res2 = execute_auth(admin_get_contact_body(?NONEXISTENT_USER, ?NONEXISTENT_USER), Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res2), <<"does not exist">>)).

%% User test cases

user_add_and_delete_contact(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun user_add_and_delete_contact_story/3).

user_add_and_delete_contact_story(Config, Alice, Bob) ->
    % Add a new contact
    Res = user_add_contact(Alice, Bob, Config),
    ?assertNotEqual(nomatch, binary:match(get_ok_value(?ADD_CONTACT_PATH, Res),
                                          <<"successfully">>)),
    check_contacts([Bob], Alice),
    % Delete a contact
    Res2 = execute_user(user_delete_contact_body(Bob), Alice, Config),
    ?assertNotEqual(nomatch, binary:match(get_ok_value(?DELETE_CONTACT_PATH, Res2),
                                          <<"successfully">>)),
    check_contacts([], Alice).

user_try_add_nonexistent_contact(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}], fun user_try_add_nonexistent_contact/2).

user_try_add_nonexistent_contact(Config, Alice) ->
    Contact = ?NONEXISTENT_DOMAIN_USER,
    Res = user_add_contact(Alice, Contact, Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), Contact)),
    check_contacts([], Alice).

user_add_contacts(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun user_add_contacts_story/3).

user_add_contacts_story(Config, Alice, Bob) ->
    Res = execute_user(user_add_contacts_body([Bob, ?NONEXISTENT_DOMAIN_USER]), Alice, Config),
    [R1, null] = get_ok_value(?ADD_CONTACTS_PATH, Res),
    ?assertNotEqual(nomatch, binary:match(R1, <<"successfully">>)),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"does not exist">>)).

user_try_delete_nonexistent_contact(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun user_try_delete_nonexistent_contact_story/3).

user_try_delete_nonexistent_contact_story(Config, Alice, Bob) ->
    Res = execute_user(user_delete_contact_body(Bob), Alice, Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"not exist">>)).

user_delete_contacts(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun user_delete_contacts_story/3).

user_delete_contacts_story(Config, Alice, Bob) ->
    user_add_contact(Alice, Bob, Config),

    Res = execute_user(user_delete_contacts_body([Bob, ?NONEXISTENT_DOMAIN_USER]), Alice, Config),
    [R1, null] = get_ok_value(?DELETE_CONTACTS_PATH, Res),
    ?assertNotEqual(nomatch, binary:match(R1, <<"successfully">>)),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"does not exist">>)).

user_invite_accept_and_cancel_subscription(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun user_invite_accept_and_cancel_subscription_story/3).

user_invite_accept_and_cancel_subscription_story(Config, Alice, Bob) ->
    % Add contacts
    user_add_contact(Alice, Bob, Config),
    user_add_contact(Bob, Alice, Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Bob, 1)),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Alice, 1)),
    % Send invitation to subscribe 
    execute_user(user_subscription_body(Bob, <<"INVITE">>), Alice, Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Alice)),
    escalus:assert(is_presence_with_type, [<<"subscribe">>], escalus:wait_for_stanza(Bob)),
    ?assertMatch(#roster{ask = out, subscription = none}, get_roster(Alice, Bob)),
    % Accept invitation 
    execute_user(user_subscription_body(Alice, <<"ACCEPT">>), Bob, Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Bob)),
    IsSub = fun(S) -> escalus_pred:is_presence_with_type(<<"subscribed">>, S) end,
    escalus:assert_many([is_roster_set, IsSub, is_presence],
                        escalus:wait_for_stanzas(Alice, 3)),
    ?assertMatch(#roster{ask = none, subscription = from}, get_roster(Bob, Alice)),
    % Cancel subscription
    execute_user(user_subscription_body(Bob, <<"CANCEL">>), Alice, Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Alice)),
    ?assertMatch(#roster{ask = none, subscription = none}, get_roster(Alice, Bob)).

user_decline_subscription_ask(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun user_decline_subscription_ask_story/3).

user_decline_subscription_ask_story(Config, Alice, Bob) ->
    % Add contacts
    user_add_contact(Alice, Bob, Config),
    user_add_contact(Bob, Alice, Config),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Bob, 1)),
    escalus:assert(is_roster_set, escalus:wait_for_stanza(Alice, 1)),
    % Send invitation to subscribe 
    execute_user(user_subscription_body(Alice, <<"INVITE">>), Bob, Config),
    ?assertMatch(#roster{ask = in, subscription = none}, get_roster(Alice, Bob)),
    ?assertMatch(#roster{ask = out, subscription = none}, get_roster(Bob, Alice)),
    % Decline the invitation 
    execute_user(user_subscription_body(Bob, <<"DECLINE">>), Alice, Config),
    ?assertMatch(does_not_exist, get_roster(Alice, Bob)),
    ?assertMatch(#roster{ask = none, subscription = none}, get_roster(Bob, Alice)).

user_list_contacts(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun user_list_contacts_story/3).

user_list_contacts_story(Config, Alice, Bob) ->
    BobBin = escalus_utils:jid_to_lower(escalus_client:short_jid(Bob)),
    Name = <<"Bobek">>,
    execute_user(user_add_contact_body(Bob, Name, ?DEFAULT_GROUPS), Alice, Config),
    Res = execute_user(user_list_contacts_body(), Alice, Config),
    [#{<<"subscription">> := <<"NONE">>, <<"ask">> := <<"NONE">>, <<"jid">> := BobBin,
       <<"name">> := Name, <<"groups">> := ?DEFAULT_GROUPS}] =
        get_ok_value(?LIST_CONTACTS_PATH, Res).

user_get_contact(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}, {bob, 1}],
                                    fun user_get_contact_story/3).

user_get_contact_story(Config, Alice, Bob) ->
    BobBin = escalus_utils:jid_to_lower(escalus_client:short_jid(Bob)),
    Name = <<"Bobek">>,
    execute_user(user_add_contact_body(Bob, Name, ?DEFAULT_GROUPS), Alice, Config),
    Res = execute_user(user_get_contact_body(Bob), Alice, Config),
    #{<<"subscription">> := <<"NONE">>, <<"ask">> := <<"NONE">>, <<"jid">> := BobBin,
      <<"name">> := Name, <<"groups">> := ?DEFAULT_GROUPS} =
        get_ok_value(?GET_CONTACT_PATH, Res).

user_get_nonexistent_contact(Config) ->
    escalus:fresh_story_with_config(Config, [{alice, 1}],
                                    fun user_get_nonexistent_contact_story/2).

user_get_nonexistent_contact_story(Config, Alice) ->
    Res = execute_user(user_get_contact_body(?NONEXISTENT_DOMAIN_USER), Alice, Config),
    ?assertNotEqual(nomatch, binary:match(get_err_msg(Res), <<"does not exist">>)).

% Helpers

admin_add_contact(User, Contact, Config) ->
    Name = escalus_utils:get_username(Contact),
    execute_auth(admin_add_contact_body(User, Contact, Name, ?DEFAULT_GROUPS), Config).

user_add_contact(User, Contact, Config) ->
    Name = escalus_utils:get_username(Contact),
    execute_user(user_add_contact_body(Contact, Name, ?DEFAULT_GROUPS), User, Config).

check_contacts(ContactClients, User) ->
    Expected = [escalus_utils:jid_to_lower(escalus_client:short_jid(Client))
                || Client <- ContactClients],
    ExpectedNames = [escalus_client:username(Client) || Client <- ContactClients],
    ActualContacts = get_roster(User),
    Actual = [ jid:to_binary(JID) || #roster{jid = JID} <- ActualContacts],
    ActualNames = [ Name || #roster{name = Name} <- ActualContacts],
    ?assertEqual(lists:sort(Expected), lists:sort(Actual)),
    ?assertEqual(lists:sort(ExpectedNames), lists:sort(ActualNames)),
    [?assertEqual(?DEFAULT_GROUPS, Groups) || #roster{groups = Groups} <- ActualContacts].

check_if_created_succ(Path, Res) ->
    check_if_created_succ(Path, Res, null).

check_if_created_succ(Path, Res, ExpectedOkValue) ->
    OkList = get_ok_value(Path, Res),

    OkList2 = case ExpectedOkValue of
                  null ->
                      [{Msg, true} || Msg <- OkList];
                  _ when is_list(ExpectedOkValue) ->
                      lists:zip(OkList, ExpectedOkValue)
              end,
    [?assertNotEqual(nomatch, binary:match(Msg, <<"created successfully">>))
     || {Msg, ShouldHaveValue} <- OkList2, ShouldHaveValue].

get_roster(User) ->
    {ok, Roster} = rpc(mim(), mod_roster_api, list_contacts, [user_to_jid(User)]),
    Roster.

get_roster(User, Contact) ->
    rpc(mim(), mod_roster, get_roster_entry,
        [domain_helper:host_type(),
         user_to_jid(User),
         jid:to_lower(user_to_jid(Contact)),
         full]).

make_contact(Users) when is_list(Users) ->
    [make_contact(U) || U <- Users];
make_contact(U) ->
    #{jid => user_to_bin(U), name => escalus_utils:get_username(U), groups => ?DEFAULT_GROUPS}.

%% Request bodies

admin_add_contact_body(User, Contact, Name, Groups) ->
    Query = <<"mutation M1($user: JID!, $contact: JID!, $name: String, $groups: [String!])
              { roster { addContact(user: $user, contact: $contact, name: $name, groups: $groups) } }">>,
    OpName = <<"M1">>,
    Vars = #{user => user_to_bin(User), contact => user_to_bin(Contact),
             name => Name, groups => Groups},
    #{query => Query, operationName => OpName, variables => Vars}.

admin_add_contacts_body(User, Contacts) ->
    Query = <<"mutation M1($user: JID!, $contacts: [ContactInput!]!)
              { roster { addContacts(user: $user, contacts: $contacts) } }">>,
    OpName = <<"M1">>,
    Vars = #{user => user_to_bin(User), contacts => make_contact(Contacts)},
    #{query => Query, operationName => OpName, variables => Vars}.

admin_delete_contact_body(User, Contact) ->
    Query = <<"mutation M1($user: JID!, $contact: JID!)
              { roster { deleteContact(user: $user, contact: $contact) } }">>,
    OpName = <<"M1">>,
    Vars = #{user => user_to_bin(User), contact => user_to_bin(Contact)},
    #{query => Query, operationName => OpName, variables => Vars}.

admin_delete_contacts_body(User, Contacts) ->
    Query = <<"mutation M1($user: JID!, $contacts: [JID!]!)
              { roster { deleteContacts(user: $user, contacts: $contacts) } }">>,
    OpName = <<"M1">>,
    Vars = #{user => user_to_bin(User), contacts => [user_to_bin(C) || C <- Contacts]},
    #{query => Query, operationName => OpName, variables => Vars}.

admin_subscription_body(User, Contact, Action) ->
    Query = <<"mutation M1($user: JID!, $contact: JID!, $action: SubAction!)
              { roster { subscription(user: $user, contact: $contact, action: $action) } }">>,
    OpName = <<"M1">>,
    Vars = #{user => user_to_bin(User), contact => user_to_bin(Contact), action => Action},
    #{query => Query, operationName => OpName, variables => Vars}.

admin_mutual_subscription_body(User, Contact, Action) ->
    Query = <<"mutation M1($userA: JID!, $userB: JID!, $action: MutualSubAction!)
              { roster { setMutualSubscription(userA: $userA, userB: $userB, action: $action) } }">>,
    OpName = <<"M1">>,
    Vars = #{userA => user_to_bin(User), userB => user_to_bin(Contact), action => Action},
    #{query => Query, operationName => OpName, variables => Vars}.

admin_subscribe_to_all_body(User, Contacts) ->
    Query = <<"mutation M1($user: ContactInput!, $contacts: [ContactInput!]!)
              { roster { subscribeToAll(user: $user, contacts: $contacts) } }">>,
    OpName = <<"M1">>,
    Vars = #{user => make_contact(User), contacts => make_contact(Contacts)},
    #{query => Query, operationName => OpName, variables => Vars}.

admin_subscribe_all_to_all_body(Users) ->
    Query = <<"mutation M1($contacts: [ContactInput!]!)
              { roster { subscribeAllToAll(contacts: $contacts) } }">>,
    OpName = <<"M1">>,
    Vars = #{contacts => make_contact(Users)},
    #{query => Query, operationName => OpName, variables => Vars}.

admin_list_contacts_body(User) ->
    Query = <<"query Q1($user: JID!)
              { roster { listContacts(user: $user)
              { jid subscription ask name groups} } }">>,
    OpName = <<"Q1">>,
    Vars = #{user => user_to_bin(User)},
    #{query => Query, operationName => OpName, variables => Vars}.

admin_get_contact_body(User, Contact) ->
    Query = <<"query Q1($user: JID!, $contact: JID!)
              { roster { getContact(user: $user, contact: $contact)
              { jid subscription ask name groups} } }">>,
    OpName = <<"Q1">>,
    Vars = #{user => user_to_bin(User), contact => user_to_bin(Contact)},
    #{query => Query, operationName => OpName, variables => Vars}.

user_add_contact_body(Contact, Name, Groups) ->
    Query = <<"mutation M1($contact: JID!, $name: String, $groups: [String!])
              { roster { addContact(contact: $contact, name: $name, groups: $groups) } }">>,
    OpName = <<"M1">>,
    Vars = #{contact => user_to_bin(Contact), name => Name, groups => Groups},
    #{query => Query, operationName => OpName, variables => Vars}.

user_add_contacts_body(Contacts) ->
    Query = <<"mutation M1($contacts: [ContactInput!]!)
              { roster { addContacts(contacts: $contacts) } }">>,
    OpName = <<"M1">>,
    Vars = #{contacts => make_contact(Contacts)},
    #{query => Query, operationName => OpName, variables => Vars}.

user_delete_contact_body(Contact) ->
    Query = <<"mutation M1($contact: JID!)
              { roster { deleteContact(contact: $contact) } }">>,
    OpName = <<"M1">>,
    Vars = #{contact => user_to_bin(Contact)},
    #{query => Query, operationName => OpName, variables => Vars}.

user_delete_contacts_body(Contacts) ->
    Query = <<"mutation M1($contacts: [JID!]!)
              { roster { deleteContacts(contacts: $contacts) } }">>,
    OpName = <<"M1">>,
    Vars = #{contacts => [user_to_bin(C) || C <- Contacts]},
    #{query => Query, operationName => OpName, variables => Vars}.

user_subscription_body(Contact, Action) ->
    Query = <<"mutation M1($contact: JID!, $action: SubAction!)
              { roster { subscription(contact: $contact, action: $action) } }">>,
    OpName = <<"M1">>,
    Vars = #{contact => user_to_bin(Contact), action => Action},
    #{query => Query, operationName => OpName, variables => Vars}.

user_list_contacts_body() ->
    Query = <<"query Q1 { roster { listContacts
              { jid subscription ask name groups} } }">>,
    #{query => Query, operationName => <<"Q1">>, variables => #{}}.

user_get_contact_body(Contact) ->
    Query = <<"query Q1($contact: JID!)
              { roster { getContact(contact: $contact)
              { jid subscription ask name groups} } }">>,
    OpName = <<"Q1">>,
    Vars = #{contact => user_to_bin(Contact)},
    #{query => Query, operationName => OpName, variables => Vars}.
