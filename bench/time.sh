#!/bin/bash

httperf=${httperf:-$(which httpref)}

if [[ -z "${httperf}" ]]
then
    echo "$0:"' Error: "httperf" not in PATH and not defined as environment variable'
    exit 1
fi

onerror () {
    echo "$0: Error on line #$1"
    exit $2
}


trap 'onerror $LINENO $?' ERR

# command to start web server
webserver=${webserver:-DEFINE_websever_VARIABLE}

port=${1:-8001}
outfile=${2:-/dev/tty}
filter=${filter:-Request.rate}
calls=${calls:-400}
conns=${conns:-10}
uri=${uri:-/hello}

# echo "... $webserver 127.0.0.1:$port &"

$webserver 127.0.0.1:$port > /dev/null &

onexit() {
   kill $!
}

trap onexit EXIT


sleep 1

echo "${conns} x ${calls}0"
${httperf} --port=8001 --uri=/hello --num-conns="$conns" --num-calls="$calls"0 2> /dev/null | grep "$filter" > $outfile

echo "${conns}0 x ${calls}"
${httperf} --port=8001 --uri=/hello --num-conns="$conns"0 --num-calls="$calls" 2> /dev/null | grep "$filter" > $outfile
