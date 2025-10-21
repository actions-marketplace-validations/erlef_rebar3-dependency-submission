-module(rebar_dependency_submission_prv).

-behaviour(provider).
-behaviour(erl_error).

%% provider callbacks
-export([init/1, do/1, format_error/1]).

%% erl_error callback
-export([format_error/2]).

-define(PROVIDER, dependency_submission).
-define(DEPS, [app_discovery]).

%% ===================================================================
%% Public API
%% ===================================================================
-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
        % The 'user friendly' name of the task
        {name, ?PROVIDER},
        % The module implementation of the task
        {module, ?MODULE},
        % The task can be run by the user, always true
        {bare, true},
        % The list of dependencies
        {deps, ?DEPS},
        % How to use the plugin
        {example, "rebar3 dependency_submission"},
        % list of options understood by the plugin
        {opts, []},
        {short_desc, "Submits dependency information to GitHub's API"},
        {desc, "Submits dependency information to GitHub's API"}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()} | {error, {module(), any()}}.
do(State) ->
    io:format("Submitting dependency information to GitHub's API...~n"),
    {ok, State}.
