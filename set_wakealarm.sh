#!/bin/bash

# This script sets the linux wakealarm so that if the machine is
# shutdown, it will turn back on at the specified time.

function tomorrow(){
    echo "$(date --date='tomorrow' +%Y-%m-%d)"
}

alarm_for="$(tomorrow) 07:00"

if [[ $(date -d "$(tomorrow)" +%u) -gt 5 ]]; then
  # awaking on the wkend..
  alarm_for="$(tomorrow) 07:30"
fi

echo Setting wake alarm for: $alarm_for

rtcwake -m no --date="$alarm_for" --utc --dry-run

echo Alarm details:

cat /proc/driver/rtc

rtcwake -m show
