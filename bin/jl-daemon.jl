#!/usr/bin/env julia
# bin/jl-daemon.jl — STREAM.jl Julia daemon entry point.
#
# Wraps DaemonMode.serve() with per-request logging so that an attached
# `tmux attach -t stream-jl` shows when each bin/jl call is submitted, what
# expression it runs, and how long it took. Without this wrapper, DaemonMode
# redirects all per-call stdout/stderr to the client socket, so the daemon's
# tmux pane stays silent during work.
#
# Usage (from a tmux pane):
#   julia --project=. bin/jl-daemon.jl
#   julia --project=. bin/jl-daemon.jl 4000     # custom port

using Revise
using DaemonMode
using Sockets
using Dates

const PORT = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 3000

function log_event(rid, msg)
    ts = Dates.format(now(), "HH:MM:SS.sss")
    println("[#$rid $ts] $msg")
    flush(stdout)
end

function preview(s::AbstractString, n::Int=400)
    s = strip(s)
    length(s) <= n ? s : (first(s, n) * "...<truncated>")
end

function serve_with_logging(port::Int)
    println("="^70)
    println("STREAM.jl Julia daemon — listening on 127.0.0.1:$port")
    println("Per-request logs below. Submit work with: bin/jl <script.jl>")
    println("="^70)
    flush(stdout)

    server = Sockets.listen(Sockets.localhost, port)
    rid = 0
    quit = false
    while !quit
        sock = accept(server)
        rid += 1
        my_rid = rid
        t_start = time()

        local mode::String
        try
            mode = readline(sock)
        catch e
            log_event(my_rid, "could not read mode: $e (likely a port probe; ignoring)")
            continue
        end

        log_event(my_rid, "← $mode")

        if mode == DaemonMode.token_runexpr
            local dir::String, expr::String
            try
                dir = readline(sock)
                expr = readuntil(sock, DaemonMode.token_end)
            catch e
                log_event(my_rid, "✗ failed to read protocol body: $e")
                continue
            end

            log_event(my_rid, "  cwd:  $dir")
            log_event(my_rid, "  expr: $(preview(expr))")

            local parsed
            try
                parsed = Meta.parse(expr)
            catch e
                log_event(my_rid, "✗ parse error: $e (NOT killing daemon)")
                try
                    println(sock, "ERROR: parse error: $e")
                    println(sock, DaemonMode.token_end)
                    close(sock)
                catch
                end
                continue
            end

            try
                cd(dir) do
                    redirect_stdout(sock) do
                        redirect_stderr(sock) do
                            try
                                Base.eval(Main, parsed)
                                println(sock, DaemonMode.token_end)
                            catch e
                                # Replicate DaemonMode's error reporting to the client.
                                DaemonMode.serverReplyError(sock, e, catch_backtrace(), "")
                            end
                        end
                    end
                end
                log_event(my_rid, "✓ done in $(round(time() - t_start, digits=2))s")
            catch e
                log_event(my_rid, "✗ dispatch failure: $e")
            end

        elseif mode == DaemonMode.token_runfile
            # Delegate to DaemonMode's stock runfile handler — it has the
            # known-include_string-relative-path issue we use runexpr to avoid,
            # but we still support runfile in case anyone calls it directly.
            log_event(my_rid, "  (delegating to DaemonMode.serverRunFile)")
            try
                DaemonMode.serverRunFile(sock, false, true)
                log_event(my_rid, "✓ runfile done in $(round(time() - t_start, digits=2))s")
            catch e
                log_event(my_rid, "✗ runfile failed: $e")
            end

        elseif mode == DaemonMode.token_exit
            log_event(my_rid, "shutdown requested")
            try
                println(sock, DaemonMode.token_end)
                close(sock)
            catch
            end
            quit = true

        else
            log_event(my_rid, "✗ unknown mode (likely a port probe / nc -z); closing socket")
            try
                close(sock)
            catch
            end
        end
    end
    close(server)
    println("daemon stopped")
end

serve_with_logging(PORT)
