# create VM
gcloud compute instances create data-extraction-rec \
    --network default \
    --zone europe-west4-a \
    --labels=env=dev \
    --metadata-from-file startup-script=startup.sh

# connect to VM
gcloud compute ssh data-extraction-rec
mkdir codes & cd codes
mkdir -p .secrets
sudo mkdir /home/ga
sudo chmod 777 /home/ga
exit

# copy files
gcloud compute scp $(pwd)/.secrets/* data-extraction-rec:~/codes/.secrets/
gcloud compute scp $(pwd)/*R data-extraction-rec:~/codes/
gcloud compute scp $(pwd)/*json data-extraction-rec:~/codes/

# install R in VM
gcloud compute ssh data-extraction-rec
sudo add-apt-repository 'deb https://cloud.r-project.org/bin/linux/ubuntu bionic-cran40/'
sudo apt install r-base
sudo apt-get install libcurl4-openssl-dev
sudo apt-get update && sudo apt-get upgrade
sudo chmod 777 /usr/local/lib/R/site-library
cp -R ~/codes /home/ga & cd /home/ga/codes
Rscript app_vm.R
exit

# create pub/sub
gcloud pubsub topics create start-collecting-recdata-event
gcloud pubsub topics create stop-collecting-recdata-event

# create function
git clone https://github.com/GoogleCloudPlatform/nodejs-docs-samples.git
cd nodejs-docs-samples/functions/scheduleinstance/
cd scheduleinstance

gcloud functions deploy startInstancePubSub \
--trigger-topic start-collecting-recdata-event \
--runtime nodejs10 \
--allow-unauthenticated

gcloud functions deploy stopInstancePubSub \
--trigger-topic stop-collecting-recdata-event \
--runtime nodejs10 \
--allow-unauthenticated

# test functions
echo '{"zone":"europe-west4-a", "label":"env=dev"}' | base64
gcloud functions call startInstancePubSub \
      --data '{"data":"eyJ6b25lIjoiZXVyb3BlLXdlc3Q0LWEiLCAibGFiZWwiOiJlbnY9ZGV2In0K"}'
gcloud compute instances describe data-extraction-rec \
        --zone europe-west4-a \
        | grep status

# create google scheduler
# shoutdown vm at 23pm in the first day of every month
gcloud beta scheduler jobs create pubsub shutdown-collecting-rawdata-instances \
    --schedule '0 23 1 * *' \
    --topic stop-collecting-recdata-event \
    --message-body '{"zone":"europe-west4-a", "label":"env=dev"}' \
    --time-zone 'CET'
# startup vm at 8pm in the first day of every month
gcloud beta scheduler jobs create pubsub startup-collecting-rawdata-instances \
    --schedule '0 8 1 * *' \
    --topic start-collecting-recdata-event \
    --message-body '{"zone":"europe-west4-a", "label":"env=dev"}' \
    --time-zone 'CET'

# test scheduler
gcloud beta scheduler jobs run startup-collecting-rawdata-instances
gcloud compute instances describe data-extraction-rec \
        --zone europe-west4-a \
        | grep status
