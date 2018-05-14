#!/bin/sh
#
# Execute the VividCortex agent binary, injecting environment variables with values from AWS SSM Parameter Store
#
set -e

# basic wrapper alias for segmentio/chamber for reading from AWS SSM Parameter Store:
alias chmbr='/usr/local/bin/chamber read -q ${chamber_service}'

export VC_API_TOKEN="$(chmbr agent-api-token)"
export VC_HOSTNAME="$(chmbr agent-hostname)"
export VC_DRV_MANUAL_HOST_URI="$(chmbr database-urls)"

/usr/local/bin/vc-agent-007 ${@}
