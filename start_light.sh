#!/bin/bash

set -xe

./transit.sh cyberway-prestart-check
./transit.sh transit-global-wait
./transit.sh cyberway-download-genesis
./transit.sh cyberway-first-run
