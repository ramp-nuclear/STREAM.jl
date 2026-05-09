#!/usr/bin/env julia
# bin/jl-client.jl — DaemonMode protocol client with strict error handling.
#
# We use the runexpr protocol (NOT runfile) because:
#
#   1. DaemonMode's runfile uses `include_string(mod, content)` which does
#      not set __FILE__/__DIR__, so relative `include("…")` calls inside
#      the script resolve against the daemon's cwd instead of the script's
#      directory. test/runtests.jl breaks immediately.
#   2. runexpr defaults to shared=true (state persists across calls), which
#      is what we want — `using STREAM` and Revise's tracking persist between
#      bin/jl invocations, so only the first call pays full compile cost.
#
# Wire format (runexpr):
#   client → server : "DaemonMode::runexpr\n"
#   client → server : pwd() + "\n"            (daemon cd's here for the call)
#   client → server : <expression text>...
#   client → server : "DaemonMode::end\n"     (end-of-expression marker)
#   server → client : <stdout/stderr lines>... + "DaemonMode::end\n"
#
# Exit codes:
#   0 → script ran without throwing
#   1 → script threw (detected via ANSI red + "ERROR:" in stream)
#   2 → usage / not a file
#   3 → daemon not reachable (ECONNREFUSED)
#   4 → daemon closed connection mid-run

using Sockets

const TOKEN_RUNEXPR = "DaemonMode::runexpr"
const TOKEN_END     = "DaemonMode::end"
const ANSI_RED      = "\x1b[31m"

function helpful_daemon_down_message(host, port)
    repo_root = dirname(@__DIR__)
    """
    ERROR: STREAM.jl Julia daemon not reachable at $host:$port.

    Start it (one shot, idempotent):
      cd $repo_root
      bin/jl-up

    Then re-run your bin/jl call. To attach a live monitor:
      tmux attach -t stream-jl     (detach with Ctrl-B then D)

    (Override host/port: STREAM_DAEMON_HOST=... STREAM_DAEMON_PORT=... bin/jl ...)
    """
end

function build_expression(script_path::AbstractString, script_args::Vector{String})
    # Use Base.include(@__MODULE__, abspath) which DOES set __FILE__ correctly,
    # so relative includes inside the script work as in plain `julia script.jl`.
    # Wrap in begin/end because DaemonMode's serverRunExpr calls Meta.parse(expr)
    # which expects a SINGLE top-level expression — a bare ";"-separated
    # multi-statement string would crash parse() and (because there is no outer
    # try/catch in serve()) kill the whole daemon process.
    #
    # We auto-call Revise.revise() at the start of every submission so that source
    # edits made between bin/jl calls are picked up. Revise's auto-trigger only
    # fires before REPL prompts, which never happen in daemon mode. Cost when no
    # edits are pending: microseconds. Footgun: if the new source is unparseable,
    # Revise logs a warning and silently keeps the old code — same as in interactive
    # use; bin/jl just makes it more frequent.
    args_literal = repr(script_args)
    path_literal = repr(abspath(script_path))
    """
    begin
        isdefined(Main, :Revise) && Main.Revise.revise()
        empty!(ARGS); append!(ARGS, $args_literal)
        Base.include(@__MODULE__, $path_literal)
    end
    """
end

function main()
    if isempty(ARGS)
        write(stderr, "usage: jl-client.jl <script.jl> [args...]\n")
        exit(2)
    end

    port = parse(Int, get(ENV, "STREAM_DAEMON_PORT", "3000"))
    host = get(ENV, "STREAM_DAEMON_HOST", "127.0.0.1")

    script = ARGS[1]
    script_args = String.(ARGS[2:end])

    if !isfile(script)
        write(stderr, "ERROR: script not found: $script\n")
        exit(2)
    end

    sock = try
        Sockets.connect(host, port)
    catch e
        if e isa Base.IOError && occursin(r"ECONNREFUSED|connection refused"i, string(e))
            write(stderr, helpful_daemon_down_message(host, port))
            exit(3)
        end
        rethrow()
    end

    # Trailing-newline subtlety: serverRunExpr's `Meta.parse(expr)` errors with
    # "extra token after end of expression" when expr has TWO+ trailing newlines
    # (parser sees an empty trailing expression). DaemonMode's own runexpr does
    # `println(sock, expr)` and assumes the user's expr has NO trailing newline.
    # Our build_expression triple-string does end in "\n", so chomp before send.
    expr = chomp(build_expression(script, script_args))

    # Pre-validate parseability client-side. DaemonMode's serve() has NO outer
    # try/catch around serverRunExpr, so a parse error on the daemon side kills
    # the entire daemon process. Parse the *exact* string the daemon will receive
    # (chomped expr + one "\n" appended by println below).
    daemon_will_receive = expr * "\n"
    try
        Meta.parse(daemon_will_receive)
    catch e
        write(stderr, "ERROR: jl-client built an unparseable expression — refusing to send (would kill daemon).\n")
        write(stderr, "Expression was:\n$daemon_will_receive\n")
        write(stderr, "Parse error: $e\n")
        exit(2)
    end

    println(sock, TOKEN_RUNEXPR)
    println(sock, pwd())
    println(sock, expr)         # one trailing "\n" appended; matches DaemonMode's own runexpr
    println(sock, TOKEN_END)    # end-of-expression marker

    # If the daemon dies, readline() returns "" forever — cap consecutive empties.
    empty_runaway_limit = 1000
    script_failed = false
    consecutive_empty = 0
    while true
        line = try
            readline(sock; keep=false)
        catch e
            write(stderr, "ERROR: daemon closed connection mid-run: $e\n")
            exit(4)
        end

        # Note: do NOT call eof(sock) — eof() BLOCKS on a still-open TCPSocket
        # when no data is buffered, which is the steady state between calls.
        # Detect a dead daemon via the runaway-empty-line guard below instead.

        if isempty(line)
            consecutive_empty += 1
            if consecutive_empty > empty_runaway_limit
                write(stderr, "ERROR: daemon appears dead (≥$empty_runaway_limit consecutive empty lines, no end-token).\n")
                write(stderr, "Check the daemon log (e.g. /tmp/stream-jl-daemon.log) for the crash.\n")
                exit(4)
            end
        else
            consecutive_empty = 0
        end

        if occursin(TOKEN_END, line)
            tail = replace(line, TOKEN_END => "")
            if !isempty(tail)
                print(tail)
            end
            break
        end

        println(line)
        # Crayons RED_FG + "ERROR:" is the signature DaemonMode emits via
        # serverReplyError → myshowerror when the server-side script throws.
        if occursin(ANSI_RED, line) && occursin("ERROR:", line)
            script_failed = true
        end
    end

    exit(script_failed ? 1 : 0)
end

main()
