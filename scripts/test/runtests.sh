#!/bin/bash
set -e

./tests/buffer_test --abort-on-failure
./tests/serialization_test --abort-on-failure
./tests/strfmt_test --abort-on-failure
./tests/stat_mgr_test --abort-on-failure
./tests/raft_server_test --abort-on-failure
./tests/snapshot_test --abort-on-failure
./tests/leader_election_test --abort-on-failure
./tests/new_joiner_test --abort-on-failure
./tests/failure_test --abort-on-failure

