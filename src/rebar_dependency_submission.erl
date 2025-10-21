-module(rebar_dependency_submission).

-export([init/1]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    {ok, State1} = rebar_dependency_submission_prv:init(State),
    {ok, State1}.
