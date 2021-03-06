#!/bin/bash

finish()
{
    # Cleanup code goes here.
    echo "Cleaning up..."
}
trap finish exit

if [ -d "./Pihole-Deploy" ]
then
    echo "Download folder already exists.  Deleting..."
    rm -rf ./Pihole-Deploy
fi

echo "Downloading installation files..."
git clone https://github.com/jasonhaymond/Pihole-Deploy.git

cd ./Pihole-Deploy
sh ./setup.sh | tee ./piholeinstall.log
finish