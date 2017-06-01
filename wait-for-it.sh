#!/usr/bin/env bash
#   Use this script to test if a given TCP host/port are available

SCRIPT_NAME=$(basename ${0})
SCRIPT_VERSION='1.0.0'

echoerr() { if [[ $QUIET -ne 1 ]]; then echo "$@" 1>&2; fi }

show_usage()
{
    cat << USAGE >&2
Usage:
    $SCRIPT_NAME host:port [-s] [-t timeout] [-- command args]
    --help              show usage
    --version           show version
    --host HOST         Host or IP under test
    --port PORT         TCP port under test
    --timeout TIMEOUT   Timeout in seconds, zero for no timeout
    --child             Fork
    --strict            Only execute subcommand if the test succeeds
    --quiet             Don't output any status messages
    -- COMMAND ARGS     Execute command with args after the test finishes
USAGE
}

wait_for()
{
    if [[ $TIMEOUT -gt 0 ]]; then
        echoerr "$SCRIPT_NAME: waiting $TIMEOUT seconds for $DISP_HOST:$PORT"
    else
        echoerr "$SCRIPT_NAME: waiting for $DISP_HOST:$PORT without a timeout"
    fi
    start_ts=$(date +%s)
    while :
    do
        # (echo > /dev/tcp/$HOST/$PORT) >/dev/null 2>&1
        if [[ "${SCAN_CMD}" ]];then
            [[ ${REQUIRE_NULL} = '1' ]] && ${SCAN_CMD} </dev/null >/dev/null 2>&1 || ${SCAN_CMD} >/dev/null 2>&1
        else
            (echo > /dev/tcp/$HOST/$PORT) >/dev/null 2>&1
        fi
        result=$?
        if [[ $result -eq 0 ]]; then
            end_ts=$(date +%s)
            echoerr "$SCRIPT_NAME: $DISP_HOST:$PORT is available after $((end_ts - start_ts)) seconds"
            break
        fi
        sleep 1
    done
    return $result
}

wait_for_wrapper()
{
    # In order to support SIGINT during timeout: http://unix.stackexchange.com/a/57692
    if [[ $QUIET -eq 1 ]]; then
        timeout $TIMEOUT $0 --quiet --child --host $HOST --port $PORT --timeout $TIMEOUT &
    else
        timeout $TIMEOUT $0 --child --host $HOST --port $PORT --timeout $TIMEOUT &
    fi
    PID=$!
    trap "kill -INT -$PID" INT
    wait $PID
    RESULT=$?
    if [[ $RESULT -ne 0 ]]; then
        echoerr "$SCRIPT_NAME: timeout occurred after waiting $TIMEOUT seconds for $DISP_HOST:$PORT"
    fi
    return $RESULT
}

# process arguments
for OPT in "$@"; do
    case "$OPT" in
    '-h' | '--help' )
        show_usage
        exit 0
        ;;
    '-v' | '--version' )
        echo -e "${FONT_INFO}${SCRIPT_VERSION}${FONT_DEFAULT}"
        exit 0
        ;;
    '--host' )
        if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
            echo -e "${FONT_ERROR}[ERROR] ${SCRIPT_NAME}: option requires an argument -- ${1}${FONT_DEFAULT}" 1>&2
            echo
            show_usage
            exit 1
        fi
        HOST=$2
        shift 2
        ;;
    '--port' )
        if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
            echo -e "${FONT_ERROR}[ERROR] ${SCRIPT_NAME}: option requires an argument -- ${1}${FONT_DEFAULT}" 1>&2
            echo
            show_usage
            exit 1
        fi
        PORT=$2
        shift 2
        ;;
    '--timeout' )
        if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
            echo -e "${FONT_ERROR}[ERROR] ${SCRIPT_NAME}: option requires an argument -- ${1}${FONT_DEFAULT}" 1>&2
            echo
            show_usage
            exit 1
        fi
        TIMEOUT=$2
        shift 2
        ;;
    '--child' )
        CHILD=1
        shift
        ;;
    '--strict' )
        STRICT=1
        shift
        ;;
    '--quiet' )
        QUIET=1
        shift
        ;;
    '--' )
        CLI="$@"
        break
        ;;
    -*)
        echo -e "${FONT_ERROR}[ERROR] ${SCRIPT_NAME}: invalid option -- $(echo ${1} | sed 's/^-*//')'${FONT_DEFAULT}" 1>&2
        echo
        show_usage
        exit 1
        ;;
    *)
    if [[ ! -z "${1}" ]] && [[ ! "${1}" =~ ^-+ ]]; then
        #param=( ${param[@]} "${1}" )
        param+=( "${1}" )
        shift
    fi
    ;;
  esac
done

if [[ "$HOST" == "" || "$PORT" == "" ]]; then
    echoerr "Error: you need to provide a host and port to test."
    show_usage
    exit 1
elif grep -q ':' <<<${HOST};then
    IS_IPV6=1
    DISP_HOST="[${HOST}]"
else
    IS_IPV6=0
    DISP_HOST="${HOST}"
fi


TIMEOUT=${TIMEOUT:-15}
STRICT=${STRICT:-0}
CHILD=${CHILD:-0}
QUIET=${QUIET:-0}
REQUIRE_NULL=${REQUIRE_NULL:-0}


if [[ $IS_IPV6 -eq 1 ]];then
    if hash socat >/dev/null;then
        SCAN_CMD="socat -t0.5 -T0.5 - TCP:[${HOST}]:${PORT},connect-timeout=0.5"
        REQUIRE_NULL=1
    elif hash ncat >/dev/null;then
        SCAN_CMD="ncat -6 --send-only --wait 0.5 ${HOST} ${PORT}"
        REQUIRE_NULL=1
    fi
else
    if hash socat >/dev/null;then
        SCAN_CMD="socat -t0.5 -T0.5 - TCP:${HOST}:${PORT},connect-timeout=0.5"
        REQUIRE_NULL=1
    elif hash netcat >/dev/null;then
        SCAN_CMD="netcat --tcp --wait=2 --zero ${HOST} ${PORT}"
    elif hash nc >/dev/null;then
        SCAN_CMD="nc --tcp --wait=2 --zero ${HOST} ${PORT}"
    elif hash ncat >/dev/null;then
        SCAN_CMD="ncat --send-only --wait 0.5 ${HOST} ${PORT}"
        REQUIRE_NULL=1
    fi
fi

if [[ $CHILD -gt 0 ]]; then
    wait_for
    RESULT=$?
    exit $RESULT
else
    if [[ $TIMEOUT -gt 0 ]]; then
        wait_for_wrapper
        RESULT=$?
    else
        wait_for
        RESULT=$?
    fi
fi

if [[ $CLI != "" ]]; then
    if [[ $RESULT -ne 0 && $STRICT -eq 1 ]]; then
        echoerr "$SCRIPT_NAME: strict mode, refusing to execute subprocess"
        exit $RESULT
    fi
    exec $CLI
else
    exit $RESULT
fi
