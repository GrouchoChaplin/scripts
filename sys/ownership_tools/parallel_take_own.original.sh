#!/bin/env bash 

# 1️⃣ Change ownership of everything under the target directory in parallel
USER_NAME="$(id -un)"
GROUP_NAME="$(id -gn)"

echo "USER_NAME:  ${USER_NAME}"
echo "GROUP_NAME: ${GROUP_NAME}"

sudo bash -c "parallel -j\"$(nproc)\" chown -vR ${USER_NAME}:${GROUP_NAME} ::: /run/media/peddycoartte/MasterBackup/Projects/* && \
              parallel -j\"$(nproc)\" chmod -vR o-rwx ::: /run/media/peddycoartte/MasterBackup/Projects/*"


# 2️⃣ Harden permissions (remove world access) for the same items, also in parallel
#sudo bash -c 'parallel -j"$(nproc)" chmod -vR o-rwx ::: /run/media/peddycoartte/MasterBackup/Projects/*'
