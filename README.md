rebar_dependency_submission
=====

A rebar plugin

Build
-----

    $ rebar3 compile

Use
---

Add the plugin to your rebar config:

    {plugins, [
        {rebar_dependency_submission, {"rebar_dependency_submission", "0.1.0"}}
    ]}.

Then just call your plugin directly in an existing application:


    $ rebar3 rebar_dependency_submission
    ===> Fetching rebar_dependency_submission
    ===> Compiling rebar_dependency_submission
    <Plugin Output>
