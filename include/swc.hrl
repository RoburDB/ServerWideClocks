
-type vv()      :: #{Key :: id() => Entry :: counter()}.

-type dcc()     :: {dots(), vv()}.

-type bvv()     :: #{Key :: id() => Entry :: entry()}.

-type key_matrix()  :: [{Node :: id(), DotKey :: [{counter(), id()}]}]. % orddict

-type vv_matrix() :: {map(), map()}.

-type dots()    :: #{Dot :: dot() => Value:: value()}.
-type dot()     :: {id(), counter()}.
-type entry()   :: {counter(), counter()}.
-type id()      :: term().
-type counter() :: non_neg_integer().
-type value()   :: any().
