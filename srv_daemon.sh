#!/bin/sh

ERL=/usr/bin/erl
SRV=srv_daemon
FUN=shell_run
SNODENAME=somenode
LOG=daemon.log

case $1 in

	start|stop|restart)
		$ERL -detached -sname $SNODENAME -run $SRV $FUN $1 >> $LOG
		#$ERL -detached -run $SRV $FUN $1 >> $LOG
		#$ERL -sname $SNODENAME -run $SRV $FUN $1 >> $LOG
		#/usr/bin/erl -detached -sname somenode -run srv_daemon shell_do start >> daemon.log
		;;

	*)
		echo "Usage: $0 (start|stop|restart)"
		exit 1

esac

exit 0
