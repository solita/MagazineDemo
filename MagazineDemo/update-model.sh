#!/bin/bash

S3_MODEL_PATH=s3://magazine-monitor/Models
MODEL_PLIST_FILE=Model.plist
MODEL_FILE=bitti.mlmodel

# The timestamp is encoded in the model filename in the format YYYY-MM-DD-HH-MM-SS.
# Parse the AWS S3 listing, find the model files, and extract the latest timestamp.
LATEST_MODEL_TIMESTAMP=$(aws s3 ls $S3_MODEL_PATH/ --profile $AWS_PROFILE | grep "bitti-*" | tr -s ' ' | cut -d' ' -f4 | cut -c7-25 | sort -r | head -n 1)
echo "Latest model timestamp = $LATEST_MODEL_TIMESTAMP"

# Get the latest model timestamp we used from the Model.plist file.
# Initially this plist file should contain an epoch timestamp that is older than all the actual deployed models.
# You can initialize the plist file with `/usr/libexec/PlistBuddy -c "Set: Timestamp 2021-01-01-00-00-00"`.
CURRENT_MODEL_TIMESTAMP=$(/usr/libexec/PlistBuddy -c "Print :Timestamp" $MODEL_PLIST_FILE)
echo "Current model timestamp = $CURRENT_MODEL_TIMESTAMP"

if [ $LATEST_MODEL_TIMESTAMP > $CURRENT_MODEL_TIMESTAMP ]; then
    echo "Newer model is available, downloading from S3"
    aws s3 cp $S3_MODEL_PATH/bitti-$LATEST_MODEL_TIMESTAMP.mlmodel $MODEL_FILE --profile $AWS_PROFILE
    /usr/libexec/PlistBuddy -c "Set :Timestamp $LATEST_MODEL_TIMESTAMP" $MODEL_PLIST_FILE
    echo "Model timestamp updated to $(/usr/libexec/Plistbuddy -c "Print :Timestamp" $MODEL_PLIST_FILE)"
    git add bitti.mlmodel
    git commit -m "Core ML model updated to latest version"
else
    echo "Model is current"
fi
