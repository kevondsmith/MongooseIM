-module(mongoose_graphql_scalar).
-export([input/2, output/2]).
-ignore_xref([input/2, output/2]).

-spec input(Type, Value) -> {ok, Coerced} | {error, Reason}
  when
    Type :: binary(),
    Value :: binary(),
    Coerced :: any(),
    Reason :: term().
input(<<"DateTime">>, DT) -> binary_to_microseconds(DT);
input(<<"Stanza">>, Value) -> exml:parse(Value);
input(<<"JID">>, Jid) -> jid_from_binary(Jid);
input(<<"NonEmptyString">>, Value) -> non_empty_string_to_binary(Value);
input(Ty, V) ->
    error_logger:info_report({coercing_generic_scalar, Ty, V}),
    {ok, V}.

-spec output(Type, Value) -> {ok, Coerced} | {error, Reason}
  when
    Type :: binary(),
    Value :: binary(),
    Coerced :: any(),
    Reason :: term().
output(<<"DateTime">>, DT) -> {ok, microseconds_to_binary(DT)};
output(<<"Stanza">>, Elem) -> {ok, exml:to_binary(Elem)};
output(<<"JID">>, Jid) -> {ok, jid:to_binary(Jid)};
output(<<"NonEmptyString">>, Value) -> binary_to_non_empty_string(Value);
output(Ty, V) ->
    error_logger:info_report({output_generic_scalar, Ty, V}),
    {ok, V}.

jid_from_binary(Value) ->
    case jid:from_binary(Value) of
        error ->
            {error, failed_to_parse_jid};
        Jid ->
            {ok, Jid}
    end.

binary_to_microseconds(DT) ->
    case mod_mam_utils:maybe_microseconds(DT) of
        undefined ->
            {error, failed_to_parse_datetime};
        Microseconds ->
            {ok, Microseconds}
    end.

non_empty_string_to_binary(<<>>) ->
    {error, "Given string is empty"};
non_empty_string_to_binary(String) ->
    {ok, String}.

binary_to_non_empty_string(<<>>) ->
    {error, "Empty binary cannot be converted to NonEmptyString"};
binary_to_non_empty_string(Val) ->
    {ok, Val}.

microseconds_to_binary(Microseconds) ->
    Opts = [{offset, "Z"}, {unit, microsecond}],
    list_to_binary(calendar:system_time_to_rfc3339(Microseconds, Opts)).