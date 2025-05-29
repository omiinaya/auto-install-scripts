#!/bin/bash
# List of container IDs
containers=$(pct list | tail -n +2 | awk '{print $1}')

# Function to update a container
update_container() {
    container=$1
    echo "[Info] Updating container $container"
    pct exec $container -- bash -c "apt update && apt full-upgrade -y && apt autoremove -y"
}

# Iterate through each container and update it
for container in $containers; do
    status=$(pct status $container)
    if [[ $status == "status: stopped" ]]; then
        echo "[Info] Starting container $container"
        pct start $container
        sleep 5
        update_container $container
        echo "[Info] Shutting down container $container"
        pct shutdown $container &
    elif [[ $status == "status: running" ]]; then
        update_container $container
    fi
done
wait