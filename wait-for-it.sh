#!/bin/bash

# Réécriture et modification du script wait-for-it (https://github.com/vishnubob/wait-for-it) pour efluid
# Ce script permet de tester si une adresse TCP répond aux requètes.
cmdname=$(basename "$0")

log() { if [[ $W4IT_QUIET -ne 1 ]]; then echo "$@" 1>&2; fi }

help(){
    cat << USAGE >&2
Usage:
    ${cmdname} host:port/path [-s] [-t timeout] [--print-params] [-- command args]
    -h HOST | --host=HOST       Host or IP under test
    -p PORT | --port=PORT       TCP port under test
    --path                      The path to test
                                Alternatively, you specify the host, port and path as host:port/path
    --retry <NUM>               The number of times the script is allowed to test the path
                                Used only if a path is provided. Default is 100
    -s | --strict               Only execute subcommand if the test succeeds
    -q | --quiet                Don't output any status messages
    -t TIMEOUT | --timeout=TIMEOUT
                                Timeout in seconds, zero for no timeout
    --print-params              Print all the arguments
    -- COMMAND ARGS             Execute command with args after the test finishes
USAGE
    exit 1
}
#  curl --data-urlencode \"script=$(<./test.groovy)\"

wait_for() {
    if [[ $W4IT_TIMEOUT -gt 0 ]]; then
        log "$cmdname: waiting $W4IT_TIMEOUT seconds for $W4IT_HOST:$W4IT_PORT"
    else
        log "$cmdname: waiting for $W4IT_HOST:$W4IT_PORT without a timeout"
    fi
    start_ts=$(date +%s)
    while :
    do
        (echo > "/dev/tcp/$W4IT_HOST/$W4IT_PORT") >/dev/null 2>&1
        result=$?
        if [[ $result -eq 0 ]]; then
            end_ts=$(date +%s)
            log "$cmdname: $W4IT_HOST:$W4IT_PORT is available after $((end_ts - start_ts)) seconds"
            if [[ $W4IT_PATH != "" ]]; then
                log "$cmdname: testing if $W4IT_HOST:$W4IT_PORT$W4IT_PATH is available"
                curl --retry "$W4IT_RETRY" "$W4IT_HOST:$W4IT_PORT$W4IT_PATH"
                res=$?
                if [[ $res -eq 0 ]]; then
                    end_ts=$(date +%s)
                    log "$cmdname: $W4IT_HOST:$W4IT_PORT$W4IT_PATH is available after $((end_ts - start_ts)) seconds"
                fi
            fi
            break
        fi
        sleep 1
    done
    return $result
}

wait_for_wrapper() {
    # In order to support SIGINT during timeout: http://unix.stackexchange.com/a/57692 
    if [[ $W4IT_QUIET -eq 1 ]]; then
        timeout "$W4IT_TIMEOUT" "$0" --quiet --child --host="$W4IT_HOST" --port="$W4IT_PORT" --path="$W4IT_PATH" --retry="$W4IT_RETRY" --timeout="$W4IT_TIMEOUT" &
    else
        timeout "$W4IT_TIMEOUT" "$0" --child --host="$W4IT_HOST" --port="$W4IT_PORT" --path="$W4IT_PATH" --retry="$W4IT_RETRY" --timeout="$W4IT_TIMEOUT" &
    fi
    PID=$!
    trap 'kill -INT -"$PID"' INT
    wait $PID
    RESULT=$?
    if [[ $RESULT -ne 0 ]]; then
        log "$cmdname: timeout occurred after waiting $W4IT_TIMEOUT seconds for $W4IT_HOST:$W4IT_PORT$W4IT_PATH"
    fi
    return $RESULT
}

print_params(){
    echo -e "$cmdname params\n-----------------------
    W4IT_HOST    = $W4IT_HOST
    W4IT_PORT    = $W4IT_PORT
    W4IT_PATH    = $W4IT_PATH
    W4IT_RETRY   = $W4IT_RETRY
    W4IT_QUIET   = $W4IT_QUIET
    W4IT_STRICT  = $W4IT_STRICT
    W4IT_TIMEOUT = $W4IT_TIMEOUT
    W4IT_CMD     = $W4IT_CMD
    "
}

parse_url(){
    # remove protocol if exists
    url=${1//*:\/\//}
    # extract host
    W4IT_HOST=$(echo "$url" | cut -d/ -f1 | cut -d: -f1)
    # extract port
    W4IT_PORT=$(echo "$url" | cut -d: -f2 | cut -d/ -f1)
    # extract path
    W4IT_PATH=${url//$W4IT_HOST:$W4IT_PORT/}
}

while [[ $# -gt 0 ]] 
do
    case "$1" in
        *:* )
            parse_url "$1"
            shift 1
            ;;
        --child)
            W4IT_CHILD=1
            shift 1
            ;;
        -q | --quiet)
            W4IT_QUIET=1
            shift 1
            ;;
        -s | --strict)
            W4IT_STRICT=1
            shift 1
            ;;
        -h)
            W4IT_HOST="$2"
            if [[ "$W4IT_HOST" == "" ]]; then break; fi
            shift 2
            ;;
        --host=*)
            W4IT_HOST="${1#*=}"
            shift 1
            ;;
        --path=*)
            W4IT_PATH="${1#*=}"
            shift 1
            ;;
        --retry=*)
            W4IT_RETRY="${1#*=}"
            shift 1
            ;;
        -p)
            W4IT_PORT="$2"
            if [[ "$W4IT_PORT" == "" ]]; then break; fi
            shift 2
            ;;
        --port=*)
            W4IT_PORT="${1#*=}"
            shift 1
            ;;
        -t)
            W4IT_TIMEOUT="$2"
            if [[ $W4IT_TIMEOUT == "" ]]; then break; fi
            shift 2
            ;;
        --timeout=*)
            W4IT_TIMEOUT="${1#*=}"
            shift 1
            ;;
        --print-params)
            PRINT_PARAMS=1
            shift 1
            ;;
        --)
            shift
            W4IT_CMD=$*
            break
            ;;
        --help)
            help
            ;;
        *)
            log "Unknown argument: $1"
            help
            ;;
    esac
done

if [[ "$W4IT_HOST" == "" || "$W4IT_PORT" == "" ]]; then
    log "Error: you need to provide a host and port to test."
    help
fi        

W4IT_TIMEOUT=${W4IT_TIMEOUT:-15}
W4IT_STRICT=${W4IT_STRICT:-0}
W4IT_QUIET=${W4IT_QUIET:-0}
W4IT_RETRY=${W4IT_RETRY:-100}
W4IT_CHILD=${W4IT_CHILD:-0}
PRINT_PARAMS=${PRINT_PARAMS:-0}

if [[ $PRINT_PARAMS -ne 0 ]]; then
    print_params
fi

if [[ $W4IT_CHILD -gt 0 ]]; then
    wait_for
    RESULT=$?
    exit $RESULT
else
    if [[ $W4IT_TIMEOUT -gt 0 ]]; then
        wait_for_wrapper
        RESULT=$?
    else
        wait_for
        RESULT=$?
    fi
fi

if [[ $W4IT_CMD != "" ]]; then
    if [[ $RESULT -ne 0 && $W4IT_STRICT -eq 1 ]]; then
        log "$cmdname: strict mode, refusing to execute subprocess"
        exit $RESULT
    fi
    eval "$W4IT_CMD"
else
    exit $RESULT
fi


