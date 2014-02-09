#!/bin/bash
#
# Copyright (C) 2014 Cloudwatt <libre.licensing@cloudwatt.com>
#
# Author: Loic Dachary <loic@dachary.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU Library Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library Public License for more details.
#
source test/mon/mon-test-helpers.sh

function run() {
    local dir=$1

    export CEPH_ARGS
    CEPH_ARGS+="--fsid=$(uuidgen) --auth-supported=none "
    CEPH_ARGS+="--mon-host=127.0.0.1 "

    setup $dir || return 1
    run_mon $dir a --public-addr 127.0.0.1
    FUNCTIONS=${FUNCTIONS:-$(set | sed -n -e 's/^\(TEST_[0-9a-z_]*\).*/\1/p')}
    for TEST_function in $FUNCTIONS ; do
        $TEST_function $dir || return 1
    done
    teardown $dir || return 1

    FUNCTIONS_RESET=${FUNCTIONS_RESET:-$(set | sed -n -e 's/^\(TESTRESET_[0-9a-z_]*\).*/\1/p')}
    for TEST_function in $FUNCTIONS_RESET ; do
        setup $dir || return 1
        $TEST_function $dir || return 1
        teardown $dir || return 1
    done
}

function TEST_crush_rule_create_simple() {
    local dir=$1
    ./ceph osd crush rule dump replicated_ruleset xml | \
        grep '<op>take</op><item>default</item>' | \
        grep '<op>chooseleaf_firstn</op><num>0</num><type>host</type>' || return 1
    local ruleset=ruleset
    local root=host1
    ./ceph osd crush add-bucket $root host
    local failure_domain=osd
    ./ceph osd crush rule create-simple $ruleset $root $failure_domain || return 1
    ./ceph osd crush rule dump $ruleset xml | \
        grep '<op>take</op><item>'$root'</item>' | \
        grep '<op>choose_firstn</op><num>0</num><type>'$failure_domain'</type>' || return 1
    ./ceph osd crush rule rm $ruleset || return 1
}

function TEST_crush_rule_dump() {
    local dir=$1
    local ruleset=ruleset
    ./ceph osd crush rule create-erasure $ruleset || return 1
    local expected
    expected="<rule_name>$ruleset</rule_name>"
    ./ceph osd crush rule dump $ruleset xml | grep $expected || return 1
    ./ceph osd crush rule dump $ruleset xml-pretty | grep $expected || return 1
    expected='"rule_name":"'$ruleset'"'
    ./ceph osd crush rule dump $ruleset json | grep "$expected" || return 1
    expected='"rule_name": "'$ruleset'"'
    ./ceph osd crush rule dump $ruleset json-pretty | grep "$expected" || return 1
    ./ceph osd crush rule dump | grep "$expected" || return 1
    ! ./ceph osd crush rule dump non_existent_ruleset || return 1
    ./ceph osd crush rule rm $ruleset || return 1
}

function TEST_crush_rule_all() {
    local dir=$1
    local crush_ruleset=erasure2
    ! ./ceph osd crush rule ls | grep $crush_ruleset || return 1
    ./ceph osd crush rule create-erasure $crush_ruleset || return 1
    ./ceph osd crush rule ls | grep $crush_ruleset || return 1

    ./ceph osd crush rule create-erasure $crush_ruleset || return 1

    ./ceph osd crush dump | grep $crush_ruleset || return 1

    ./ceph osd crush rule rm $crush_ruleset || return 1
    ! ./ceph osd crush rule ls | grep $crush_ruleset || return 1
}

function TESTRESET_crush_rule_create_simple_exists() {
    local dir=$1
    run_mon $dir a --public-addr 127.0.0.1 \
        --paxos-propose-interval=200 --debug-mon=20 --debug-paxos=20 
    local ruleset=ruleset
    local root=default
    local failure_domain=host
    ./ceph osd crush rule create-simple first $root $failure_domain # propose interval ignored the first time around
    ./ceph osd crush rule create-simple $ruleset $root $failure_domain &
    pid=$!
    waitfor $dir 'already exists (pending)' \
        ./ceph osd crush rule create-simple $ruleset $root $failure_domain
    kill $pid
}

main osd-crush

# Local Variables:
# compile-command: "cd ../.. ; make -j4 && test/mon/osd-crush.sh"
# End:
