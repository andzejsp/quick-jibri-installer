#!/bin/bash
# Jibri Node Aggregator
# Original script by SwITNet Ltd © - 2020, https://switnet.net/
#
# This is a fork script by andzejsp
# GPLv3 or later.


# My personal additions
#
# Removed "#Make sure the file name is the required one" check
# Added moreutils to requirements download list
# Added descriptions/comments to ### 0_VAR_DEF that needs to be edited
# Removed "ssh -i /home/jibri/jbsync.pem $MJS_USER@$MAIN_SRV_DOMAIN "rm -r \$LJF_PATH"" in finalize_recording.sh
# Added additional conditions for finalize_recording.sh
# Added call-status-checks {} to jibri.conf.
# Removed from "echo -e "\n---- Create random nodesync user ----"" to "#Enable jibri services"
# Removed from "echo -e "\nSending updated add-jibri-node.sh file to main server sync user...\n"" to "echo "Rebooting in...""
# Added echo and dpkg-reconfigure xserver-xorg-legacy selection before "echo "Rebooting in..."
# Added "Do you want to reboot (y/n)"


while getopts m: option
do
    case "${option}"
    in
        m) MODE=${OPTARG};;
        \?) echo "Usage: sudo ./add_jibri_node.sh [-m debug]" && exit;;
    esac
done

#DEBUG
if [ "$MODE" = "debug" ]; then
set -x
fi

#Check admin rights
if ! [ "$(id -u)" = 0 ]; then
   echo "You need to be root or have sudo privileges!"
   exit 0
fi

### 0_VAR_DEF
## Change TBD values to your personal values
MAIN_SRV_DIST=TBD # Default - focal - for Ubuntu20.04
MAIN_SRV_REPO=TBD # Default - stable
MAIN_SRV_DOMAIN=TBD # Jitsi-meet server location or ip or fqdn
JibriBrewery=TBD # Default - JibriBrewery
JB_NAME=TBD # Prosody Jibri account on Jitsi-meet server
JB_AUTH_PASS=TBD # Prosody jibri account pass on Jitsi-meet server
JB_REC_PASS=TBD # Prosody recorder account pass on Jitsi-meet server
MJS_USER=TBD # SSH User on Jitsi-meet server
MJS_USER_PASS=TBD # SSH Password on Jitsi-meet server 
### ---------------------------------------------
THIS_SRV_DIST=$(lsb_release -sc)
JITSI_REPO=$(apt-cache policy | awk '/jitsi/&&/stable/{print$3}' | awk -F / 'NR==1{print$1}')
START=0
LAST=0 # Number of last jibri node so that they have their own number and wont conflict with each other
JIBRI_CONF="/etc/jitsi/jibri/jibri.conf"
DIR_RECORD="/var/jbrecord"
REC_DIR="/home/jibri/finalize_recording.sh"
CHD_VER="$(curl -sL https://chromedriver.storage.googleapis.com/LATEST_RELEASE)"
GOOGL_REPO="/etc/apt/sources.list.d/dl_google_com_linux_chrome_deb.list"
GOOGLE_ACTIVE_REPO=$(apt-cache policy | awk '/chrome/{print$3}' | awk -F "/" 'NR==1{print$2}')
GCMP_JSON="/etc/opt/chrome/policies/managed/managed_policies.json"
PUBLIC_IP="$(dig -4 @resolver1.opendns.com ANY myip.opendns.com +short)"
NJN_RAND_TAIL="$(tr -dc "a-zA-Z0-9" < /dev/urandom | fold -w 4 | head -n1)"
NJN_USER="jbnode${ADDUP}_${NJN_RAND_TAIL}"
NJN_USER_PASS="$(tr -dc "a-zA-Z0-9#_*=" < /dev/urandom | fold -w 32 | head -n1)"
GITHUB_RAW="https://raw.githubusercontent.com"
GIT_REPO="andzejsp/quick-jibri-installer"
TEST_JIBRI_ENV="$GITHUB_RAW/$GIT_REPO/unstable/tools/test-jibri-env.sh"
### ---------------------------------------------
### ---------------------------------------------
### Additional settings for mattermost and nextcloud for use in finalize_recordings.sh
## If you dont use any of these services and dont need to upload to nextcloud or post to mattermost then change settings bellow to "no" and you dont have to configure the rest of the mattermost or nextcloud settings
USE_MATTERMOST="yes" # If "yes" then after recording either bot or webhook will post a message on mattermost about the details of recording. If "no" then nothing will be posted.
USE_MATTERMOST_BOT_TO_POST="yes" # Uses bot account and bot access token to post to mattermost. If "no" then uses bot access token and webhook url to post on mattermost. Bot access token is needed in any case to fetch usrname of the recorded participants. The bot account must be in system admin role/group om mattermost server.
USE_NEXTCLOUD="yes" # If "yes" then after recording it uploads the .mp4 file to nextcloud. If "no" then there is no need to post on mattermost because there wont be a link to your recording because recording wont be accessible to outside network.
USE_REMOVE_LOCAL_RECORDING_DIR="yes" # removes local recording (.mp4, .json) after it is uploaded to nextcloud
# NEXTCLOUD Credidentials - These needs to be edited
## Nextcloud server address
NC_SRV_DOMAIN="https://your.domain.com" 	
## Nextcloud server folder to keep all the recordings/recording folders, if folder dont exists it will be created.	
NC_SHARED_RECORDINGS_FOLDER="<RECORDINGS>" 
## Nextcloud account username with upload permissions	
NC_USER="<user>" 
## Nextcloud account password							
NC_PASS="<pass>" 					 		
# Mattermost Credidentials - These needs to be edited
## Mattermost api url - http://your.domain.com/api/v4
MM_API_URL='http://your.domain.com/api/v4'
## Mattermost bot token to be able to login and fetch userdata
MM_BOT_TOKEN='<bot access token - not token id>'
MM_WEBHOOK_URL="<mattermost incomming webhook url>"
MM_WEBHOOK_USERNAME="<Webhook username that will be displayed on the post>"
MM_WEBHOOK_ICON_URL="<webhook icon url>" #Default is commented out to use icon defined in mattermost
# Mattermost channel name lowercases, spaces replaced with '-' --> team-one
MM_TEAM_NAME="team-name"
# Mattermost channel name lowercases, spaces replaced with '-' --> town-square
MM_CHANNEL_NAME="channel-name"
## Locales for message constructor - These needs to be edited
MEETING_LOCALE="Meeting"
PARTICIPANTS_LOCALE="Participants"
DOWNLOAD_LOCALE="Download recording here"
## Loacales for card constructor - These needs to be edited
INFO_LOCALE="Information"
MEETING_ID="Meeting ID"
#Jibri nickname randomizer. Dont change this
RAND_STR=$(openssl rand -hex 12)
# Jibri nickname
JB_NICKNAME_RND="Live-$RAND_STR"
### ---------------------------------------------
### ---------------------------------------------
### 1_VAR_DEF

# sed limiters for add-jibri-node.sh variables
var_dlim() {
    grep -n $1 add-jibri-node.sh|head -n1|cut -d ":" -f1
}

check_var() {
    if [ "$2" = "TBD" ]; then
        echo -e "Check if variable $1 is set: \xE2\x9C\x96"
        exit
    else
        echo -e "Check if variable $1 is set: \xE2\x9C\x94"
    fi
}


echo "
#-----------------------------------------------------------------------
# Checking initial necessary variables...
#-----------------------------------------------------------------------"

JMS_DATA=($MAIN_SRV_DIST \
          $MAIN_SRV_REPO \
          $MAIN_SRV_DOMAIN \
          $JibriBrewery \
          $JB_NAME \
          $JB_AUTH_PASS \
          $JB_REC_PASS \
          $MJS_USER \
          $MJS_USER_PASS)

JMS_EVAL=${JMS_DATA[0]}
for i in "${JMS_DATA[@]}"; do
    if [[ "$JMS_EVAL" != "$i" ]]; then
        ALL_TBD="no"
        break
    fi
done
if [ "$ALL_TBD" = "no" ];then
 echo -e "Good, seems this is not a vanilla copy of add-jibri-node.sh,
let's check variables ...\n"
else
 echo -e "You seem to be using a vanilla copy of the add-jibri-node.sh.
  > Please use the content (or apply the changes) of add-jibri-node.sh from
    the main Jitsi server installation folder, as it contains necessary data.\n"
        exit
fi

check_var MAIN_SRV_DIST "$MAIN_SRV_DIST"
check_var MAIN_SRV_REPO "$MAIN_SRV_REPO"
check_var MAIN_SRV_DOMAIN "$MAIN_SRV_DOMAIN"
check_var JibriBrewery "$JibriBrewery"
check_var JB_NAME "$JB_NAME"
check_var JB_AUTH_PASS "$JB_AUTH_PASS"
check_var JB_REC_PASS "$JB_REC_PASS"
check_var MJS_USER "$MJS_USER"
check_var MJS_USER_PASS "$MJS_USER_PASS"

#Check server and node OS
if [ ! "$THIS_SRV_DIST" = "$MAIN_SRV_DIST" ]; then
    echo "Please use the same OS for the jibri setup on both servers."
    echo "This server is based on: $THIS_SRV_DIST"
    echo "The main server record claims is based on: $MAIN_SRV_DIST"
    exit
fi

#Check system resources
echo "Verifying System Resources:"
if [ "$(nproc --all)" -lt 4 ];then
  echo "
Warning!: The system do not meet the minimum CPU requirements for Jibri to run.
>> We recommend 4 cores/threads for Jibri!
"
  CPU_MIN="N"
else
  echo "CPU Cores/Threads: OK ($(nproc --all))"
  CPU_MIN="Y"
fi
### Test RAM size (8GB min) ###
mem_available=$(grep MemTotal /proc/meminfo| grep -o '[0-9]\+')
if [ ${mem_available} -lt 7700000 ]; then
  echo "
Warning!: The system do not meet the minimum RAM requirements for Jibri to run.
>> We recommend 8GB RAM for Jibri!
"
  MEM_MIN="N"
else
  echo "Memory: OK ($((mem_available/1024)) MiB)"
  MEM_MIN="Y"
fi
if [ "$CPU_MIN" = "Y" ] && [ "$MEM_MIN" = "Y" ];then
    echo "All requirements seems meet!"
    echo "
    - We hope you have a nice recording/streaming session
    "
else
    echo "CPU ($(nproc --all))/RAM ($((mem_available/1024)) MiB) does NOT meet minimum recommended requirements!"
    echo "Since this is a Jibri node installation there is no point on not having the necessary resources."
    echo "We highly advice to increase the resources in order to install this Jibri node."
    while [[ "$CONTINUE_LOW_RES" != "yes" && "$CONTINUE_LOW_RES" != "no" ]]
    do
    read -p "> Do you want to continue?: (yes or no)"$'\n' -r CONTINUE_LOW_RES
    if [ "$CONTINUE_LOW_RES" = "no" ]; then
        echo "See you next time with more resources!..."
        exit
    elif [ "$CONTINUE_LOW_RES" = "yes" ]; then
        echo "Please keep in mind that we might not support underpowered nodes."
    fi
    done
fi

# Rename hostname for each jibri node
hostnamectl set-hostname "jbnode${RAND_STR}.${MAIN_SRV_DOMAIN}"
sed -i "1i 127.0.0.1 jbnode${RAND_STR}.${MAIN_SRV_DOMAIN}" /etc/hosts

# Jitsi-Meet Repo
echo "Add Jitsi repo"
if [ -z "$JITSI_REPO" ]; then
    echo "deb http://download.jitsi.org $MAIN_SRV_REPO/" > /etc/apt/sources.list.d/jitsi-$MAIN_SRV_REPO.list
    wget -qO -  https://download.jitsi.org/jitsi-key.gpg.key | apt-key add -
elif [ ! "$JITSI_REPO" = "$MAIN_SRV_REPO" ]; then
    echo "Main and node servers repository don't match, extiting.."
    exit
elif [ "$JITSI_REPO" = "$MAIN_SRV_REPO" ]; then
    echo "Main and node servers repository match, continuing..."
else
    echo "Jitsi $JITSI_REPO repository already installed"
fi

# Requirements
echo "We'll start by installing system requirements this may take a while please be patient..."
apt-get update -q2
apt-get dist-upgrade -yq2

apt-get -y install \
                    apt-show-versions \
                    bmon \
                    curl \
                    ffmpeg \
                    git \
                    htop \
                    inotify-tools \
                    jq \
                    rsync \
                    ssh \
                    unzip \
                    wget \
					          moreutils

check_snd_driver() {
echo -e "\n# Checking ALSA - Loopback module..."
echo "snd-aloop" | tee -a /etc/modules
modprobe snd-aloop
if [ "$(lsmod | grep snd_aloop | head -n 1 | cut -d " " -f1)" = "snd_aloop" ]; then
    echo "
#-----------------------------------------------------------------------
# Audio driver seems - OK.
#-----------------------------------------------------------------------"
else
    echo "
#-----------------------------------------------------------------------
# Your audio driver might not be able to load.
# We'll check the state of this Jibri with our 'test-jibri-env.sh' tool.
#-----------------------------------------------------------------------"
curl -s $TEST_JIBRI_ENV > /tmp/test-jibri-env.sh
#Test tool
  if [ "$MODE" = "debug" ]; then
    bash /tmp/test-jibri-env.sh -m debug
  else
    bash /tmp/test-jibri-env.sh
  fi
rm /tmp/test-jibri-env.sh
read -n 1 -s -r -p "Press any key to continue..."$'\n'
fi
}

echo "# Check and Install HWE kernel if possible..."
HWE_VIR_MOD=$(apt-cache madison linux-image-generic-hwe-$(lsb_release -sr) 2>/dev/null|head -n1|grep -c "hwe-$(lsb_release -sr)")
if [ "$HWE_VIR_MOD" = "1" ]; then
    apt-get -y install \
    linux-image-generic-hwe-$(lsb_release -sr)
else
    apt-get -y install \
    linux-image-generic \
    linux-modules-extra-$(uname -r)
fi

echo "
#--------------------------------------------------
# Install Jibri
#--------------------------------------------------
"
apt-get -y install \
                jibri \
                openjdk-8-jre-headless

echo "# Installing Google Chrome / ChromeDriver"
if [ "$GOOGLE_ACTIVE_REPO" = "main" ]; then
    echo "Google repository already set."
else
    echo "Installing Google Chrome Stable"
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
    echo "deb http://dl.google.com/linux/chrome/deb/ stable main" | tee $GOOGL_REPO
fi
apt-get -q2 update
apt-get install -y google-chrome-stable
rm -rf /etc/apt/sources.list.d/dl_google_com_linux_chrome_deb.list

if [ -f /usr/local/bin/chromedriver ]; then
    echo "Chromedriver already installed."
else
    echo "Installing Chromedriver"
    wget -q https://chromedriver.storage.googleapis.com/$CHD_VER/chromedriver_linux64.zip -O /tmp/chromedriver_linux64.zip
    unzip /tmp/chromedriver_linux64.zip -d /usr/local/bin/
    chown root:root /usr/local/bin/chromedriver
    chmod 0755 /usr/local/bin/chromedriver
    rm -rf /tpm/chromedriver_linux64.zip
fi

echo "
Check Google Software Working...
"
/usr/bin/google-chrome --version
/usr/local/bin/chromedriver --version | awk '{print$1,$2}'

echo '
########################################################################
                        Start Jibri configuration
########################################################################
'
echo "
Remove Chrome warning...
"
mkdir -p /etc/opt/chrome/policies/managed
echo '{ "CommandLineFlagSecurityWarningsEnabled": false }' > $GCMP_JSON

# Additions to finalize_recording.sh
#-----------------------------------------------
#-----------------------------------------------

MATTERMOST_BOT_TO_POST_CODE()
{
  cat << 'EOF_MATTERMOST_BOT_TO_POST_CODE'


#MATTERMOST_BOT_TO_POST_CODE
# This script is for posting a message with participants and recording on mattermost channel using bot account. 
# You need to have a bot-account registered on mattermost server and have access-token not token-id
# Mattermost CVARS - These needs to be edited
## Mattermost api url - http://your.domain.com/api/v4
MMAPI_URL=$MM_API_URL

## Mattermost bot token to be able to login and fetch userdata
MMBOT_TOKEN=$MM_BOT_TOKEN

## Get Mattermost BOT ID
MMBOT_ID=$(curl -s -H 'authorization: Bearer '$MMBOT_TOKEN $MMAPI_URL/users/me | jq -r '.id')

# Mattermost channel name lowercases, spaces replaced with '-' --> team-one
MMTEAM_NAME=$MM_TEAM_NAME

# Mattermost channel name lowercases, spaces replaced with '-' --> town-square
MMCHANNEL_NAME=$MM_CHANNEL_NAME

## Get Mattermost Channel ID
MMCHANNEL_ID=$(curl -s -H 'authorization: Bearer '$MMBOT_TOKEN $MMAPI_URL/channels | jq -r '.[] | select(.team_name== "'$MMTEAM_NAME'") |select(.name== "'$MMCHANNEL_NAME'").id')

# CVARS
## Date 
DAT=$(date +"%d.%m.%Y | %T")

## Get Files from the recording folder

MANIFEST_FILE_DIR=$(find $NJF_PATH -name '*.json')
URL_TO_RECORDING=$NC_RECORDING_SHARE_LINK

## Gets meeting url from manifest.json
MEETING_URL=$(jq -r '.meeting_url' $MANIFEST_FILE_DIR)

## Get only the meetingname - Jitsi meeting ID
MEETING_NAME=$(echo $MEETING_URL | cut -d'/' -f4- )

## Gets list of participants from manifest.json
PARTICIPANTS_NAME=$(jq -r '.participants[] | .user | .name' $MANIFEST_FILE_DIR)
PARTICIPANTS_ID=$(jq -r '.participants[] | .user | .id' $MANIFEST_FILE_DIR)

## Gets formated usernames from PARTICIPANTS_ID

### Function to get usernames
Get_formated_usernames()
{
for usr in $PARTICIPANTS_ID
do
curl -s -H 'authorization: Bearer '$MMBOT_TOKEN $MMAPI_URL/users/$usr | jq -r '.username' | ts '@' | tr -d ' '
done
}

## Set usernames into a one string
PARTICIPANTS_USERNAME_FORMATED="$(Get_formated_usernames | awk '{ printf("%s ", $0) }')"

## Message constructor
T_BUILDER="#### #"$MEETING_LOCALE": "$DAT"\n\n"$PARTICIPANTS_LOCALE": "$PARTICIPANTS_USERNAME_FORMATED"\n\n"$DOWNLOAD_LOCALE": [:open_file_folder:]("$URL_TO_RECORDING")"

## Card constructor
C_BUILDER="## "$INFO_LOCALE"\n---\n##### "$MEETING_ID": *"$MEETING_NAME"*\n##### "$PARTICIPANTS_LOCALE": "$PARTICIPANTS_USERNAME_FORMATED"\n"

# Incomming Webhook constructor
card=${C_BUILDER}
text=${T_BUILDER}

## Create Webhook data object
Generate_post_data()
{
  cat <<EOF
{
	"channel_id": "$MMCHANNEL_ID",
	"props": {
		"attachments": [
			{
				"text": "$text"
			}
		],
		"card": "$card"
	}
}
EOF
}

# Sends a webhook to mattermost
curl -i -X POST -H 'Content-Type: application/json' --data "$(Generate_post_data)"  -H 'Authorization: Bearer '$MMBOT_TOKEN $MMAPI_URL/posts
EOF_MATTERMOST_BOT_TO_POST_CODE
}
#-----------------------------------------------
#-----------------------------------------------

#-----------------------------------------------
#-----------------------------------------------
MATTERMOST_WEBHOOK_TO_POST_CODE()
{
  cat << 'EOF_MATTERMOST_WEBHOOK_TO_POST_CODE'


# MATTERMOST_WEBHOOK_TO_POST_CODE
# This script is for posting a message with participants and recording on mattermost channel using bot account. 
# You need to have a bot-account registered on mattermost server and have access-token not token-id
# Mattermost CVARS - These needs to be edited
## Mattermost api url - http://your.domain.com/api/v4
MMAPI_URL=$MM_API_URL

## Mattermost bot token to be able to login and fetch userdata
MMBOT_TOKEN=$MM_BOT_TOKEN

## Get Mattermost BOT ID
MMBOT_ID=$(curl -s -H 'authorization: Bearer '$MMBOT_TOKEN $MMAPI_URL/users/me | jq -r '.id')

# Mattermost channel name lowercases, spaces replaced with '-' --> team-one
MMTEAM_NAME=$MM_TEAM_NAME

# Mattermost channel name lowercases, spaces replaced with '-' --> town-square
MMCHANNEL_NAME=$MM_CHANNEL_NAME

## Get Mattermost Channel ID
MMCHANNEL_ID=$(curl -s -H 'authorization: Bearer '$MMBOT_TOKEN $MMAPI_URL/channels | jq -r '.[] | select(.team_name== "'$MMTEAM_NAME'") |select(.name== "'$MMCHANNEL_NAME'").id')

# CVARS
## Date 
DAT=$(date +"%d.%m.%Y | %T")

## Get Files from the recording folder

MANIFEST_FILE_DIR=$(find $NJF_PATH -name '*.json')
URL_TO_RECORDING=$NC_RECORDING_SHARE_LINK

## Gets meeting url from manifest.json
MEETING_URL=$(jq -r '.meeting_url' $MANIFEST_FILE_DIR)

## Get only the meetingname - Jitsi meeting ID
MEETING_NAME=$(echo $MEETING_URL | cut -d'/' -f4- )

## Gets list of participants from manifest.json
PARTICIPANTS_NAME=$(jq -r '.participants[] | .user | .name' $MANIFEST_FILE_DIR)
PARTICIPANTS_ID=$(jq -r '.participants[] | .user | .id' $MANIFEST_FILE_DIR)

## Gets formated usernames from PARTICIPANTS_ID

### Function to get usernames
Get_formated_usernames()
{
for usr in $PARTICIPANTS_ID
do
curl -s -H 'authorization: Bearer '$MMBOT_TOKEN $MMAPI_URL/users/$usr | jq -r '.username' | ts '@' | tr -d ' '
done
}

## Set usernames into a one string
PARTICIPANTS_USERNAME_FORMATED="$(Get_formated_usernames | awk '{ printf("%s ", $0) }')"

## Message constructor
T_BUILDER="#### #"$MEETING_LOCALE": "$DAT"\n\n"$PARTICIPANTS_LOCALE": "$PARTICIPANTS_USERNAME_FORMATED"\n\n"$DOWNLOAD_LOCALE": [:open_file_folder:]("$URL_TO_RECORDING")"

## Card constructor
C_BUILDER="## "$INFO_LOCALE"\n---\n##### "$MEETING_ID": *"$MEETING_NAME"*\n##### "$PARTICIPANTS_LOCALE": "$PARTICIPANTS_USERNAME_FORMATED"\n"

# Incomming Webhook constructor
card=${C_BUILDER}
text=${T_BUILDER}

# Incomming Webhook constructor
webhook_url="$MM_WEBHOOK_URL"
channel="$MM_CHANNEL_NAME" # Default channel "town-square"
username="$MM_WEBHOOK_USERNAME"
#icon_url="$MM_WEBHOOK_ICON_URL" #Can be commented out, then webhook img will be used
card=${C_BUILDER}
text=${T_BUILDER}

## Create Webhook data object
Generate_post_data()
{
  cat <<EOF
{
  "channel": "$channel",
  "username": "$username",
  "text": "$text",
  "icon_url": "$icon_url",
     "props": {
    "card": "$card"
  }
}
EOF
}

# Sends a webhook to mattermost
curl -i -X POST -H 'Content-Type: application/json' --data "$(Generate_post_data)" $webhook_url

EOF_MATTERMOST_WEBHOOK_TO_POST_CODE
}
#-----------------------------------------------
#-----------------------------------------------

#-----------------------------------------------
#-----------------------------------------------
NEXTCLOUD_UPLOAD_CODE()
{
  cat << 'EOF_NEXTCLOUD_UPLOAD_CODE'


# NEXTCLOUD_UPLOAD_CODE
# Create the shared folder to keep all recordings/recording folders on nextcloud
curl -u $NC_USER:$NC_PASS -X MKCOL "$NC_SRV_DOMAIN/nextcloud/remote.php/dav/files/$NC_USER/$NC_SHARED_RECORDINGS_FOLDER/$NJF_NAME"

# Upload file to nextcloud
curl -u $NC_USER:$NC_PASS -T "$NJF_PATH/$NJF_NAME.mp4" "$NC_SRV_DOMAIN/nextcloud/remote.php/dav/files/$NC_USER/$NC_SHARED_RECORDINGS_FOLDER/$NJF_NAME/$NJF_NAME.mp4"

# Generate shared link
NC_RECORDING_SHARE_LINK=$(curl -u $NC_USER:$NC_PASS -H "Accept: application/json" -H "OCS-APIRequest: true" -X POST "$NC_SRV_DOMAIN/ocs/v1.php/apps/files_sharing/api/v1/shares" -d path="/RECORDINGS/$NJF_NAME" -d shareType=3 -d permissions=1 | jq -r '.ocs.data.url')

echo "---------------------------"
echo "Recording can be found on: $NC_RECORDING_SHARE_LINK"
echo "---------------------------"
EOF_NEXTCLOUD_UPLOAD_CODE
}
#-----------------------------------------------
#-----------------------------------------------

#-----------------------------------------------
#-----------------------------------------------

REMOVE_LOCAL_RECORDING_DIR_CODE()
{
  cat << 'EOF_REMOVE_LOCAL_RECORDING_DIR_CODE'


# REMOVE_LOCAL_RECORDING_DIR_CODE
# Remove local recording direcotry and show whats being removed on stdout
rm -rv $NJF_PATH
EOF_REMOVE_LOCAL_RECORDING_DIR_CODE
}
#-----------------------------------------------
#-----------------------------------------------

# Do Some checks befor adding code to finalize_recordings.sh
CODE_TO_WRITE=''
if [ $USE_NEXTCLOUD = 'yes' ]; then
CODE_TO_WRITE+=$(NEXTCLOUD_UPLOAD_CODE)

	if [ $USE_MATTERMOST = 'yes' ]; then

		if [ $USE_MATTERMOST_BOT_TO_POST = 'yes' ]; then

		CODE_TO_WRITE+=$(MATTERMOST_BOT_TO_POST_CODE)

		else
		CODE_TO_WRITE+=$(MATTERMOST_WEBHOOK_TO_POST_CODE)

		fi

	fi
	if [ $USE_REMOVE_LOCAL_RECORDING_DIR = 'yes' ]; then
		CODE_TO_WRITE+=$(REMOVE_LOCAL_RECORDING_DIR_CODE)
	fi
fi




# Recording directory
if [ ! -d $DIR_RECORD ]; then
mkdir $DIR_RECORD
fi
chown -R jibri:jibri $DIR_RECORD

cat << REC_DIR > $REC_DIR
#!/bin/bash

RECORDINGS_DIR=$DIR_RECORD

chmod -R 770 \$RECORDINGS_DIR

#Rename folder.
LJF_PATH="\$(find \$RECORDINGS_DIR -exec stat --printf="%Y\t%n\n" {} \; | sort -n -r|awk '{print\$2}'| grep -v "meta\|-" | head -n1)"
NJF_NAME="\$(find \$LJF_PATH |grep -e "-"|sed "s|\$LJF_PATH/||"|cut -d "." -f1)"
NJF_PATH="\$RECORDINGS_DIR/\$NJF_NAME"

##Prevent empty recording directory failsafe
if [ "\$LJF_PATH" != "\$RECORDINGS_DIR" ]; then
  mv \$LJF_PATH \$NJF_PATH
else
  echo "No new folder recorded, not removing anything."
fi

## Additions
MM_API_URL="$MM_API_URL"
MM_BOT_TOKEN="$MM_BOT_TOKEN"
MM_WEBHOOK_URL="$MM_WEBHOOK_URL"
MM_WEBHOOK_USERNAME="$MM_WEBHOOK_USERNAME"
MM_WEBHOOK_ICON_URL="$MM_WEBHOOK_ICON_URL"
MM_TEAM_NAME="$MM_TEAM_NAME"
MM_CHANNEL_NAME="$MM_CHANNEL_NAME"

NC_SRV_DOMAIN="$NC_SRV_DOMAIN"
NC_SHARED_RECORDINGS_FOLDER="$NC_SHARED_RECORDINGS_FOLDER"
NC_USER="$NC_USER"
NC_PASS="$NC_PASS"


## Locales for message constructor - These needs to be edited
MEETING_LOCALE="$MEETING_LOCALE"
PARTICIPANTS_LOCALE="$PARTICIPANTS_LOCALE"
DOWNLOAD_LOCALE="$DOWNLOAD_LOCALE"

## Loacales for card constructor - These needs to be edited
INFO_LOCALE="$INFO_LOCALE"
MEETING_ID="$MEETING_ID"


## Aditional code
$CODE_TO_WRITE


exit 0
REC_DIR
chown jibri:jibri $REC_DIR
chmod +x $REC_DIR

## New Jibri Config (2020)
mv $JIBRI_CONF ${JIBRI_CONF}-dpkg-file
cat << NEW_CONF > $JIBRI_CONF
// New XMPP environment config.
jibri {
    chrome {
        // The flags which will be passed to chromium when launching
        flags = [
          "--use-fake-ui-for-media-stream",
          "--start-maximized",
          "--kiosk",
          "--enabled",
          "--disable-infobars",
          "--autoplay-policy=no-user-gesture-required",
          "--ignore-certificate-errors",
          "--disable-dev-shm-usage"
        ]
    }
    recording {
         recordings-directory = $DIR_RECORD
         finalize-script = $REC_DIR
    }
    api {
        xmpp {
            environments = [
                {
                // A user-friendly name for this environment
                name = "$JB_NAME"

                // A list of XMPP server hosts to which we'll connect
                xmpp-server-hosts = [ "$MAIN_SRV_DOMAIN" ]

                // The base XMPP domain
                xmpp-domain = "$MAIN_SRV_DOMAIN"

                // The MUC we'll join to announce our presence for
                // recording and streaming services
                control-muc {
                    domain = "internal.auth.$MAIN_SRV_DOMAIN"
                    room-name = "$JibriBrewery"
                    nickname = "$JB_NICKNAME_RND"
                }

                // The login information for the control MUC
                control-login {
                    domain = "auth.$MAIN_SRV_DOMAIN"
                    username = "jibri"
                    password = "$JB_AUTH_PASS"
                }

                // An (optional) MUC configuration where we'll
                // join to announce SIP gateway services
            //    sip-control-muc {
            //        domain = "domain"
            //        room-name = "room-name"
            //        nickname = "nickname"
            //    }

                // The login information the selenium web client will use
                call-login {
                    domain = "recorder.$MAIN_SRV_DOMAIN"
                    username = "recorder"
                    password = "$JB_REC_PASS"
                }

                // The value we'll strip from the room JID domain to derive
                // the call URL
                strip-from-room-domain = "conference."

                // How long Jibri sessions will be allowed to last before
                // they are stopped.  A value of 0 allows them to go on
                // indefinitely
                usage-timeout = 0 hour

                // Whether or not we'll automatically trust any cert on
                // this XMPP domain
                trust-all-xmpp-certs = true
                }
            ]
        }
    }
	call-status-checks {
    // If all clients have their audio and video muted and if Jibri does not
    // detect any data stream (audio or video) comming in, it will stop
    // recording after NO_MEDIA_TIMEOUT expires.
    // no-media-timeout = 10 seconds

    // If all clients have their audio and video muted, Jibri consideres this
    // as an empty call and stops the recording after ALL_MUTED_TIMEOUT expires.
    all-muted-timeout = 10 minutes

    // When detecting if a call is empty, Jibri takes into consideration for how
    // long the call has been empty already. If it has been empty for more than
    // DEFAULT_CALL_EMPTY_TIMEOUT, it will consider it empty and stop the recording.
    default-call-empty-timeout = 5 seconds
    }
}
NEW_CONF


#Enable jibri services
systemctl enable jibri
systemctl enable jibri-xorg
systemctl enable jibri-icewm

check_snd_driver

echo "
-------------------------------------------
We are about to configure xserver-xorg-legacy. If you are using VM and Ubuntu desktop installation this has to be set to anybody.
"
sleep 3
echo -n "Are you running Ubuntu desktop installation (y/n)? "
read answer

if [ "$answer" != "${answer#[Yy]}" ] ;then
    echo "Yes was chosen"
	echo "We are about to launch xserver-xorg-legacy configuration." 
	echo "Please select Anybody for jibri to run correctly.."
	sleep 5
	dpkg-reconfigure xserver-xorg-legacy
else
    echo "No was chosen"
	echo "Continuing with jibri installation.."
	sleep 2
fi

echo "
#########################################################################
#                        Node addition complete!!
#########################################################################
"
echo "

Jibri conf file is found here:"
echo $JIBRI_CONF

echo "

Jibri finalize_recording.sh file is found here:"
echo $REC_DIR

echo "

Jibri recordings folder is found here:"
echo $DIR_RECORD

# Test Bot or webhook on mattermsot

if [ $USE_MATTERMOST = 'yes' ]; then

if [ $USE_MATTERMOST_BOT_TO_POST = 'yes' ]; then
# Post a success post as bot
# ------------------------------------------------------------------
## Get Mattermost Channel ID
MM_CHANNEL_ID=$(curl -s -H 'authorization: Bearer '$MM_BOT_TOKEN $MM_API_URL/channels | jq -r '.[] | select(.team_name== "'$MM_TEAM_NAME'") |select(.name== "'$MM_CHANNEL_NAME'").id')

## Message constructor
T_BUILDER_BOT="Hello,\nYour Jibri node ***[ "$JB_NICKNAME_RND" ]*** \nhas been set up correctly!\n\nJibri conf file is found here: ***[ "$JIBRI_CONF" ]***\nJibri finalize_recording.sh file is found here: ***[ "$REC_DIR" ]***\nJibri recordings folder is found here: ***[ "$DIR_RECORD" ]***\n\nAdditional settings:\n\nUSE_MATTERMOST=***[ "$USE_MATTERMOST" ]***\nUSE_MATTERMOST_BOT_TO_POST=***[ "$USE_MATTERMOST_BOT_TO_POST" ]***\nUSE_NEXTCLOUD=***[ "$USE_NEXTCLOUD" ]***\nUSE_REMOVE_LOCAL_RECORDING_DIR=***[ "$USE_REMOVE_LOCAL_RECORDING_DIR" ]***"

# Incomming Webhook constructor
text_BOT=${T_BUILDER_BOT}

## Create Webhook data object
Generate_post_data_BOT()
{
  cat <<EOF_BOT
{
  "channel_id": "$MM_CHANNEL_ID",
  "props": {
    "attachments": [
      {
        "text": "$text_BOT"
      }
    ]
  }
}
EOF_BOT
}

# Sends a webhook to mattermost
curl -i -X POST -H 'Content-Type: application/json' --data "$(Generate_post_data_BOT)"  -H 'Authorization: Bearer '$MM_BOT_TOKEN $MM_API_URL/posts

# ------------------------------------------------------------------
echo "Posting to mattermost as Bot"
else
# Post a success post as incomming webhook
# ------------------------------------------------------------------
# Incomming Webhook constructor

T_BUILDER_HOOK="Hello,\nYour Jibri node ***[ "$JB_NICKNAME_RND" ]*** \nhas been set up correctly!\n\nJibri conf file is found here: ***[ "$JIBRI_CONF" ]***\nJibri finalize_recording.sh file is found here: ***[ "$REC_DIR" ]***\nJibri recordings folder is found here: ***[ "$DIR_RECORD" ]***\n\nAdditional settings:\n\nUSE_MATTERMOST=***[ "$USE_MATTERMOST" ]***\nUSE_MATTERMOST_BOT_TO_POST=***[ "$USE_MATTERMOST_BOT_TO_POST" ]***\nUSE_NEXTCLOUD=***[ "$USE_NEXTCLOUD" ]***\nUSE_REMOVE_LOCAL_RECORDING_DIR=***[ "$USE_REMOVE_LOCAL_RECORDING_DIR" ]***"

# Incomming Webhook constructor
text_HOOK=${T_BUILDER_HOOK}

## Create Webhook data object
Generate_post_data_HOOK()
{
  cat <<EOF_HOOK
{
  "channel": "$MM_CHANNEL_NAME",
  "username": "Jibri node installer",
  "text": "$text_HOOK"
}
EOF_HOOK
}

# Sends a webhook to mattermost
curl -i -X POST -H 'Content-Type: application/json' --data "$(Generate_post_data_HOOK)" $MM_WEBHOOK_URL

# ------------------------------------------------------------------
echo "Posting to mattermost as webhook"

fi

fi


echo "
#########################################################################
#                        Settings are set
#########################################################################
"

echo -n "Do you want to reboot (y/n)? "
read answer
if [ "$answer" != "${answer#[Yy]}" ] ;then

echo "Rebooting in..."
secs=$((15))
while [ $secs -gt 0 ]; do
   echo -ne "$secs\033[0K\r"
   sleep 1
   : $((secs--))
done
reboot

else
    echo "Restarting jibri"
    systemctl restart jibri

fi
