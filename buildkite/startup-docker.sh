#!/bin/bash
#
# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euxo pipefail

# Wait for all snaps to become available.
snap wait system seed.loaded

# Ubuntu 18.04 installs gcloud, gsutil, etc. commands in /snap/bin
export PATH=$PATH:/snap/bin

# If available: Use the local SSD as fast storage.
if [[ -e /dev/nvme0n1 ]]; then
  mkfs.xfs -f -m rmapbt=1 -m reflink=1 /dev/nvme0n1
  mount /dev/nvme0n1 /mnt

  # Move over our working directories to the SSD and then mount them back into the original path.
  for dir in bazelbuild buildkite-agent docker; do
    rsync -aHAX "/var/lib/${dir}/" "/mnt/${dir}/"
    mount --bind "/mnt/${dir}" "/var/lib/${dir}"
  done
fi

# Start Docker.
systemctl start docker

# Get the Buildkite Token from GCS and decrypt it using KMS.
BUILDKITE_TOKEN=$(gsutil cat "gs://bazel-encrypted-secrets/buildkite-agent-token.enc" | \
  gcloud kms decrypt --location global --keyring buildkite --key buildkite-agent-token --ciphertext-file - --plaintext-file -)

# Insert the Buildkite Token into the agent configuration.
sed -i "s/token=\"xxx\"/token=\"${BUILDKITE_TOKEN}\"/" /etc/buildkite-agent/buildkite-agent.cfg

# Fix permissions of the Buildkite agent configuration files and hooks.
chmod 0400 /etc/buildkite-agent/buildkite-agent.cfg
chmod 0500 /etc/buildkite-agent/hooks/*
chown -R buildkite-agent:buildkite-agent /etc/buildkite-agent

# Start the Buildkite agent service.
systemctl start buildkite-agent

exit 0
