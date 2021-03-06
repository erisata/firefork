%/--------------------------------------------------------------------
%| Copyright 2017 Kazimieras Senvaitis
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%% @doc
%%% This module allows to play music.
%%% It depends on OS software - mplayer.
%%% Single mp3 files and mp3 playlists (.m3u) are supported.
%%%
-module(firefork_audio_player_mplayer).
-compile([{parse_transform, lager_transform}]).
-behaviour(firefork_audio_player).
-behaviour(gen_server).
-export([
    start_link/1,
    play/2,
    stop/1,
    pause/1,
    resume/1,
    next/1,
    prev/1
]).
-export([
    init/1,
    handle_info/2,
    handle_cast/2,
    handle_call/3,
    code_change/3,
    terminate/2
]).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%  @doc
%%  Manage audio player.
%%
start_link(Name) ->
    {ok, _Pid} = gen_server:start_link({local, Name}, ?MODULE, [], []).

play(ProcName, Path) ->
    try gen_server:call(ProcName, {play, Path})
    catch
        exit:{noproc, _} ->
            case firefork_audio_player_sup:start_child(ProcName) of
                {ok, _Pid} ->
                    gen_server:call(ProcName, {play, Path});
                {error, already_present} ->
                    {ok, _Pid} = firefork_audio_player_sup:restart_child(),
                    gen_server:call(ProcName, {play, Path})
            end
    end.

stop(Pid) ->
    try gen_server:call(Pid, stop)
    catch
        exit:{normal, _} ->
            ok;
        exit:{noproc, _} ->
            {error, audio_player_not_stated}
    end.

pause(Pid) ->
    try gen_server:call(Pid, pause)
    catch
        exit:{noproc, _} ->
            {error, audio_player_not_stated}
    end.

resume(Pid) ->
    try gen_server:call(Pid, resume)
    catch
        exit:{noproc, _} ->
            {error, audio_player_not_stated}
    end.

next(Pid) ->
    try gen_server:call(Pid, next)
    catch
        exit:{noproc, _} ->
            {error, audio_player_not_stated}
    end.

prev(Pid) ->
    try gen_server:call(Pid, prev)
    catch
        exit:{noproc, _} ->
            {error, audio_player_not_stated}
    end.

%%% ============================================================================
%%% Internal state of the module.
%%% ============================================================================

-record(state, {
    port    :: term(),
    status  :: playing | paused,
    type    :: playlist | single
}).



%%% ============================================================================
%%% Callbacks for `gen_server'.
%%% ============================================================================

%% @doc
%% Initializes the process.
%%
init(_) ->
    {ok, #state{}}.


%% @doc
%% Manage the audio play.
%%
handle_call({play, Path}, _From, State = #state{status = Status}) ->
    case Status of
        playing ->
            {reply, {error, already_playing}, State};
        _ ->
            case filename:extension(Path) of
                ".m3u" ->
                    Port = erlang:open_port({spawn, "mplayer -playlist " ++ Path}, [stream, binary, use_stdio, exit_status]),
                    {reply, ok, State#state{port = Port, type = playlist, status = playing}};
                ".mp3" ->
                    Port = erlang:open_port({spawn, "mplayer " ++ Path}, [stream, binary, use_stdio, exit_status]),
                    {reply, ok, State#state{port = Port, type = single, status = playing}};
                Ext ->
                    {stop, {error, {unsupported_extention, Ext}}}
            end
    end;

handle_call(stop, _From, State = #state{port = Port}) ->
    true = erlang:port_command(Port, "q"),
    true = erlang:port_close(Port),
    {stop, normal, State};

handle_call(pause, _From, State = #state{status = paused}) ->
    {reply, {error, already_paused}, State};

handle_call(pause, _From, State = #state{port = Port}) ->
    true = erlang:port_command(Port, "p"),
    NewState = State#state{status = paused},
    {reply, ok, NewState};

handle_call(resume, _From, State = #state{status = playing}) ->
    {reply, {error, already_resumed}, State};

handle_call(resume, _From, State = #state{port = Port}) ->
    true = erlang:port_command(Port, "p"),
    NewState = State#state{status = playing},
    {reply, ok, NewState};

handle_call(next, _From, State = #state{port = Port, type = playlist}) ->
    true = erlang:port_command(Port, ">"),
    NewState = State#state{status = playing},
    {reply, ok, NewState};

handle_call(prev, _From, State = #state{port = Port, type = playlist}) ->
    true = erlang:port_command(Port, "<"),
    NewState = State#state{status = playing},
    {reply, ok, NewState};

handle_call(next, _From, State = #state{type = single}) ->
    {reply, {error, {not_available_for_single_mp3, next}}, State};

handle_call(prev, _From, State = #state{type = single}) ->
    {reply, {error, {not_available_for_single_mp3, prev}}, State};

handle_call(Unknown, _From, State) ->
    {reply, {error, {unknown_command, Unknown}}, State}.


%% @doc
%% Unused.
%%
handle_cast(_Unknown, State) ->
    {noreply, State}.


%% @doc
%% Handles message when Port is closed externally.
%%
handle_info({Port, {exit_status, _Status}}, State = #state{port = Port}) ->
    lager:info("Audio play finished."),
    {stop, normal, State};

handle_info(_Unknown, State) ->
    {noreply, State}.


%% @doc
%% Unused.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% @doc
%% Unused.
%%
terminate(_Reason, _State) ->
    ok.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================
