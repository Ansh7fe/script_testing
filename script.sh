#!/bin/bash

instance_id=$1

function encrypt_volume() {
    local volume_id=$1
    local device=$2

    echo "Processing volume: $volume_id"

    # Get Volume ID not encrypted
    echo "Volume ID: $volume_id"

    echo "Create snapshot of Volume for $volume_id "
    snapshot_id=$(aws ec2 create-snapshot --volume-id $volume_id --profile AWSAdministratorAccess-474650141015 | grep -i "SnapshotId" | awk -F'\"' '{ print $4 }')
    echo "Snapshot ID: $snapshot_id"

    while [ "$snapshot1_status" != "completed" ]
        do
        snapshot1_status=`aws ec2 describe-snapshots --snapshot-ids $snapshot_id --profile AWSAdministratorAccess-474650141015 | grep -i "State" | awk -F'\"' '{ print  $4 }'`
        echo "Waiting for Source snapshot creation to be completed"
    done

    snapshot1_time=$(date +%s)
    echo "Time taken to create snapshot: $((snapshot1_time - stop_time)) seconds"

    echo "Copy the snapshot and encrypt it for $volume_id"
    copied_snapshot=$(aws --region us-east-1 ec2 copy-snapshot --source-region us-east-1 --source-snapshot-id $snapshot_id --encrypted --profile AWSAdministratorAccess-474650141015 | grep -i "SnapshotId" | awk -F'\"' '{ print  $4 }')
    echo "Copied Snapshot ID: $copied_snapshot"

    while [ "$(aws ec2 describe-snapshots --snapshot-ids $copied_snapshot --profile AWSAdministratorAccess-474650141015 | grep -i "State" | awk -F'\"' '{ print  $4 }')" != "completed" ]; do
        echo "Waiting for copied snapshot creation to be completed"
        sleep 10
    done

    snapshot2_time=$(date +%s)
    echo "Time taken to copy and encrypt snapshot: $((snapshot2_time - snapshot1_time)) seconds"

    echo "Create new volume from encrypted snapshot for $volume_id"
    new_encrypt_volume=$(aws ec2 create-volume --size 1 --region us-east-1 --availability-zone us-east-1a --volume-type gp2 --snapshot-id $copied_snapshot --profile AWSAdministratorAccess-474650141015 | grep -i "VolumeID" | awk -F'\"' '{ print  $4 }')

    echo "New Encrypted Volume ID: $new_encrypt_volume"

    while [ "$(aws ec2 describe-volumes --volume-ids $new_encrypt_volume --profile AWSAdministratorAccess-474650141015 | grep -i "State" | awk -F'\"' '{ print  $4 }')" != "available" ]; do
        echo "Waiting for new volume creation to be completed for $volume_id"
        sleep 10
    done

    new_volume_time=$(date +%s)
    echo "Time taken to create new volume: $((new_volume_time - snapshot2_time)) seconds"

    echo "Detach un-encrypted volume for $volume_id"
    aws ec2 detach-volume --volume-id $volume_id --profile AWSAdministratorAccess-474650141015

    while [ "$(aws ec2 describe-volumes --volume-ids $volume_id --profile AWSAdministratorAccess-474650141015| grep -i "State" | awk -F'\"' '{ print  $4 }')" != "available" ]; do
        echo "Waiting for old volume detachment to be completed"
        sleep 10
    done

    detach_time=$(date +%s)
    echo "Time taken to detach old volume: $((detach_time - new_volume_time)) seconds"
    # vol-09e69d80d8a833998 vol-0dc8f108faff87308


    echo "Attach newly encrypted volume for $volume_id"
    aws ec2 attach-volume --volume-id $new_encrypt_volume --instance-id $instance_id --device $device --profile AWSAdministratorAccess-474650141015

    while true; do
        new_volume_state=$(aws ec2 describe-volumes --volume-ids $new_encrypt_volume --profile AWSAdministratorAccess-474650141015 | grep -i "State" | awk -F'\"' '{ print $4 }')
        echo "$new_volume_state for $volume_id"

        if [[ "$new_volume_state" == *"in-use"* ]]; then
            echo "new-volume is attached for $volume_id"
            break
        fi

        sleep 5
    done

    attach_time=$(date +%s)
    echo "Time taken to attach new volume: $((attach_time - detach_time)) seconds"

    echo "Encryption process completed for Volume: $volume_id"
}

start_time=$(date +%s)

echo "Stop instance"
aws ec2 stop-instances --instance-ids $instance_id --profile AWSAdministratorAccess-474650141015


while [ "$instance_state" != "stopped" ]
do
    instance_state=`aws ec2 describe-instances --instance-ids $instance_id --profile AWSAdministratorAccess-474650141015 | grep -A 3 "State" | grep -i "Name" | awk -F'\"' '{ print  $4 }'`
    echo "Waiting to instance state changed to STOPPED"
    sleep 10
done

stop_time=$(date +%s)
echo "Time taken to stop instance: $((stop_time - start_time)) seconds"

# Get Volume IDs not encrypted
volumes=$(aws ec2 describe-instances --filters "Name=instance-id,Values=$instance_id"  --profile AWSAdministratorAccess-474650141015 --query 'Reservations[0].Instances[0].BlockDeviceMappings[*].Ebs.VolumeId' --output text)

# echo $volumes

volume_ids=("vol-0088664d2ca7c7c34")
device_names=()

# Loop through each volume ID and get the device name
for volume_id in "${volume_ids[@]}"; do
    device=$(aws ec2 describe-volumes --filters Name=volume-id,Values="$volume_id" --query 'Volumes[*].Attachments[*].Device' --profile AWSAdministratorAccess-474650141015 --output text)
    
    # Add the device name to the array
    device_names+=("$device")
done

encrypt_in_parallel() {
    local volume_id=$1
    local device_name=$2
    encrypt_volume "$volume_id" "$device_name" &
}


export -f encrypt_volume
export -f encrypt_in_parallel

# Run the encryption in parallel
for ((i=0; i<${#volume_ids[@]}; i++)); do
    encrypt_in_parallel "${volume_ids[$i]}" "${device_names[$i]}"
done
wait


echo "Start instances"
aws ec2 start-instances --instance-ids $instance_id --profile AWSAdministratorAccess-474650141015

end_time=$(date +%s)
echo "Total time taken to encrypt: $((end_time - start_time)) "
