#!/bin/bash

# to abort in case of errors

function error {
echo aborted due to an error
exit 1
}
trap error ERR

dist/build/nikki/nikki $@ --runinplace +RTS -C
