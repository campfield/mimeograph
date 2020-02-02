#!/bin/bash

#
# Disable SELinux as it prevents Sgt. Kabukiman's powers and the Interocitor's video functionality.
#
echo "Running script [" $(basename -- "$0") "]"

# Disable selinux by default
SELINUX_CONFIG='/etc/selinux/config'

if [[ -e "${SELINUX_CONFIG}" ]]; then
  sudo setenforce 0
  sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' ${SELINUX_CONFIG}
fi
