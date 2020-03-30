#!/bin/bash

if [ -d "./Pihole-Deploy" ]
then
    echo "Download folder already exists.  Deleting..."
    rm -rf ./Pihole-Deploy
fi

echo "Downloading installation files..."
git clone https://github.com/jasonhaymond/Pihole-Deploy.git

cd ./Pihole-Deploy
sh ./install.sh | tee ./piholeinstall.log
finish

finish()
{
    # Cleanup code goes here.
    echo "Cleaning up..."
}
trap finish exit