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

start_manifest() {
    local i=0
    local ret=0
    local has_errors=0

    eindent

    # shellcheck disable=SC2002
    cat /etc/containers.manifest | \
    grep -vE '#|^$' | \
    while read -r image cmd; do
        local name="auto${i}"
        vebegin "Starting ${name}"
        ret=0
        id=$(docker ps -a -q -f name=${name})
        if [ -z "${id}" ]; then
            docker run --restart=always -d --name ${name} ${image} ${cmd} > /dev/null 2>&1
            ret=$?
        else
            docker start "${id}" > /dev/null 2>&1
            ret=$?
        fi
        if [ ${ret} -ne 0 ]; then
            has_errors=1
        fi
        veend ${ret}
        i=$((i + 1))
    done

    eoutdent
    return ${has_errors}
}

start_compose() {
    docker-compose -f /etc/containers-compose.yml up
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
    else
        start_manifest
        ret=$?
    fi

    eend ${ret}
}

stop_manifest() {
    local i=0
    local ret=0
    local has_errors=0

    eindent
    # shellcheck disable=SC2002
    cat /etc/containers.manifest | \
    grep -vE '#|^$' | \
    while read -r image cmd; do
        local name="auto${i}"
        vebegin "Stopping ${name}"
        ret=0
        id=$(docker ps -q -f name=${name})
        if [ ! -z "${id}" ]; then
            docker stop "${id}" > /dev/null 2>&1
            ret=$?
            if [ ${ret} -ne 0 ]; then
                has_errors=1
            fi
        fi
        veend ${ret}
        i=$((i + 1))
    done

    eoutdent
    return ${has_errors}
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
    else
        stop_manifest
        ret=$?
    fi

    eend ${ret}
}