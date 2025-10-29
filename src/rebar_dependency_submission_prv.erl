-module(rebar_dependency_submission_prv).

-behaviour(provider).
-behaviour(erl_error).

%% provider callbacks
-export([init/1, do/1, format_error/1]).

%% erl_error callback
-export([format_error/2]).

-include("records.hrl").

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
    Lock = rebar_state:lock(State),
    [ProjectApp | _] = rebar_state:project_apps(State),
    {ok, PluginVsn} = application:get_key(rebar_dependency_submission, vsn),
    Snapshot = #{
        version => to_binary(rebar_app_info:vsn(ProjectApp)),
        job => #{
            id => getenv("GITHUB_RUN_ID"),
            correlator => <<(getenv("GITHUB_WORKFLOW"))/binary, "_", (getenv("GITHUB_JOB"))/binary>>
        },
        sha => getenv("GITHUB_SHA"),
        ref => getenv("GITHUB_REF"),
        detector => #{
            name => ~"rebar",
            version => to_binary(PluginVsn),
            url => ~"https://github.com/kivra/rebar-dependency-submission"
        },
        scanned => calendar:system_time_to_rfc3339(erlang:system_time(millisecond), [
            {offset, "Z"}, {unit, millisecond}, {return, binary}
        ]),
        manifests => #{
            ~"rebar.lock" => #{
                name => ~"rebar.lock",
                file => #{
                    source_location => ~"rebar.lock"
                },
                resolved => maps:from_list([resolve_dependency(Dep) || Dep <- Lock])
            }
        }
    },
    #resource{state = #{base_config := Config}} = lists:keyfind(
        pkg, #resource.type, rebar_state:resources(State)
    ),
    Headers = #{
        ~"Accept" => ~"application/vnd.github+json",
        ~"Authorization" => <<"Bearer ", (getenv("GITHUB_TOKEN"))/binary>>,
        ~"X-GitHub-Api-Version" => ~"2022-11-28"
    },
    Body = {~"application/json", iolist_to_binary(json:encode(Snapshot))},
    URL =
        <<
            (getenv("GITHUB_API_URL", "https://api.github.com"))/binary,
            "/repos/",
            (getenv("GITHUB_REPOSITORY"))/binary,
            "/dependency-graph/snapshots"
        >>,
    r3_hex_http:request(Config, post, URL, Headers, Body),
    {ok, State}.

-spec format_error(any()) -> iolist().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

format_error(badarg, [{?MODULE, _Function, _Arguments, Info} | _StackTrace]) ->
    case proplists:get_value(error_info, Info, #{}) of
        #{cause := ErrorMap} -> ErrorMap;
        _ -> #{}
    end.

-spec resolve_dependency(rebar_app_info:t()) -> {Name, ResolvedDependency} when
    Name :: binary(),
    ResolvedDependency :: #{
        package_url := binary(),
        relationship := binary(),
        scope := binary(),
        dependencies := [binary()]
    }.
resolve_dependency(AppInfo) ->
    Source = rebar_app_info:source(AppInfo),
    Purl1 =
        case to_purl(Source) of
            {ok, #purl{} = Purl0} ->
                Purl0;
            {error, Reason} ->
                error(badarg, [AppInfo], {error_info, #{cause => #{1 => Reason}}})
        end,
    RuntimeDependencies = ordsets:from_list(
        rebar_app_info:applications(AppInfo) ++
            rebar_app_info:included_applications(AppInfo) ++
            rebar_app_info:optional_applications(AppInfo)
    ),
    ResolvedDependency = #{
        package_url => to_binary(purl:to_binary(Purl1)),
        relationship =>
            case rebar_app_info:dep_level(AppInfo) of
                0 -> ~"direct";
                _ -> ~"indirect"
            end,
        scope =>
            case ordsets:is_element(rebar_app_info:name(AppInfo), RuntimeDependencies) of
                true -> ~"runtime";
                false -> ~"development"
            end,
        dependencies => rebar_app_info:deps(AppInfo)
    },
    {Purl1#purl.name, ResolvedDependency}.

to_purl(#pkg{name = Name, version = Version}) ->
    purl:from_resource_uri(<<"https://hex.pm/packages/", Name/binary, "/", Version/binary>>);
to_purl(#git{repo = Repo, ref = {ref, Ref}}) ->
    purl:from_resource_uri(Repo, to_binary(Ref));
to_purl(#git_subdir{repo = Repo, ref = {ref, Ref}, subdir = SubPath0}) ->
    maybe
        SubPath1 = binary:split(to_binary(SubPath0), ~"/", [trim_all, global]),
        {ok, Purl} ?= purl:from_resource_uri(Repo, to_binary(Ref)),
        {ok, Purl#purl{subpath = SubPath1}}
    end.

-doc false.
to_binary(Chardata) ->
    case unicode:characters_to_binary(Chardata) of
        Binary when is_binary(Binary) ->
            Binary;
        {incomplete, _Encoded, _Rest} ->
            error(badarg, [Chardata], {error_info, #{cause => #{1 => "incomplete UTF-8"}}});
        {error, _Encoded, _Rest} ->
            error(badarg, [Chardata], {error_info, #{cause => #{1 => "invalid UTF-8"}}})
    end.

getenv(Env) ->
    case os:getenv(Env) of
        false -> error(env_missing, [Env]);
        Value -> to_binary(Value)
    end.

getenv(Env, Default) ->
    to_binary(os:getenv(Env, Default)).
