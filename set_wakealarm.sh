#!/bin/bash

# This script sets the linux wakealarm so that if the machine is
# shutdown, it will turn back on at the specified time.

function wake_up_time(){
    local tomorrows_date="$(date --date='tomorrow' +%Y-%m-%d)"
    local wake_up_time=$(date -d "$tomorrows_date $1" +%s)
    echo "$wake_up_time"
}

alarm_for=$(wake_up_time "07:00")

if [[ $(date -d @$alarm_for +%u) -gt 5 ]]; then
  # awaking on the wkend..
  alarm_for=$(wake_up_time "07:30")
fi

echo Waking up at $(date -d @$alarm_for +'%Y-%m-%d %T')

echo Setting wake alarm with: $alarm_for

echo $alarm_for > /sys/class/rtc/rtc0/wakealarm

echo Alarm details:

cat /proc/driver/rtc
