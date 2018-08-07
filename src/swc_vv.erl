%%    @author Ricardo Gonçalves <tome.wave@gmail.com>
%%    @doc
%%    An Erlang implementation of a Version Vector.
%%    @end

-module('swc_vv').
-author('Ricardo Gonçalves <tome.wave@gmail.com>').

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include_lib("swc/include/swc.hrl").

%% API exports
-export([ new/0
        , ids/1
        , is_key/2
        , get/2
        , join/2
        , left_join/2
        , filter/2
        , add/2
        , min/1
        , min_key/1
        , reset_counters/1
        , delete_key/2
        ]).

-export_type([vv/0]).

-import(swc_node, [map_merge/3]).

%% @doc Initializes a new empty version vector.
-spec new() -> vv().
new() -> maps:new().

%% @doc Returns all the keys (ids) from a VV.
-spec ids(vv()) -> [id()].
ids(V) ->
    maps:keys(V).

-spec is_key(vv(), id()) -> boolean().
is_key(VV, Id) ->
    maps:is_key(Id, VV).

%% @doc Returns the counter associated with an id K. If the key is not present
%% in the VV, it returns 0.
-spec get(id(), vv()) -> counter().
get(K,V) ->
    case maps:find(K,V) of
        error   -> 0;
        {ok, C} -> C
    end.

%% @doc Merges or joins two VVs, taking the maximum counter if an entry is
%% present in both VVs.
-spec join(vv(), vv()) -> vv().
join(A,B) ->
    FunMerge = fun (_Id, C1, C2) -> max(C1, C2) end,
    map_merge(FunMerge, A, B).

%% @doc Left joins two VVs, taking the maximum counter if an entry is
%% present in both VVs, and also taking the entrie in A and not in B.
-spec left_join(vv(), vv()) -> vv().
left_join(A,B) ->
    PeersA = maps:keys(A),
    FunFilter = fun (Id,_) -> lists:member(Id, PeersA) end,
    B2 = maps:filter(FunFilter, B),
    map_merge(fun (_,C1,C2) -> max(C1,C2) end, A, B2).


%% @doc It applies some boolean function F to all entries in the VV, removing
%% those that return False when F is used.
-spec filter(fun((id(), counter()) -> boolean()), vv()) -> vv().
filter(F,V) ->
    maps:filter(F, V).

%% @doc Adds an entry {Id, Counter} to the VV, performing the maximum between
%% both counters, if the entry already exists.
-spec add(vv(), {id(), counter()}) -> vv().
add(VV, {Id, Counter}) ->
    Fun = fun (C) -> max(C, Counter) end,
    maps:update_with(Id, Fun, Counter, VV).

%% @doc Returns the minimum counters from all the entries in the VV.
-spec min(vv()) -> counter().
min(VV) ->
    Keys = maps:keys(VV),
    Values = [maps:get(Key, VV) || Key <- Keys],
    lists:min(Values).

%% @doc Returns the key with the minimum counter associated.
-spec min_key(vv()) -> id().
min_key(VV) ->
    Fun = fun (Key, Value, undefined) -> {Key, Value};
              (Key, Value, {MKey, MVal}) when Value < MVal -> {Key, Value};
              (Key, Value, Acc) -> Acc
          end,
    {MinKey, _MinValue} = maps:fold(Fun, undefined, VV),
    MinKey.

%% @doc Returns the VV with the same entries, but with counters at zero.
-spec reset_counters(vv()) -> vv().
reset_counters(VV) ->
    maps:map(fun (_Id,_Counter) -> 0 end, VV).


%% @doc Returns the VV without the entry with a given key.
-spec delete_key(vv(), id()) -> vv().
delete_key(VV, Key) ->
    maps:remove(Key, VV).

%% ===================================================================
%% EUnit tests
%% ===================================================================

-ifdef(TEST).

min_key_test() ->
    A0 = #{"a" => 2},
    A1 = #{"a" => 2, "b" => 4, "c" => 4},
    A2 = #{"a" => 5, "b" => 4, "c" => 4},
    A3 = #{"a" => 4, "b" => 4, "c" => 4},
    A4 = #{"a" => 5, "b" => 14,"c" => 4},
    ?assertEqual( "a", min_key(A0)),
    ?assertEqual( "a", min_key(A1)),
    ?assertEqual( "b", min_key(A2)),
    ?assertEqual( "a", min_key(A3)),
    ?assertEqual( "c", min_key(A4)),
    ok.

reset_counters_test() ->
    E = #{},
    A0 = #{"a" => 2},
    A1 = #{"a" => 2, "b" => 4, "c" => 4},
    ?assertEqual(reset_counters(E), #{}),
    ?assertEqual(reset_counters(A0), #{"a" => 0}),
    ?assertEqual(reset_counters(A1), #{"a" => 0, "b" => 0, "c" => 0}),
    ok.

delete_key_test() ->
    E = #{},
    A0 = #{"a" => 2},
    A1 = #{"a" => 2, "b" => 4, "c" => 4},
    ?assertEqual(delete_key(E, "a"), #{}),
    ?assertEqual(delete_key(A0, "a"), #{}),
    ?assertEqual(delete_key(A0, "b"), #{"a" => 2}),
    ?assertEqual(delete_key(A1, "a"), #{"b" => 4, "c" => 4}),
    ok.

join_test() ->
    A0 = #{"a" => 4},
    A1 = #{"a" => 2, "b" => 4, "c" => 4},
    A2 = #{"a" => 1, "z" => 10},
    ?assertEqual(join(A0,A1), #{"a" => 4, "b" => 4, "c" => 4}),
    ?assertEqual(left_join(A0,A1), A0),
    ?assertEqual(left_join(A0,A2), A0).



-endif.
