#!/sbin/openrc-run
# shellcheck shell=bash

depend() {
    need docker
}

wait_for_docker() {
    eindent
    ebegin "Waiting for docker to start"
    local num_loops=0
    local ret=0

    while ! docker info > /dev/null 2>&1; do
        if [ ${num_loops} -ge 30 ]; then
            ret=1
            break
        fi
        num_loops=$((num_loops + 1))
        sleep 1.0
    done

    eend ${ret}
    eoutdent
    return ${ret}
}

start_compose() {
    docker-compose -f /etc/containers-compose.yml up -d
    return $?
}

start() {
    ebegin "Starting docker containers"
    wait_for_docker
    local ret=$?

    if [ ${ret} -ne 0 ]; then
        eend ${ret}
        return
    fi

    if [ -f /etc/containers-compose.yml ]; then
        start_compose
        ret=$?
    fi

    eend ${ret}
}

stop_compose() {
    docker-compose -f /etc/containers-compose.yml down
    return $?
}

stop() {
    ebegin "Stopping docker containers"
    wait_for_docker

    local ret=0

    if [ -f /etc/containers-compose.yml ]; then
        stop_compose
        ret=$?
    fi

    eend ${ret}
}