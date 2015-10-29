%%    @author Ricardo Gonçalves <tome.wave@gmail.com>
%%    @doc  
%%    An Erlang implementation of a Server Wide Logical Clock,
%%    in this case a Bitmapped Version Vector.
%%    @end  

-module('swc_node').
-author('Ricardo Gonçalves <tome.wave@gmail.com>').

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include_lib("include/swc.hrl").

%% API exports
-export([ new/0
        , ids/1
        , get/2
        , norm/1
        , values/1
        , add/2
        , merge/2
        , join/2
        , base/1
        , event/2
        , store_entry/3
        ]).

-export_type([bvv/0]).

%%====================================================================
%% API functions
%%====================================================================

%% @doc Constructs an empty BVV (an orddict in Erlang).
-spec new() -> bvv().
new() -> orddict:new().

%% @doc Returns all IDs from the entries in a BVV.
-spec ids(bvv()) -> [id()].
ids(B) ->
    orddict:fetch_keys(B).

%% @doc Returns the entry of a BVV associated with a given ID.
-spec get(id(), bvv()) -> entry().
get(K,B) ->
    case orddict:find(K,B) of
        error   -> {0,0};
        {ok, E} -> E
    end.

%% @doc Normalizes an entry pair, by removing dots and adding them to the base
%% if they are contiguous with the base.
-spec norm(entry()) -> entry().
norm({N,B}) ->
    case B rem 2 of
        0 -> {N,B};
        1 -> norm({N+1, B bsr 1})
    end.

%% @doc Normalizes all entries in the BVV, using norm/2.
-spec norm_bvv(bvv()) -> bvv().
norm_bvv(BVV) ->
    % normalize all entries
    FunMap = fun (_Id, E) -> norm(E) end,
    BVV1 = orddict:map(FunMap, BVV),
    % remove `{0,0}` entries
    FunFilter = fun (_Id, E) -> E =/= {0,0} end,
    orddict:filter(FunFilter, BVV1).

%% @doc Returns the sequence numbers for the dots represented by an entry.
-spec values(entry()) -> [counter()].
values({N,B}) ->
    lists:seq(1,N) ++ values_aux(N,B,[]).

%% @doc Returns the sequence numbers for the dots represented by a bitmap. It's
%% an auxiliary function used by values/1.
-spec values_aux(counter(), counter(), [counter()]) -> [counter()].
values_aux(_,0,L) -> L;
values_aux(N,B,L) ->
    M = N + 1,
    case B rem 2 of
        0 -> values_aux(M, B bsr 1, L);
        1 -> values_aux(M, B bsr 1, [ M | L ])
    end.

%% @doc Adds a dot (ID, Counter) to a BVV.
-spec add(bvv(), {id(), counter()}) -> bvv().
add(BVV, {Id, Counter}) ->
    Initial = add_aux({0,0}, Counter),
    Fun = fun (Entry) -> add_aux(Entry, Counter) end,
    orddict:update(Id, Fun, Initial, BVV).

%% @doc Adds a dot to a BVV entry, returning the normalized entry.
-spec add_aux(entry(), counter()) -> entry().
add_aux({N,B}, M) ->
    case N < M of
        false -> norm({N,B});
        true  -> M2 = B bor (1 bsl (M-N-1)),
                 norm({N,M2})
    end.

%% @doc Merges all entries from the two BVVs.
-spec merge(bvv(), bvv()) -> bvv().
merge(BVV1, BVV2) ->
    FunMerge = fun (_Id, E1, E2) -> join_aux(E1, E2) end,
    norm_bvv(orddict:merge(FunMerge, BVV1, BVV2)).

%% @doc Joins entries from BVV2 that are also IDs in BVV1, into BVV1.
-spec join(bvv(), bvv()) -> bvv().
join(BVV1, BVV2) ->
    % filter keys from BVV2 that are not in BVV1
    K1 = orddict:fetch_keys(BVV1),
    Pred = fun (Id,_E) -> lists:member(Id, K1) end,
    BVV2b = orddict:filter(Pred, BVV2),
    % merge BVV1 with filtered BVV2b
    FunMerge = fun (_Id, E1, E2) -> join_aux(E1, E2) end,
    norm_bvv(orddict:merge(FunMerge, BVV1, BVV2b)).

%% @doc Returns a (normalized) entry that results from the union of dots from
%% two other entries. Auxiliary function used by join/2.
-spec join_aux(entry(), entry()) -> entry().
join_aux({N1,B1}, {N2,B2}) ->
    case N1 >= N2 of
        true  -> {N1, B1 bor (B2 bsr (N1-N2))};
        false -> {N2, B2 bor (B1 bsr (N2-N1))}
    end.

%% @doc Takes and returns a BVV where in each entry, the bitmap is reset to zero.
-spec base(bvv()) -> bvv().
base(BVV) ->
    % normalize all entries
    BVV1 = norm_bvv(BVV),
    % remove all non-contiguous counters w.r.t the base
    Fun = fun (_Id, {N,_B}) -> {N,0} end,
    orddict:map(Fun, BVV1).

%% @doc Takes a BVV at node Id and returns a pair with sequence number for a new
%% event (dot) at node Id and the original BVV with the new dot added; this
%% function makes use of the invariant that the node BVV for node Id knows all
%% events generated at Id, i.e., the first component of the pair denotes the
%% last event, and the second component, the bitmap, is always zero.
-spec event(bvv(), id()) -> {counter(), bvv()}.
event(BVV, Id) ->
    % find the next counter for Id
    C = case orddict:find(Id, BVV) of
        % since nodes call event with their Id, their entry always matches {N,0}
        {ok, {N,0}} -> N + 1;
        error        -> 1
    end,
    % return the new counter and the updated BVV
    {C, add(BVV, {Id,C})}.

%% @doc Stores an Id-Entry pair in a BVV; if the id already exists, the 
%% associated entry is replaced by the new one.
store_entry(_Id, {0,0}, BVV) -> BVV;
store_entry(Id, Entry={N,0}, BVV) ->
    case orddict:find(Id, BVV) of
        {ok, {N2,_}} when N2 >= N   -> BVV;
        {ok, {N2,_}} when N2 <  N   -> orddict:store(Id, Entry, BVV);
        error                       -> orddict:store(Id, Entry, BVV)
    end.



%%===================================================================
%% EUnit tests
%%===================================================================

-ifdef(TEST).

norm_test() ->
    ?assertEqual( norm({5,3}), {7,0} ),
    ?assertEqual( norm({5,2}), {5,2} ),
    ?assertEqual( norm_bvv( [{"a",{0,0}}] ), [] ),
    ?assertEqual( norm_bvv( [{"a",{5,3}}] ), [{"a",{7,0}}] ).

values_test() ->
    ?assertEqual( lists:sort( values({0,0}) ), lists:sort( [] )),
    ?assertEqual( lists:sort( values({5,3}) ), lists:sort( [1,2,3,4,5,6,7] )),
    ?assertEqual( lists:sort( values({2,5}) ), lists:sort( [1,2,3,5] )).

add_test() ->
    ?assertEqual( add( [{"a",{5,3}}] , {"b",0} ), [{"a",{5,3}}, {"b",{0,0}}] ),
    ?assertEqual( add( [{"a",{5,3}}] , {"a",1} ), [{"a",{7,0}}] ),
    ?assertEqual( add( [{"a",{5,3}}] , {"a",8} ), [{"a",{8,0}}] ),
    ?assertEqual( add( [{"a",{5,3}}] , {"b",8} ), [{"a",{5,3}}, {"b",{0,128}}] ).

add_aux_test() ->
    ?assertEqual( add_aux({5,3}, 8), {8,0} ),
    ?assertEqual( add_aux({5,3}, 7), {7,0} ),
    ?assertEqual( add_aux({5,3}, 4), {7,0} ),
    ?assertEqual( add_aux({2,5}, 4), {5,0} ),
    ?assertEqual( add_aux({2,5}, 6), {3,6} ),
    ?assertEqual( add_aux({2,4}, 6), {2,12} ).

merge_test() ->
    ?assertEqual( merge( [{"a",{5,3}}] , [{"a",{2,4}}] ), [{"a",{7,0}}] ),
    ?assertEqual( merge( [{"a",{5,3}}] , [{"b",{2,4}}] ), [{"a",{7,0}}, {"b",{2,4}}] ),
    ?assertEqual( merge( [{"a",{5,3}}, {"c",{1,2}}] , [{"b",{2,4}}, {"d",{5,3}}] ),
                  [{"a",{7,0}}, {"b",{2,4}}, {"c",{1,2}}, {"d",{7,0}}] ),
    ?assertEqual( merge( [{"a",{5,3}}, {"c",{1,2}}] , [{"b",{2,4}}, {"c",{5,3}}] ), 
                  [{"a",{7,0}}, {"b",{2,4}}, {"c",{7,0}}]).

join_test() ->
    ?assertEqual( join( [{"a",{5,3}}] , [{"a",{2,4}}] ), [{"a",{7,0}}] ),
    ?assertEqual( join( [{"a",{5,3}}] , [{"b",{2,4}}] ), [{"a",{7,0}}] ),
    ?assertEqual( join( [{"a",{5,3}}, {"c",{1,2}}] , [{"b",{2,4}}, {"d",{5,3}}] ), [{"a",{7,0}}, {"c",{1,2}}] ),
    ?assertEqual( join( [{"a",{5,3}}, {"c",{1,2}}] , [{"b",{2,4}}, {"c",{5,3}}] ), [{"a",{7,0}}, {"c",{7,0}}] ).

join_aux_test() ->
    ?assertEqual( join_aux({5,3}, {2,4}), join_aux({2,4}, {5,3}) ),
    ?assertEqual( join_aux({5,3}, {2,4}), {5,3} ),
    ?assertEqual( join_aux({2,2}, {3,0}), {3,1} ),
    ?assertEqual( join_aux({2,2}, {3,1}), {3,1} ),
    ?assertEqual( join_aux({2,2}, {3,2}), {3,3} ),
    ?assertEqual( join_aux({2,2}, {3,4}), {3,5} ),
    ?assertEqual( join_aux({3,2}, {1,4}), {3,3} ),
    ?assertEqual( join_aux({3,2}, {1,16}), {3,6} ).

base_test() ->
    ?assertEqual( base( [{"a",{5,3}}] ), [{"a",{7,0}}] ),
    ?assertEqual( base( [{"a",{5,2}}] ), [{"a",{5,0}}] ),
    ?assertEqual( base( [{"a",{5,3}}, {"b",{2,4}}, {"c",{1,2}}, {"d",{5,2}}] ), 
                        [{"a",{7,0}}, {"b",{2,0}}, {"c",{1,0}}, {"d",{5,0}}] ).


event_test() ->
    ?assertEqual( event( [{"a",{7,0}}] , "a"), {8, [{"a",{8,0}}]} ),
    ?assertEqual( event( [{"a",{5,3}}] , "b"), {1, [{"a",{5,3}}, {"b",{1,0}}]} ),
    ?assertEqual( event( [{"a",{5,3}}, {"b",{2,0}}, {"c",{1,2}}, {"d",{5,3}}] , "b"), 
                        {3, [{"a",{5,3}}, {"b",{3,0}}, {"c",{1,2}}, {"d",{5,3}}]} ).


store_entry_test() ->
    ?assertEqual( store_entry( "a", {0,0}, [{"a",{7,0}}]), [{"a",{7,0}}] ),
    ?assertEqual( store_entry( "b", {0,0}, [{"a",{7,0}}]), [{"a",{7,0}}] ),
    ?assertEqual( store_entry( "a", {9,0}, [{"a",{7,0}}]), [{"a",{9,0}}] ),
    ?assertEqual( store_entry( "a", {90,0}, [{"a",{7,1234}}]), [{"a",{90,0}}] ),
    ?assertEqual( store_entry( "b", {9,0}, [{"a",{7,0}}]), [{"a",{7,0}}, {"b",{9,0}}] ).

-endif.
