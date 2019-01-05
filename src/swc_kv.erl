%%    @author Ricardo Gonçalves <tome.wave@gmail.com>
%%    @doc
%%    An Erlang implementation of Key-Value Logical Clock,
%%    in this case a Dotted Causal Container.
%%    @en

-module('swc_kv').
-author('Ricardo Gonçalves <tome.wave@gmail.com>').

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include_lib("swc/include/swc.hrl").

%% API exports
-export([ new/0
        , values/1
        , context/1
        , sync/2
        , discard/2
        , strip/2
        , fill/2
        , fill/3
        , add/2
        , add/3
        ]).

-export_type([dcc/0]).

-import(swc_node, [map_merge/3]).


%% @doc Constructs a new clock set without causal history,
%% and receives one value that goes to the anonymous list.
-spec new() -> dcc().
new() -> {maps:new(), swc_vv:new()}.


%% @doc Returns the set of values held in the DCC.
-spec values(dcc()) -> [value()].
values({D,_V}) ->
    maps:values(D).


%% @doc Returns the causal context of a DCC, which is representable as a
%% Version Vector.
-spec context(dcc()) -> vv().
context({_D,V}) -> V.


%% @doc Performs the synchronization of two DCCs; it discards versions (
%% {dot,value} pairs) made obsolete by the other DCC, by preserving the
%% versions that are present in both, together with the versions in either of
%% them that are not covered by the relevant entry in the other's causal
%% context; the causal context is obtained by a standard version vector merge
%% function (performing the pointwise maximum).
-spec sync(dcc(), dcc()) -> dcc().
sync({D1,V1}, {D2,V2}) ->
    % merge the two DCCs
    Dm = maps:merge(D1, D2),
    % filter the outdated versions
    FunFilter = fun ({Id,Counter}, _Val) -> Counter > min(swc_vv:get(Id,V1), swc_vv:get(Id,V2)) end,
    Df = maps:filter(FunFilter, Dm),
    % calculate versions that are in both DCCs
    K1 = maps:keys(D1),
    Db = maps:with(K1, D2),
    % add these versions to the filtered list of versions
    D = maps:merge(Df, Db),
    % return the new list of version and the merged VVs
    {D, swc_vv:join(V1,V2)}.

%% @doc Adds the dots corresponding to each version in the DCC to the BVV; this
%% is accomplished by using the standard fold higher-order function, passing
%% the function swc_node:add/2 defined over BVV and dots, the BVV, and the list of
%% dots in the DCC.
-spec add(bvv(), dcc()) -> bvv().
add(BVV, {Versions,_VV}) ->
    Dots = maps:keys(Versions),
    lists:foldl(fun(Dot,Acc) -> swc_node:add(Acc,Dot) end, BVV, Dots).

%% @doc This function is to be used at node I after dcc:discard/2, and adds a
%% mapping, from the Dot (I, N) (which should be obtained by previously applying
%% swc_node:event/2 to the BVV at node I) to the Value, to the DCC, and also advances
%% the i component of the VV in the DCC to N.
-spec add(dcc(), {id(),counter()}, value()) -> dcc().
add({D,V}, Dot, Value) ->
    {maps:put(Dot, Value, D), swc_vv:add(V,Dot)}.

%% @doc It discards versions in DCC {D,V} which are made obsolete by a causal
%% context (a version vector) C, and also merges C into DCC causal context V.
-spec discard(dcc(), vv()) -> dcc().
discard({D,V}, C) ->
    FunFilter = fun ({Id,Counter}, _Val) -> Counter > swc_vv:get(Id,C) end,
    {maps:filter(FunFilter, D), swc_vv:join(V,C)}.


%% @doc It discards all entries from the version vector V in the DCC that are
%% covered by the corresponding base component of the BVV B; only entries with
%% greater sequence numbers are kept. The idea is that DCCs are stored after
%% being stripped of their causality information that is already present in the
%% node clock BVV.
-spec strip(dcc(), bvv()) -> dcc().
strip({D,V}, B) ->
    FunFilter =
        fun (Id,Counter) ->
            {Base,_Dots} = swc_node:get(Id,B),
            Counter > Base
        end,
    {D, swc_vv:filter(FunFilter, V)}.


%% @doc Function fill adds back causality information to a stripped DCC, before
%% any operation is performed.
-spec fill(dcc(), bvv()) -> dcc().
fill({D,VV}, BVV) ->
    FunFold =
        fun(Id, Acc) ->
            {Base,_D} = swc_node:get(Id,BVV),
            swc_vv:add(Acc,{Id,Base})
        end,
    {D, lists:foldl(FunFold, VV, swc_node:ids(BVV))}.


%% @doc Same as fill/2 but only adds entries that are elements of a list of Ids,
%% instead of adding all entries in the BVV.
-spec fill(dcc(), bvv(), [id()]) -> dcc().
fill({D,VV}, BVV, Ids) ->
    % only consider ids that belong to both the list of ids received and the BVV
    Ids2 = sets:to_list(sets:intersection(
            sets:from_list(swc_node:ids(BVV)),
            sets:from_list(Ids))),
    FunFold =
        fun(Id, Acc) ->
            {Base,_D} = swc_node:get(Id,BVV),
            swc_vv:add(Acc,{Id,Base})
        end,
    {D, lists:foldl(FunFold, VV, Ids2)}.




%% ===================================================================
%% EUnit tests
%% ===================================================================

-ifdef(TEST).

d1() -> { #{{"a",8} => "red", {"b",2} => "green"} , #{} }.
d2() -> { #{} , #{"a" => 4, "b" => 20} }.
d3() -> { #{{"a",1} => "black", {"a",3} => "red", {"b",1} => "green", {"b",2} => "green"} ,
          #{"a" => 4, "b" => 7} }.
d4() -> { #{{"a",2} => "gray", {"a",3} => "red", {"a",5} => "red", {"b",2} => "green"} ,
          #{"a" => 5, "b" => 5} }.
d5() -> { #{{"a",5} => "gray"} , #{"a" => 5, "b" => 5, "c" => 4} }.


values_test() ->
    ?assertEqual( values(d1()), ["red","green"]),
    ?assertEqual( values(d2()), []).

context_test() ->
    ?assertEqual( context(d1()), #{}),
    ?assertEqual( context(d2()), #{"a" => 4, "b" => 20} ).

sync_test() ->
    D34 = { #{{"a",3} => "red", {"a",5} => "red", {"b",2} => "green"},
            #{"a" => 5, "b" => 7} },
    ?assertEqual( sync(d3(), d3()), d3()),
    ?assertEqual( sync(d4(), d4()), d4()),
    ?assertEqual( sync(d3(), d4()), D34).

add2_test() ->
    ?assertEqual( add(#{"a" => {5,3}}, d1()) , #{"a" => {8,0}, "b" => {0,2}}).

discard_test() ->
    ?assertEqual( discard(d3(), #{} ) , d3()),
    ?assertEqual( discard(d3(), #{"a" => 2, "b" => 15, "c" => 15} ),
                  { #{{"a",3} => "red"} , #{"a" => 4, "b" => 15, "c" => 15} } ),
    ?assertEqual( discard(d3(), #{"a" => 3, "b" => 15, "c" => 15} ),
                  { #{} , #{"a" => 4, "b" => 15, "c" => 15} }).

strip_test() ->
    ?assertEqual( strip(d5(), #{"a"=> {4,4}} ) , d5()),
    ?assertEqual( strip(d5(), #{"a"=> {5,0}} ) , { #{{"a",5} => "gray"} , #{"b" => 5, "c" => 4} }),
    ?assertEqual( strip(d5(), #{"a"=> {15,0}} ) , { #{{"a",5} => "gray"} , #{"b" => 5, "c" => 4} }),
    ?assertEqual( strip(d5(), #{"a"=> {15,4}, "b" => {1,2}} ) , { #{{"a",5} => "gray"} , #{"b" => 5, "c" => 4} }),
    ?assertEqual( strip(d5(), #{"b"=> {15,4}, "c" => {1,2}} ) , { #{{"a",5} => "gray"} , #{"a" => 5, "c" => 4} }),
    ?assertEqual( strip(d5(), #{"a"=> {15,4}, "b" =>{15,4}, "c" => {5,2}} ) , { #{{"a",5} => "gray"} , #{} }).

fill_test() ->
    ?assertEqual( fill(d5(), #{"a" => {4,4}} ) , d5()),
    ?assertEqual( fill(d5(), #{"a" => {5,0}} ) , d5()),
    ?assertEqual( fill(d5(), #{"a" => {6,0}} ) , { #{{"a",5} => "gray"} , #{"a" => 6, "b" => 5, "c" => 4} }),
    ?assertEqual( fill(d5(), #{"a" => {15,12}} ) , { #{{"a",5} => "gray"} , #{"a" => 15,"b" => 5, "c" => 4} }),
    ?assertEqual( fill(d5(), #{"b" => {15,12}} ) , { #{{"a",5} => "gray"} , #{"a" => 5, "b" => 15,"c" => 4} }),
    ?assertEqual( fill(d5(), #{"d" => {15,12}} ) , { #{{"a",5} => "gray"} , #{"a" => 5, "b" => 5, "c" => 4, "d" => 15} }),
    ?assertEqual( fill(d5(), #{"a" => {9,6}, "d" => {15,12}} ) , { #{{"a",5} => "gray"}, #{"a" => 9, "b" => 5, "c" => 4, "d" => 15}}),
    ?assertEqual( fill(d5(), #{"a" => {9,6}, "d" => {15,12}}, ["a"]) , { #{{"a",5} => "gray"}, #{"a" => 9, "b" => 5, "c" => 4}}),
    ?assertEqual( fill(d5(), #{"a" => {9,6}, "d" => {15,12}}, ["b","a"]) , { #{{"a",5} => "gray"}, #{"a" => 9, "b" => 5, "c" => 4}}),
    ?assertEqual( fill(d5(), #{"a" => {9,6}, "d" => {15,12}}, ["d","a"]) , { #{{"a",5} => "gray"}, #{"a" => 9, "b" => 5, "c" => 4, "d" => 15}}),
    ?assertEqual( fill(d5(), #{"a" => {9,6}, "d" => {15,12}}, ["b"]) , d5()),
    ?assertEqual( fill(d5(), #{"a" => {9,6}, "d" => {15,12}}, ["f"]) , d5()).

add3_test() ->
    ?assertEqual( add(d1(),{"a",11}, "purple") , { #{{"a",8} => "red", {"a",11} => "purple", {"b",2} => "green"} , #{"a" => 11} } ),
    ?assertEqual( add(d2(),{"b",11}, "purple") , { #{{"b",11} => "purple"} , #{"a" => 4, "b" => 20} } ).

-endif.
