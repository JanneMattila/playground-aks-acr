#!/usr/bin/env bash

# Run once in every minute
UPDATE_FREQUENCY=60

while true; do
   echo "Hello there!"
   sleep "$UPDATE_FREQUENCY"
done
