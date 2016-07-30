%%%-------------------------------------------------------------------
%%% @author Ricardo Gonçalves <tome.wave@gmail.com>
%%% @copyright (C) 2016, Ricardo Gonçalves
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(swc_watermark).

-author('Ricardo Gonçalves <tome.wave@gmail.com>').

-compile({no_auto_import,[min/2]}).

-include_lib("swc/include/swc.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% API exports
-export([ new/0
        , add_peer/3
        , update_peer/3
        , update_cell/4
        , min/2
        , peers/1
        , get/3
        , reset_counters/1
        , delete_peer/2
        ]).

-spec new() -> vv_matrix().
new() ->
    orddict:new().


-spec add_peer(vv_matrix(), id(), [id()]) -> vv_matrix().
add_peer(M, NewPeer, ItsPeers) ->
    % CurrentPeers = orddict:fetch_keys(M),
    NewEntry = lists:foldl(
                 fun (Id, Acc) -> swc_vv:add(Acc, {Id,0}) end,
                 swc_vv:new(),
                 [NewPeer | ItsPeers]),
    orddict:store(NewPeer, NewEntry, M).


-spec update_peer(vv_matrix(), id(), bvv()) -> vv_matrix().
update_peer(M, EntryId, NodeClock) ->
    NodeClockBase = orddict:map(fun (_,{B,_}) -> B end, NodeClock),
    orddict:map(fun (Id, OldVV) ->
                    case swc_vv:is_key(OldVV, EntryId) of
                        false -> OldVV;
                        true  ->
                            Counter = swc_vv:get(Id, NodeClockBase),
                            swc_vv:add(OldVV, {EntryId, Counter})
                    end
                end,
                M).


-spec update_cell(vv_matrix(), id(), id(), counter()) -> vv_matrix().
update_cell(M, EntryId, PeerId, Counter) ->
    Top = {PeerId, Counter},
    orddict:update(
        EntryId,
        fun (OldVV) -> swc_vv:add(OldVV, Top) end,
        swc_vv:add(swc_vv:new(), Top),
        M).

-spec min(vv_matrix(), id()) -> counter().
min(M, Id) ->
    case orddict:find(Id, M) of
        error -> 0;
        {ok, VV} -> swc_vv:min(VV)
    end.

-spec peers(vv_matrix()) -> [id()].
peers(M) ->
    orddict:fetch_keys(M).

-spec get(vv_matrix(), id(), id()) -> counter().
get(M, P1, P2) ->
    case orddict:find(P1, M) of
        error -> 0;
        {ok, VV} -> swc_vv:get(P2, VV)
    end.


-spec reset_counters(vv_matrix()) -> vv_matrix().
reset_counters(M) ->
    orddict:map(fun (_Id,VV) -> swc_vv:reset_counters(VV) end, M).

-spec delete_peer(vv_matrix(), id()) -> vv_matrix().
delete_peer(M, Id) ->
    M2 = orddict:erase(Id, M),
    orddict:map(fun (_Id,VV) -> swc_vv:delete_key(VV, Id) end, M2).


%%===================================================================
%% EUnit tests
%%===================================================================

-ifdef(TEST).

update_test() ->
    C1 = [{"a",{12,0}}, {"b",{7,0}}, {"c",{4,0}}, {"d",{5,0}}, {"e",{5,0}}, {"f",{7,10}}, {"g",{5,10}}, {"h",{5,14}}],
    C2 = [{"a",{5,14}}, {"b",{5,14}}, {"c",{50,14}}, {"d",{5,14}}, {"e",{15,0}}, {"f",{5,14}}, {"g",{7,10}}, {"h",{7,10}}],
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    M5 = update_cell(M4, "c", "c",15),
    M6 = update_peer(M5, "c", C1),
    M7 = update_peer(M5, "c", C2),
    M8 = update_peer(M5, "a", C1),
    M9 = update_peer(M5, "a", C2),
    M10 = update_peer(M5, "b", C1),
    M11 = update_peer(M5, "b", C2),
    ?assertEqual( M1,  [{"a",[{"b",4}]}]),
    ?assertEqual( M2,  [{"a",[{"b",4}, {"c",10}]}]),
    ?assertEqual( M3,  [{"a",[{"b",4}, {"c",10}]},    {"c",[{"c",2}]}]),
    ?assertEqual( M4,  [{"a",[{"b",4}, {"c",10}]},    {"c",[{"c",20}]}]),
    ?assertEqual( M4,  M5),
    ?assertEqual( M6,  [{"a",[{"b",4},  {"c",12}]},   {"c",[{"c",20}]}]),
    ?assertEqual( M7,  [{"a",[{"b",4},  {"c",10}]},   {"c",[{"c",50}]}]),
    ?assertEqual( M8,  [{"a",[{"b",4},  {"c",10}]},   {"c",[{"c",20}]}]),
    ?assertEqual( M9,  [{"a",[{"b",4},  {"c",10}]},   {"c",[{"c",20}]}]),
    ?assertEqual( M10, [{"a",[{"b",12}, {"c",10}]},   {"c",[{"c",20}]}]),
    ?assertEqual( M11, [{"a",[{"b",5},  {"c",10}]},   {"c",[{"c",20}]}]).

add_peers_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual( add_peer(add_peer(M, "z", ["b","a"]), "l", ["z","y"]),
                  add_peer(add_peer(M, "l", ["y","z"]), "z", ["a","b"])),
    ?assertEqual( add_peer(M, "z",["a","b"]),    [{"z",[{"a",0},{"b",0},{"z",0}]}]),
    ?assertEqual( add_peer(M4, "z",["t2","t1"]), [{"a",[{"b",4}, {"c",10}]}, {"c",[{"c",20}]}, {"z",[{"t1",0},{"t2",0},{"z",0}]}]).

min_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual( min(M, "a"), 0),
    ?assertEqual( min(M1, "a"), 4),
    ?assertEqual( min(M1, "b"), 0),
    ?assertEqual( min(M4, "a"), 4),
    ?assertEqual( min(M4, "c"), 20),
    ?assertEqual( min(M4, "b"), 0).

peers_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    M5 = update_cell(M4, "c", "c",15),
    ?assertEqual( peers(M), []),
    ?assertEqual( peers(M1), ["a"]),
    ?assertEqual( peers(M5), ["a", "c"]).


get_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual( get(M, "a", "a"), 0),
    ?assertEqual( get(M1, "a", "a"), 0),
    ?assertEqual( get(M1, "b", "a"), 0),
    ?assertEqual( get(M4, "c", "c"), 20),
    ?assertEqual( get(M4, "a", "c"), 10).

reset_counters_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual( reset_counters(M), M),
    ?assertEqual( reset_counters(M1), [{"a",[{"b",0}]}]),
    ?assertEqual( reset_counters(M2), [{"a",[{"b",0}, {"c",0}]}]),
    ?assertEqual( reset_counters(M3), [{"a",[{"b",0}, {"c",0}]}, {"c",[{"c",0}]}]),
    ?assertEqual( reset_counters(M4), [{"a",[{"b",0}, {"c",0}]}, {"c",[{"c",0}]}]).

delete_peer_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual( delete_peer(M1, "a"), []),
    ?assertEqual( delete_peer(M1, "b"), [{"a",[]}]),
    ?assertEqual( delete_peer(M1, "c"), [{"a",[{"b",4}]}]),
    ?assertEqual( delete_peer(M4, "a"), [{"c",[{"c",20}]}]),
    ?assertEqual( delete_peer(M4, "c"), [{"a",[{"b",4}]}]).

-endif.

