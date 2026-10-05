# Sourced by the live harnesses: how long nobody has touched this Mac, and whether its screen is locked.
# screen_locked needs $HELPER, the compiled Scripts/e2e_predict_helper.swift.

# Reads to the end rather than exiting awk early, so ioreg is never killed by SIGPIPE under pipefail.
idle_seconds() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ && !seen { print $NF / 1000000000; seen = 1 }'; }
screen_locked() { [ "$("$HELPER" locked 2>/dev/null)" = "1" ]; }
