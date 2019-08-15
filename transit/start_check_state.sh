#!/bin/bash

set -xe

./transit.sh cyberway-prestart-check
./transit.sh state-prestart-check
./transit.sh hf21-wait
# Uncomment if your signing key mathes the active key
# ./transit.sh transit-approve
./transit.sh golos-existing-run
./transit.sh transit-local-wait
./transit.sh cyberway-generate-genesis
./transit.sh cyberway-first-run
