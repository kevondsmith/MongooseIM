-module(mongoose_graphql_muc_light_user_query).

-export([execute/4]).

-ignore_xref([execute/4]).

-include("../mongoose_graphql_types.hrl").

-import(mongoose_graphql_helper, [make_error/2, format_result/2]).
-import(mongoose_graphql_muc_light_helper, [make_room/1, make_ok_user/1,
                                            page_size_or_max_limit/2]).

execute(Ctx, _Obj, <<"listRooms">>, Args) ->
    list_user_rooms(Ctx, Args);
execute(Ctx, _Obj, <<"listRoomUsers">>, Args) ->
    list_room_users(Ctx, Args);
execute(Ctx, _Obj, <<"getRoomConfig">>, Args) ->
    get_room_config(Ctx, Args);
execute(Ctx, _Obj, <<"getRoomMessages">>, Args) ->
    get_room_messages(Ctx, Args).

-spec list_user_rooms(map(), map()) -> {ok, [{ok, jid:simple_bare_jid()}]}.
list_user_rooms(#{user := UserJID}, #{}) ->
    {ok, Rooms} = mod_muc_light_api:get_user_rooms(UserJID),
    {ok, [{ok, R} || R <- Rooms]}.

-spec list_room_users(map(), map()) -> {ok, [{ok, map()}]} | {error, resolver_error()}.
list_room_users(#{user := UserJID}, #{<<"room">> := RoomJID}) ->
    case mod_muc_light_api:get_room_aff(RoomJID, UserJID) of
        {ok, Affs} ->
            {ok, [make_ok_user(A) || A <- Affs]};
        Err ->
            make_error(Err, #{room => RoomJID})
    end.

-spec get_room_config(map(), map()) -> {ok, map()} | {error, resolver_error()}.
get_room_config(#{user := UserJID}, #{<<"room">> := RoomJID}) ->
    case mod_muc_light_api:get_room_info(RoomJID, UserJID) of
        {ok, Room} ->
            {ok, make_room(Room)};
        Err ->
            make_error(Err, #{room => RoomJID})
    end.

-spec get_room_messages(map(), map()) -> {ok, map()} | {error, resolver_error()}.
get_room_messages(#{user := UserJID}, #{<<"room">> := RoomJID, <<"pageSize">> := PageSize,
                                        <<"before">> := Before}) ->
    Before2 = null_to_undefined(Before),
    PageSize2 = page_size_or_max_limit(PageSize, 50),
    case mod_muc_light_api:get_room_messages(RoomJID, UserJID, PageSize2, Before2) of
        {ok, Rows} ->
            Maps = lists:map(fun mongoose_graphql_stanza_helper:row_to_map/1, Rows),
            {ok, #{<<"stanzas">> => Maps, <<"limit">> => PageSize2}};
        Err ->
            make_error(Err, #{room => RoomJID})
    end.

%% Helpers

null_to_undefined(null) -> undefined;
null_to_undefined(V) -> V.
