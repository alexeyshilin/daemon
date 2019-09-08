%%
%% @author Alexey Shilin <shilin.alexey@gmail.com>
%%
-module(srv_daemon).
-vsn(0).
-export([test/0]).
-export([shell_run/1]).
-export([start/0]).
-export([hello/0, getpid/0, stop/0, kill/0]).

%-include("srv_daemon.hrl").
%-include_lib("eunit/include/eunit.hrl").

-define(LOG_CLIENT, "daemon.client.log").
-define(LOG_SERVER, "daemon.server.log").

-define(NODE_SNAME, "somedaemon").
-define(DAEMON_NAME, list_to_atom("somedaemon@"++net_adm:localhost())).

-define(RESULT_OK, 0).
-define(RESULT_ALREADY_STARTED, 0).

-define(RESULT_ERR_UNKNOWN, 1).
-define(RESULT_ERR_UNKNOWN_ACTION, 2).
-define(RESULT_ERR_NO_NODENAME, 3).
-define(RESULT_TIMEOUT, 4).
-define(RESULT_TIMEOUT_WAIT_START, 5).
-define(RESULT_TIMEOUT_WAIT_STOP, 6).
-define(RESULT_ERR_CONNECT, 7).


-define(SERVER_TICK_TIMEOUT, 1000).


%% helpers
msg_flush() ->
	receive
		_ -> msg_flush()
		after 0 -> true
	end.

sleep(Timeout) ->
	receive after Timeout -> true end.


wait_node_start(_, 0, _) ->
	?RESULT_TIMEOUT_WAIT_START;

%wait_node_start(Node, N, Timeout) ->
%	?RESULT_OK;

wait_node_start(Node, N, Timeout) ->
	connect(Node),
	F = fun(V) -> V==Node end,
	case lists:filter(F, nodes()) of
		[] ->
			sleep(Timeout),
			wait_node_start(Node, N-1, Timeout);
		[Node] ->
			?RESULT_OK;
		_ ->
			?RESULT_ERR_UNKNOWN % unknown error
	end.

wait_node_start(Node, N) ->
	wait_node_start(Node, N, 1000).


wait_node_stop(_, 0, _) ->
	?RESULT_TIMEOUT_WAIT_STOP;

%wait_node_stop(Node, N, Timeout) ->
%	?RESULT_OK;

wait_node_stop(Node, N, Timeout) ->
	connect(Node),
	F = fun(V) -> V==Node end,
	case lists:filter(F, nodes()) of
		[] ->
			?RESULT_OK;
		[Node] ->
			sleep(Timeout),
			wait_node_stop(Node, N-1, Timeout);
		_ ->
			?RESULT_ERR_UNKNOWN % unknown error
	end.

wait_node_stop(Node, N) ->
	wait_node_stop(Node, N, 1000).

%% /helpers

%% utils
timestamp()->
	ErlangSystemTime = erlang:system_time(microsecond),
	MegaSecs = ErlangSystemTime div 1000000000000,
	Secs = ErlangSystemTime div 1000000 - MegaSecs*1000000,
	MicroSecs = ErlangSystemTime rem 1000000,
	{MegaSecs, Secs, MicroSecs}.

timestamp_s()->
	{Mega, Sec, Micro} = os:timestamp(),
	Mega*1000000 + Sec.

timestamp_ms()->
	{Mega, Sec, Micro} = os:timestamp(),
	(Mega*1000000 + Sec)*1000 + round(Micro/1000).

timestamp_mcs()->
	{Mega, Sec, Micro} = os:timestamp(),
	(Mega*1000000 + Sec)*1000*1000 + Micro.

micro2timestamp(microsecond)->
	M = 1000000,
	T = erlang:system_time(microsecond),
	{T div M div M, T div M rem M, T rem M}.

timestamp2datetime(Ts)->
	calendar:now_to_universal_time(Ts).

unixtime()->
	{Mega, Sec, Micro} = os:timestamp(),
	Mega*1000000 + Sec.

unixtime({Mega, Sec, Micro})->
	Mega*1000000 + Sec.

unixtime2timestamp(Value)->
	Mega = Value div 1000000,
	Sec = Value - Mega*1000000,
	{Mega, Sec, 0}.

datetime2unixstamp( {{Y,M,D},{Hr,Min,Sec}} = DT )->
	UnixSec = calendar:datetime_to_gregorian_seconds({{1970,01,01},{00,00,00}}), % 62167219200
	UnixSec = 62167219200,
	DtSec = calendar:datetime_to_gregorian_seconds(DT),
	DtSec - UnixSec.

dateNow()->
	{{Year, Month, Day}, {Hour, Minute, Second}} = calendar:now_to_datetime(erlang:now()),
	lists:flatten(io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0w",[Year,Month,Day,Hour,Minute,Second])).

log_info(null, Format, Data) ->
	true;

log_info(File, Format, Data) ->
	%io:fwrite(File, "~w"++Format++"~n", [erlang:localtime()] ++ Data).
	%io:fwrite(File, "~w\t"++Format++"~n", [erlang:localtime()] ++ Data).
	io:fwrite(File, "~w\t"++Format++"~n", [timestamp2datetime(erlang:timestamp())] ++ Data).
	%io:fwrite(File, "~s\t"++Format++"~n", [dateNow()] ++ Data).

log_info(File, Data)->
	log_info(File, "~s", Data).
%% /utils

%% shell
shell_run([Action]) ->
	io:format("[~s]", [Action]),
	File = case file:open(?LOG_CLIENT, [write,append]) of
		{ok, IoDevice} ->
			io:format("[log ok ~s]", [Action]),
			log_info(IoDevice, [Action]),
			IoDevice;
		{error, Reason} ->
			io:format("[~p ~p]", ["can't open file", ?LOG_CLIENT]),
			null
	end,
	%Result = run_action(Action, File),
	Result = run_action(list_to_atom(Action), File),
	log_info(File, "Action result: ~p", [Result]),
	file:close(File), % is it need to check result?
	init:stop(Result).

%run_action("start", File) ->
%	daemon_start(File);

%run_action("stop", File) ->
%	daemon_stop(File);

%run_action("restart", File) ->
%	daemon_stop(File),
%	daemon_start(File);

run_action(start, File) ->
	daemon_start(File);

run_action(stop, File) ->
	daemon_stop(File);

run_action(restart, File) ->
	daemon_stop(File),
	%sleep(10*1000),
	daemon_start(File);

run_action(Action, File) ->
	log_info(File, "Unkonown action ~p", [Action]),
	?RESULT_ERR_UNKNOWN_ACTION;

run_action(_,_) ->
	?RESULT_ERR_UNKNOWN_ACTION.
%% /shell


%% daemon
connect(Node) ->
	%net_kernel:connect_node(Node).
	net_kernel:connect(Node).

daemon_start(File) ->
	case node() of
		nonode@nohost ->
			log_info(File, ["Node name not set, use -sname key"]),
			?RESULT_ERR_NO_NODENAME;
		_ ->
			daemon_start_(File)
	end.

daemon_start_(File) ->
	case connect(?DAEMON_NAME) of
		true ->
			log_info(File, ["Already started"]),
			?RESULT_ALREADY_STARTED;
		false ->
			log_info(File, ["Try start"]),
			Cmd = "erl -detached -sname " ++ ?NODE_SNAME,
			%Cmd = "erl -detached -sname somedaemon",
			os:cmd(Cmd),

			%%wait
			%receive
			%	_ -> ok
			%	after 1000 -> ok
			%end,

			case wait_node_start(?DAEMON_NAME, 10) of
				?RESULT_OK ->
					Pid = spawn(?DAEMON_NAME, ?MODULE, start, []),
					log_info(File, "Pid: ~p", [Pid]),
					?RESULT_OK;
				Res ->
					log_info(File, "Wait node start result: ~p", [Res]),
					?RESULT_ERR_UNKNOWN;
				_ ->
					?RESULT_ERR_UNKNOWN
			end;
		ignored ->
			% ???
			?RESULT_ERR_UNKNOWN;
		_ ->
			?RESULT_ERR_UNKNOWN
	end.


daemon_stop(File) ->
	case connect(?DAEMON_NAME) of
		true ->
			Pid = whereis(srv),
			log_info(File, "Try stop ~p", [Pid]),

			Ref = make_ref(),

			msg_flush(),
			{srv, ?DAEMON_NAME} ! {stop, self(), Ref},

			receive
				{stop_resp, Ref, Resp} ->
					case wait_node_stop(?DAEMON_NAME, 10) of
						?RESULT_OK ->
							?RESULT_OK;
						Res ->
							log_info(File, "Wait node stop result: ~p", [Res]),
							?RESULT_ERR_UNKNOWN;
						_ ->
							?RESULT_ERR_UNKNOWN
					end;
				_ ->
					?RESULT_ERR_UNKNOWN
			end;
		false ->
			?RESULT_ERR_CONNECT;
		ignored ->
			% ???
			?RESULT_ERR_CONNECT;
		_ ->
			?RESULT_ERR_CONNECT
	end.
%% /daemon

%% server
start() ->
	register(srv, self()),
	Pid = whereis(srv),

	File = case file:open(?LOG_SERVER, [write,append]) of
		{ok, IoDevice} ->
			log_info(IoDevice, "Start server ~p.", [Pid]),
			IoDevice;
		{error, Reason} ->
			io:format("[~p ~p]", ["can't open file", ?LOG_SERVER]),
			null
	end,
	server(File). % or start it only when log is created

server(File) ->
	log_info(File, ["tick"]),
	receive
		{getpid, Sender, Ref} ->
			log_info(File, ["Cmd getpid"]),
			Sender ! {getpid_resp, Ref, self()},
			server(File);
		{hello, Sender, Ref} ->
			log_info(File, ["Cmd hello"]),
			Sender ! {hello_resp, Ref, ok},
			server(File);
		{stop, Sender, Ref} ->
			log_info(File, ["Cmd stop"]),
			Sender ! {stop_resp, Ref, ok},
			unregister(srv),
			init:stop();
		_ ->
			log_info(File, ["Unknown action"])
	after
		?SERVER_TICK_TIMEOUT ->
			server(File)
	end.
%% /server

%% client
cli(ReqCmd, RespCmd) ->
	case connect(?DAEMON_NAME) of
		true ->
			Ref = make_ref(),
			%msg_flush(),
			{srv, ?DAEMON_NAME} ! {ReqCmd, self(), Ref},
			receive
				{RespCmd, Ref, Resp} ->
					Resp;
				_ ->
					?RESULT_ERR_UNKNOWN
			after
				1000 ->
					?RESULT_TIMEOUT
			end;
		false ->
			?RESULT_ERR_CONNECT;
		ignored ->
			% ???
			?RESULT_ERR_CONNECT;
		_ ->
			?RESULT_ERR_CONNECT
	end.

hello() ->
	cli(hello, hello_resp).

getpid() ->
	cli(getpid, getpid_resp).

stop() ->
	cli(stop, stop_resp).

kill() ->
	case rpc:call(?DAEMON_NAME, init, stop, [], 5000) of
		{badrpc, timeout} ->
			timeout;
		{badrpc, Reason} ->
			Reason;
		Res ->
			Res
	end.

%% /client

%% test
test() ->
	ok.
%% /test

