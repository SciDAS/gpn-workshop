#!/bin/sh

# Prime SRA Toolkit
printf '/LIBS/GUID = "%s"\n' `uuidgen` > /root/.ncbi/user-settings.mkfg

# Get Index
export INDEX=${HOSTNAME##*-}
INDEX=$((INDEX+1))
echo ${INDEX}

# Get SRA ID to pull
ID=$(sed "${INDEX}q;d" $1)
echo ${ID}

# Pull SRA ID
prefetch ${ID} && fasterq-dump ${ID}/${ID}.sra --split-files -O /workspace/gemmaker/input/ --force
