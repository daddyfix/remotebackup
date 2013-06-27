#!/bin/bash

# This Script uses SCP tp copy config files (see array of files below)
# from a remote machine. Remote host must have /root/.ssh/id_rsa.pub (local) stored
# at /root/.ssh/authorized_keys2 (remote)
# http://www.howtogeek.com/66776/how-to-remotely-copy-files-over-ssh-without-entering-your-password/
#
# Author:	Michael Connors
# Date:		May 22 2013
#

# -----------------------------------------------------------------------
#
# Load Config Files
#
#
CONFIGS=( 	'remotebackup.cfg'
	  	'remotebackup_servers.cfg' )
echo "Reading config files...." >&2
for conf in "${CONFIGS[@]}"
do
	if [ ! -f $conf ]; then
    	echo -e "$conf config file not found!"
    	exit
	fi
	source $conf
done


# -----------------------------------------------------------------------
#
# Execute Command and determine exit status
# 
# usage: safeRunCommand "rm test"
#
function safeRunCommand {
	typeset cmnd="$1"
	typeset ret_code

	# IF DEBUG is on OR ARG $2 Doesnt exist then
	if [ $DEBUG = "ON" ] || [[ -z "$2" ]]; then

		echo -en "$cmnd " >&2
		eval $cmnd
	else
		echo -en "$2 " >&2
		eval "$cmnd 2>/dev/null"
	fi 

	ret_code=$?
	if [ $ret_code != 0 ]; then
		if [ $ret_code = 30 ]; then
			echo -en "[ ${LRED}Server unreachable ($ret_code) Timed-out${RESTORE} ]\n" >&2
		elif [ $ret_code = 23 ]; then
			echo -en "[ ${LBLUE}File/Folder does not exist ($ret_code)${RESTORE} ]\n" >&2
		else
			echo -en "[ ${LRED}Error Code: $ret_code${RESTORE} ]\n" >&2
		fi
	else
		echo -e "[ ${GREEN}OK${RESTORE} ]" >&2
	fi
}

# -----------------------------------------------------------------------
#
# Establish Log file
# 
# LOGFILE="$(date +%Y%m%d).log"
#
LOG="$LOGPATH/$LOGFILE"
# Check log path
if [ ! -d "$LOGPATH" ]; then
	safeRunCommand "mkdir $LOGPATH" "Making Log Folder: ${YELLOW}$LOGPATH${RESTORE}"
fi
if [ -f $LOG ]; then
    safeRunCommand "rm $LOG" "Deleting todays log file: ${YELLOW}$LOG${RESTORE}"
fi
exec >  >(tee -a $LOG)
exec 2> >(tee -a $LOG >&2)


# -----------------------------------------------------------------------
#
# Verify Save Directory exists
# 
#
# Check path
if [ ! -d "$SAVEDIR" ]; then
	safeRunCommand "mkdir $SAVEDIR" "Making Save Folder: ${YELLOW}$SAVEDIR${RESTORE}"
fi

# -----------------------------------------------------------------------
#
# Loop Through Server and get files
#
#
function getFiles {

	# Exclude the path to saved files
	typeset excluded="$OUTDIR"

	# Arguments to pass ( files is a string separated by spaces, string remotehost, string saveDirectory)
	IFS=' ' read -a assets <<< "${1}"
	typeset remotehost="$2"
	typeset outdir="$3"

	# Loop through files and scp download
	for onefile in "${assets[@]}"
	do
		# getDirectory="scp -r -i /root/.ssh/id_rsa $REMOTEHOST:$onefile $OUTDIR/"
		# safeRunCommand $getDirectory
		#echo -en  "\nscp -o ConnectTimeout=5 -r -i /root/.ssh/id_rsa $REMOTEHOST:$onefile $OUTDIR/" "Getting: ${YELLOW}$onefile${RESTORE}"
		#return 0
		
		if [ "$DEBUG" = "ON" ]; then
			safeRunCommand "rsync -avzR --timeout=5 --exclude '$excluded' --exclude '*.gz' -e 'ssh -i /root/.ssh/id_rsa' $remotehost:$onefile $outdir/" "Getting: ${YELLOW}$onefile${RESTORE}"
		else
			safeRunCommand "rsync -azR --timeout=5 --exclude '$excluded' --exclude '*.gz' -e 'ssh -i /root/.ssh/id_rsa' $remotehost:$onefile $outdir/" "Getting: ${YELLOW}$onefile${RESTORE}"
		fi
	done
}

# -----------------------------------------------------------------------
#
# NMap server and check if its reachable
#
#
function checkServer {
	typeset server=$1
	#$SERVERSTATE="closed"
	#echo -en "\nSERVERSTATE=nmap $server -PN -p ssh | egrep 'open|closed|filtered'"
	echo -en "\n\nChecking Port 22: "
	serverupdown=$(nmap $server -PN -p ssh | egrep 'open|closed|filtered')

	#if eval "nmap $server -PN -p ssh | grep 'open' &>/dev/null" &>/dev/null
	if [[ "$serverupdown" == *open* ]]
	then
		echo -en "[ ${GREEN}OPEN${RESTORE} ]" >&2
		SERVERSTATE="open"
	else
		echo -en " $serverupdown [ ${RED}DOWN${RESTORE} ]" >&2
		SERVERSTATE="Unreachable"
	fi
	wait
}

# -----------------------------------------------------------------------
#
# Check if program exists
#
#
function checkProg {
	#eval "command -v foo >/dev/null 2>&1 || { echo 'I require foo but it's not installed. Aborting.'' >&2; exit 1; }"
	typeset prog=$1

	echo -en "\n${YELLOW}$prog${RESTORE} "

	if command -v $prog &>/dev/null
    then
            echo -en "[ ${GREEN}OK${RESTORE} ]"
    else
            echo -en "[ ${LRED}Not Found.${RESTORE} ] Is it Installed?\nExiting...\n"
            exit
    fi
    wait
}

# -----------------------------------------------------------------------
#
# Display Header
#
#
function displayHeader {
	# Args passed ( string RemoteHost, string path/to/output
	typeset HOST="$1"
	typeset OUT="$2"
	echo -en "\n----------------------------------------------------------\n$(date)" >&2
	echo -en "\nHost: ${YELLOW}$HOST${RESTORE}" >&2
	echo -en "\nOutput: ${YELLOW}$OUT${RESTORE}" >&2
	echo -en "\n----------------------------------------------------------" >&2
	wait
}

# -----------------------------------------------------------------------
#
# ASK: User Input
#
# User Input Yes or No returns true or false
# https://gist.github.com/davejamesmiller/1965569
#
function ask {
    while true; do
 
        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi
 
        # Ask the question
        read -p "$1 [$prompt] " REPLY
 
        # Default?
        if [ -z "$REPLY" ]; then
            REPLY=$default
        fi
 
        # Check if the reply is valid
        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
 
    done
}

# -----------------------------------------------------------------------
#
# Email log
#
#
function cleanLogNEmail {
	#${string/pattern/replacement}
	# Strip COLOR CODES in the log. I like color.
	safeRunCommand "sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' $LOG > temp.log" "Cleaning log: $LOG"
	safeRunCommand "mv temp.log $LOG" "Saving cleaned log file"
	safeRunCommand "$MYMAIL" "Emailing $LOG to ${YELLOW}$TO_ADDR${RESTORE}"
}

# -----------------------------------------------------------------------
#
# HELP?
# Check if Argument passed is --help then display help and exit
#
#
if [ "$1" = "--help" ]
then
	echo -en "${GREEN}"
	echo -e 'Usage: remotebackup.sh\n'
	echo -en "${RESTORE}"
	echo 'This script downloads the following files from servers using Rsync'
	
	# Display List of Servers with File list
	for i in "${!SERVERS2D[@]}"
	do
		echo -en "\n\n$i\nFiles: ${YELLOW}${SERVERS2D[$i]}${RESTORE}"
	done

	echo -e '\nFor ONE SERVER ONLY use the following. Files list is used from remotebackup_servers.cfg:'
	echo -e 'Usage: get-pi-configs.sh [root@someserver.com]'

	echo -en "${YELLOW}"
	echo -e '\nREAD MORE in script file\n'
	echo -en "${RESTORE}"
	exit
fi

# -----------------------------------------------------------------------
#
# If number of Arguments passed is NOT equal to 1 then
# assume backup of all servers
#
#
if [ $# -ne 1 ]
then
	echo -en "Debugger: ${YELLOW}$DEBUG${RESTORE}"

        # Display List of Servers with File list
        for i in "${!SERVERS2D[@]}"
        do
                echo -en "\n$i\nFiles: ${YELLOW}${SERVERS2D[$i]}${RESTORE}"
        done

	echo -en "\n\nBackup Path: ${YELLOW}$OUTDIR[servername]${RESTORE}\n\n"

	if [ "$DEBUG" = "ON" ]; then
		if ! ask "Backup Files from these Servers to the Path?" Y; then
			echo -e 'Exiting...\n' >&2
			exit
		fi
	fi
	ONESERVER=0
fi

# -----------------------------------------------------------------------
#
# if number of arguments is equal to 1 then
# assume only one server to be backed up 
# arg string user@server
#
#
if [ $# -eq 1 ]; then
	ONESERVER=1
fi



# -----------------------------------------------------------------------
#
# THE MEAT OF THE SCRIPT
#
# 

#TEST OF 2D ARRAY --------------
#for i in "${!SERVERS2D[@]}"
#do
#  echo "key  : $i"
#  IFS=' ' read -a assets <<< "${SERVERS2D[$i]}"
#  for asset in "${assets[@]}"
#  do
#  		echo "Server: $i, $asset"
#  done
#  echo "value: ${servers[$i]}"
#done
#exit
# END TEST-----------------------

# First check that we have all the programs needed to run the script
echo -en "------------------------------------------------------------\nChecking for installed programs..." >&2
for needed in "${PROGRAMS[@]}"
do
	checkProg $needed
done

if [ $ONESERVER -eq 1 ]
then
	REMOTEHOST=$1
	SERVERNAME=${REMOTEHOST#*@}
	SERVERPATH="$OUTDIR$SERVERNAME"

	SAVECONFIG=$SAVEDIR$SERVERNAME
	# prepare one file for tarball by replacing [oneserver] with $Servername
	TAR=${TARONESERVER/'[oneserver]'/$SERVERNAME}

	# It doesnt matter what SKIP is. We are only doing one HOST
	displayHeader $REMOTEHOST $SERVERPATH

	# Check if Server is awake on port 22 for SSH
	checkServer $SERVERNAME

	if [[ "$SERVERSTATE" == "open" ]]; then
		echo -e "\n" >&2

		GOTFILES=0
		# check if the server is in the array of servers list.
		#   If found then backup the files noted
		#   If not found then use the FILES noted in cfg
		for i in "${!SERVERS2D[@]}"
		do
			if [[ "$i" == "$REMOTEHOST" ]]; then
				echo -en "${LRED}*** Found server in cfg, using files found. ***${RESTORE}\n"
				getFiles "${SERVERS2D[$i]}" $REMOTEHOST $SERVERPATH
				GOTFILES=1
				break
			fi
		done
		if [ $GOTFILES -eq 0 ]; then
			getFiles "$FILES" $REMOTEHOST $SERVERPATH
		fi
	else
		if [[ "$SERVERSTATE" == *filtered* ]]; then
			serverClosed="filtered"
		elif [[ "$SERVERSTATE" == *closed* ]]; then
			serverClosed="closed"
		else
			serverClosed=$SERVERSTATE
		fi
		echo -en "\nServer ${LRED}$serverClosed${RESTORE}. Exiting...\n" >&2
		wait
		exit 1
	fi
else
        TAR=$TARCOMPRESSED
        SAVECONFIG=$SAVEDIR

	# Loop thorugh Servers
	for server in "${!SERVERS2D[@]}"
	do
		REMOTEHOST=${server#*@}
		SERVERPATH="$OUTDIR$REMOTEHOST"

		#echo -e "OUTDIR with HOSTNAME IS ->$SERVERPATH"
		displayHeader $server $SERVERPATH

		# Check if Server is awake on port 22 for SSH
		checkServer $REMOTEHOST
		#echo -en "Server State : $SERVERSTATE" >&2

		if [[ "$SERVERSTATE" == *open* ]]; then

			# We leave the string of files alone, we will parse it in getFiles

			echo -e "\n" >&2
			if [ "$DEBUG" = "ON" ]; then
				if ask "Skip?" N; then
					echo -e "Skipping Server: $server\n" >&2
				else
					getFiles "${SERVERS2D[$server]}" $server $SERVERPATH
				fi
			else
				getFiles "${SERVERS2D[$server]}" $server $SERVERPATH
			fi
		else
			if [[ "$SERVERSTATE" == *filtered* ]]; then
				serverClosed="filtered"
			elif [[ "$SERVERSTATE" == *closed* ]]; then
				serverClosed="closed"
			else
				serverClosed=$SERVERSTATE
			fi
			echo -en "\nServer ${LRED}$serverClosed${RESTORE}. Skipping..." >&2
		fi
	done
fi

# Now make a compressed file of the outdir and send to dropbox
#tar -zcvf configs_4_all_pi.tar.gz *
if [ "$DEBUG" = "ON" ]; then
	options="-zcvf"
else
	options="-zcf"
fi

echo -e "\n-------------------------------------------------------" >&2
safeRunCommand "tar $options $TAR $SAVECONFIG" "Compressing: ${YELLOW}$SAVECONFIG as $TAR${RESTORE}"

# Copy backup to Dropbox
#   checkProg $DROPBOXSCRIPT
safeRunCommand "dropbox_uploader.sh upload $TAR '$DROPBOXFOLDER$TAR'" "Uploading to Dropbox: ${YELLOW}$DROPBOXFOLDER$TAR${RESTORE}"

# Email the log results
cleanLogNEmail

echo -e '\nDone.' >&2
exit
