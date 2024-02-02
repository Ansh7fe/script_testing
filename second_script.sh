#!/bin/bash

# Variables
source_volume_id="vol-0088664d2ca7c7c34"
destination_volume_size="5"
source_mount_point="/vol1"
destination_mount_point="/vol2"
encrypted_volume_id="vol-089827b1b1b914e1a"

ssh -i ansh-test.pem ec2-user@10.0.2.22 "mkdir $source_mount_point/dummy_directory"
ssh -i ansh-test.pem ec2-user@10.0.2.22 "touch $source_mount_point/dummy_directory/file1.txt"
ssh -i ansh-test.pem ec2-user@10.0.2.22 "touch $source_mount_point/dummy_directory/file2.txt"
ssh -i ansh-test.pem ec2-user@10.0.2.22 "echo 'Sample content for file1.txt' | sudo tee $source_mount_point/dummy_directory/file1.txt"
ssh -i ansh-test.pem ec2-user@10.0.2.22 "echo 'Sample content for file2.txt' | sudo tee $source_mount_point/dummy_directory/file2.txt"

ssh -i ansh-test.pem ec2-user@10.0.2.22 "ls -l $source_mount_point/dummy_directory/"

# Create an encrypted volume
# encrypted_volume_id=$(aws ec2 create-volume --size $destination_volume_size --encrypted --availability-zone us-east-1a --volume-type gp2 --output json --profile AWSAdministratorAccess-474650141015)
# echo "$encrypted_volume_id"


# Wait for the new volume to be available
aws ec2 wait volume-available --volume-ids $encrypted_volume_id --profile AWSAdministratorAccess-474650141015

# # Attach volumes to the temporary instance
aws ec2 attach-volume --volume-id $encrypted_volume_id --instance-id i-0e5a64c5a0c74d33b --device /dev/xvdaa --profile AWSAdministratorAccess-474650141015

# # Wait for the volumes to be attached 
aws ec2 wait volume-in-use --volume-ids $source_volume_id $encrypted_volume_id --profile AWSAdministratorAccess-474650141015

ssh -i ansh-test.pem ec2-user@10.0.2.22 "mkdir $source_mount_point"
ssh -i ansh-test.pem ec2-user@10.0.2.22 "mkdir $destination_mount_point"

# Mount the source volume
echo "Mounting source volume ($source_volume_id) at $source_mount_point"
ssh -i ansh-test.pem ec2-user@10.0.2.22 "mount /dev/sdg $source_mount_point"
if [ $? -ne 0 ]; then
    echo "Failed to mount source volume: $source_volume_id"
    exit 1
fi

# Mount the encrypted volume
echo "Mounting encrypted volume ($encrypted_volume_id) at $destination_mount_point"
ssh -i ansh-test.pem ec2-user@10.0.2.22 "mount /dev/xvdaa $destination_mount_point"
if [ $? -ne 0 ]; then
    echo "Failed to mount encrypted volume: $encrypted_volume_id"
    # Unmount the source volume before exiting
    ssh -i ansh-test.pem ec2-user@10.0.2.22 "umount $source_mount_point"
    exit 1
fi

# Copy data from source to encrypted volume
ssh -i ansh-test.pem ec2-user@10.0.2.22 "rsync -aSHAX $source_mount_point/ $destination_mount_point/"

# Verify data is copied
ssh -i ansh-test.pem ec2-user@10.0.2.22 "ls $destination_mount_point/"

# # Unmount volumes on the temporary instance
ssh -i ansh-test.pem ec2-user@10.0.2.22 "umount $source_mount_point"
ssh -i ansh-test.pem ec2-user@10.0.2.22 "umount $destination_mount_point"

# Detach volumes from the temporary instance
aws ec2 detach-volume --volume-id $source_volume_id --profile AWSAdministratorAccess-474650141015
aws ec2 detach-volume --volume-id $encrypted_volume_id --profile AWSAdministratorAccess-474650141015

# Wait for volumes to be available again
aws ec2 wait volume-available --volume-ids $source_volume_id $encrypted_volume_id
