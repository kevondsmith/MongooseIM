-module(mongoose_graphql_muc_light_helper).

-export([make_room/1, make_ok_user/1, blocking_item_to_map/1,
         prepare_blocking_items/1, page_size_or_max_limit/2]).

-spec page_size_or_max_limit(null | integer(), integer()) -> integer().
page_size_or_max_limit(null, MaxLimit) ->
    MaxLimit;
page_size_or_max_limit(PageSize, MaxLimit) when PageSize > MaxLimit ->
    MaxLimit;
page_size_or_max_limit(PageSize, _MaxLimit) ->
    PageSize.

-spec make_room(mod_muc_light_api:room()) -> map().
make_room(#{jid := JID, name := Name, subject := Subject, aff_users := Users}) ->
    Participants = lists:map(fun make_ok_user/1, Users),
    #{<<"jid">> => JID, <<"name">> => Name, <<"subject">> => Subject,
      <<"participants">> => Participants}.

make_ok_user({JID, Aff}) ->
    {ok, #{<<"jid">> => JID, <<"affiliation">> => Aff}}.

prepare_blocking_items(Items) ->
    [{What, Action, jid:to_lus(Who)} || #{<<"entity">> := Who, <<"entityType">> := What,
                                          <<"action">> := Action} <- Items].

blocking_item_to_map({What, Action, Who}) ->
    {ok, #{<<"entityType">> => What, <<"action">> => Action, <<"entity">> => Who}}.
