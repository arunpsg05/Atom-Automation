#!/bin/bash

#######################################################################################################
#
#  v.1 - Perform Operation based on input args
#  v.2 - Perform Admin, NM , OCCS-ADMIN URL , DB CHECKS
#  v.3 - Checks for Garceful exit of non-provisioned host, Remove Post-checks for stop
########################################################################################################

#set -e            ## Script exits incase of single non-zero exit code.
#set -o pipefail  ## Make sure all commands in chain are successfull.

################################################
##          PRE-DEFINED VARIABLES             ##
################################################

APP_USER=`grep 0c0 /etc/passwd | grep Application | awk -F: '{print $1}'`
APP_SID=`grep 0c0 /etc/passwd | grep Application | awk -F: '{print $1}' | sed 's|ia\(.*\)|\1|'`
APP_PREFIX=`grep 0c0 /etc/passwd | grep Application | awk -F: '{print $1}' | sed 's|ia[a-z]\(.*\)0c0|\1|'`

count=`printenv | grep "DOMAIN" | wc -l`

if [ $count -ne 0 ]; then
  if [[ -d "/$APP_SID/fmw" && ! -h "/$APP_SID/fmw/java" && ! -d "/$APP_SID/fmw/product" ]]; then
	echo "ENVIRONMENT IS NOT PROVISIONED"
	exit 0
  else
	DOMAIN_PATH=`printenv | grep -v "OHS" | grep "DOMAIN" | awk -F= '{print $2}'`
	DOMAIN_NAME=`basename $DOMAIN_PATH`
	DOMAIN_HOME="/$APP_SID/admin/user_projects/$(basename $DOMAIN_NAME)"
	JDBC_CFG="$DOMAIN_HOME/config/jdbc/"
  fi
elif [[ -d "/$APP_SID/fmw" && ! -h "/$APP_SID/fmw/java" && ! -d "/$APP_SID/fmw/product" ]]; then
	echo "ENVIRONMENT IS NOT PROVISIONED"
	exit 0
fi

BIN_PATH="/$APP_SID/admin/bin"
ATOM_PATH="/$APP_SID/fmw/atom"

LD_LIBRARY_PATH="/$APP_SID/admin/oracle1104client/instantclient_11_2"
PASSWD_MGR="/ptsadmin/ohscommerce/helpers/utils/passwdmgr/passwdmgr.sh"
PASS_CODE="12AHbk+25sam+YuYbTh1+//wqY4UvhJQ=="
PREFIX=`echo $PASS_CODE | awk -F+ '{print $1}'`
SUFFIX=`echo $PASS_CODE | awk -F+ '{print $2}'`
SCHMEA_PASS="${PREFIX: -3}${SUFFIX}"
LOGFILE="$ATOM_PATH/run.log"
VIEW_LOG_FILE="$ATOM_PATH/"

mkdir -p $ATOM_PATH

#if [ -f $ATOM_PATH/wlsinfo.txt ] ; then
#        rm -f "${ATOM_PATH}"/wlsinfo.txt
#fi

#if [ -f $ATOM_PATH/get_server_details.py ]; then
#       rm -f "${ATOM_PATH}"/get_server_details.py
#fi

#if [ -f $ATOM_PATH/log.txt ]; then
#       rm -f "${ATOM_PATH}"/log.txt
#fi

#if [ ! ls *capture.log > /dev/null 2>&1 ] ; then
#	 rm -f $ATOM_PATH/*capture.log
#fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\e[1;33;40m'
NC='\033[0m' # No Color

################################################
##             ASSIGNMENTS                    ##
################################################

atgd_option=$1
environment=$2
#echo "In GC" $atgd_option $environment

if [ -f $LOGFILE ] ; then
    rm $LOGFILE
fi

function print_usage(){
	echo -e "Scrip need two arguments as show below \n"
	echo -e "./Atgd-wrapper.sh <atgd_option> <environment> \n"
	echo -e "Values of the arguments can be given as below \n"
	echo -e "Example :   ./Atgd-wrapper.sh Restart-All <Prod|Sandbox|Test> \n"
	echo -e "                        ./Atgd-wrapper.sh Start-All <Prod|Sandbox|Test> \n"
	echo -e "                        ./Atgd-wrapper.sh Stop-All  <Prod|Sandbox|Test> \n"
	echo -e "                        ./Atgd-wrapper.sh Restart-Store <Prod|Sandbox|Test> \n"
	echo -e "                        ./Atgd-wrapper.sh Restart-Admin <Prod|Sandbox|Test> \n"
	echo -e "                        ./Atgd-wrapper.sh Start-Store <Prod|Sandbox|Test> \n"
	echo -e "                        ./Atgd-wrapper.sh Start-Admin <Prod|Sandbox|Test> \n"
	echo -e "                        ./Atgd-wrapper.sh Stop-Store <Prod|Sandbox|Test> \n"
	echo -e "                        ./Atgd-wrapper.sh Stop-Admin <Prod|Sandbox|Test> \n"
	echo -e "                        ./Atgd-wrapper.sh Start-Aux <Prod> \n"
	echo -e "                        ./Atgd-wrapper.sh Stop-Aux <Prod> \n"
	echo -e "                        ./Atgd-wrapper.sh Restart-Aux <Prod> \n"
	echo -e "Only in above combination script can take input , Note the \"<\" and \">\" in above example for environment arguments should be skipped and only one of those values should be entered\n"
}

function log_it(){

	string=$1
	echo -e "$string" >> $LOGFILE 2>&1
}
if [ $# -eq 0 ] ; then
		print_usage
		exit 0
fi

if [ -z "$environment" ]; then
		echo -e "Please enter anyone of these values:  Sandbox or Prod or Test"
		print_usage
		exit 0
fi

if [ -z "$atgd_option" ]; then
		print_usage
		exit 0
fi

if [[ -d "/$APP_SID/fmw" && ! -h "/$APP_SID/fmw/java" && ! -d "/$APP_SID/fmw/product" ]]; then
	echo "Environment Is not Provisioned"
	exit 0
fi

#### PRE_CHECK ATGD ONGOING OPERATIONS #####
#
function check_atg_lock(){

	RUNNING_COUNT=`ps -ef | grep "atgd.sh" | grep -v grep | wc -l`
	if [ $RUNNING_COUNT -gt 0 ]; then
		log_it "Already atgd.sh process running, A goal could be in progres"
		Progress=`$BIN_PATH/atgd.sh status | grep "progres" |grep -v grep | wc -l`
		if [ $Progress -gt 0 ] ; then
			goal=`$BIN_PATH/atgd.sh status | grep "progres" |grep -v grep`
			log_it "$goal"
			cat $LOGFILE
			rm $LOGFILE
		fi
		exit 0
	else
		return 0
	fi
}

#############################################

function Write_FILE(){

	OUT_FILE="$ATOM_PATH/get_server_details.py"
	echo -e "#!/usr/bin/python" >> $OUT_FILE
	echo -e "import sys,getopt" >> $OUT_FILE
	echo -e "import os" >> $OUT_FILE
	echo -e "import os.path" >> $OUT_FILE
	echo -e "import socket" >> $OUT_FILE
	echo -e "import time" >> $OUT_FILE

	echo -e "from urlparse import urlparse" >> $OUT_FILE
	echo -e "adminhost = os.environ.get('WLS_HOSTNAME', 'wlsadmin')" >> $OUT_FILE
	echo -e "adminport = os.environ.get(\"WLS_PORT\", \"9000\")" >> $OUT_FILE
	echo -e "adminusername  = os.environ.get('WLS_USER', 'weblogic')" >> $OUT_FILE
	echo -e "adminpass = os.environ.get(\"WLS_PASSWORD\", \"abcde\")" >> $OUT_FILE

	echo -e "#=======================================================================================" >> $OUT_FILE
	echo -e "# Connect to admin server" >> $OUT_FILE
	echo -e "#=======================================================================================" >> $OUT_FILE
	echo -e "connect(adminusername,adminpass,'t3://'+adminhost+\":\"+adminport)" >> $OUT_FILE
	
	echo -e "directory_path = sys.argv[1]" >> $OUT_FILE
	echo -e "name_of_file = 'wlsinfo'" >> $OUT_FILE
	echo -e "complete_file_path = os.path.join(directory_path, name_of_file+\".txt\")" >> $OUT_FILE
	echo -e "f = open(complete_file_path, \"w\")" >> $OUT_FILE
	echo -e "domainConfig()" >> $OUT_FILE
	echo -e "servers = cmo.getServers()" >> $OUT_FILE
	echo -e "for server in servers:" >> $OUT_FILE
	echo "      f.write(server.name + \"\t\" + str(server.getListenPort()) + \"\t\" + str(server.machine.name)+\"\n\")" >> $OUT_FILE
	echo -e "disconnect()" >> $OUT_FILE
	echo -e "f.close()" >> $OUT_FILE
}

function validate_environment_variables(){

	count=0
	input=$1
	wls_host=`echo $input | awk -F: '{print $1}'`
	if [[ `hostname -f` =~ $wls_host ]] ; then
		count=$(( $count + 1 ))
	else
		count=$(( $count - 1 ))
	fi

	wls_user=`echo $input | awk -F: '{print $3}'`

	if [ "$wls_user" == "occsadmin" ] ; then
		count=$(( $count + 1 ))
	else
		count=$(( $count - 1 ))
	fi

	if [ $count -eq 2 ]; then
		return 0
	else
		return 1
	fi
}

function get_weblogic_managed_server_info(){
	
	WLS_HOSTNAME=`hostname -f`
	
	if [ "$environment" == "Prod" ]; then
		WLS_PORT="3061"
	else
		WLS_PORT="5061"
	fi
	
	WLS_USER=$(${PASSWD_MGR} -getall | grep WLS_USER  	  | awk -F: '{print $2}')
	WLS_PASSWORD=$(${PASSWD_MGR} -getall | grep WLS_PASSWORD  | awk -F: '{print $2}')
	validate_environment_variables $WLS_HOSTNAME:$WLS_PORT:$WLS_USER:$WLS_PASSWORD
	
	if [ "$?" -ne 0 ]; then
		log_it "ENVIRONMENT VARIABLES NOT RIGHT"
		return 1
	fi
	CONFIG_JVM_ARGS="${CONFIG_JVM_ARGS} -Dweblogic.security.SSL.ignoreHostnameVerification=true"
	if [ ! -z $WL_HOME ]; then
		WLST="${WL_HOME}/common/bin/"
		cd $WLST
	fi
	
	Write_FILE
	
	if [ -f $ATOM_PATH/get_server_details.py ]; then
	
		export WLS_HOSTNAME=$WLS_HOSTNAME
		export WLS_PORT=$WLS_PORT
		export WLS_USER=$WLS_USER
		export WLS_PASSWORD=$WLS_PASSWORD
		if [ -d $ATOM_PATH ]; then
			if [ -f $ATOM_PATH/wlsinfo.txt ]; then
				rm $ATOM_PATH/wlsinfo.txt
				nohup ./wlst.sh -skipWLSModuleScanning $ATOM_PATH/get_server_details.py $ATOM_PATH > $ATOM_PATH/wlst_log.txt 2>&1 < /dev/null &
				pid=`echo $!`
			else
				nohup ./wlst.sh -skipWLSModuleScanning $ATOM_PATH/get_server_details.py $ATOM_PATH > $ATOM_PATH/wlst_log.txt 2>&1 < /dev/null &
				 pid=`echo $!`
			fi
		fi
		
		while kill -0 $pid 2> /dev/null ;
		do
			log_it "${GREEN} \t Gathering WLST Server Details from Weblogic ${NC}"
			sleep 5
		done
		wait $pid
		exit_status=$?
		if [ $exit_status -eq 0 ]; then
			echo 0
		else 
			echo 1
		fi
		
		rm $ATOM_PATH/wlst_log.txt $ATOM_PATH/get_server_details.py
	fi
}

function check_Admin_Node_availablity(){

	env=$1
	retval=0
	host=`hostname -f`
	ADMIN_STATE="true"
	NM_STATE="true"
        
	if [ "$env" == "Prod" ]; then
			ADMN_PORT="3061"
			  NM_PORT="3062"
	else
			ADMN_PORT="5061"
			  NM_PORT="5062"
	fi
        
	#Check if Admin ( AS ) is available to instaintiate a request for managed server
	log_it "###########################################################\n"
	log_it "#       CHECKING HEALTH OF ADMIN AND NODE MANAGER ...     #\n"
	log_it "###########################################################\n"
	ADM_COUNT=`ps -ef | grep AdminServer | grep $DOMAIN_NAME | grep -v grep | wc -l`
        
	if [ $ADM_COUNT -eq 1 ]; then
      
		if [ "$env" == "Prod" ]; then
				wget -q -t 1 --timeout=10 --delete-after http://$host:$ADMN_PORT/console
				val=`echo $?`
		else
				wget -q -t 1 --timeout=10 --delete-after http://$host:$ADMN_PORT/console
				val=`echo $?`
		fi
		if [ $val -eq 0 ]; then
			log_it "[+] ADMIN SERVER  *****  ${GREEN}[ RUNNING ]${NC}"
			ADMIN_STATE="true"
		else
			log_it "[+] ADMIN SERVER  *****  ${RED}[ NOT REACHABLE ]${NC}"
			log_it " Restarting now ..."
			cd  /$APP_SID/admin/bin/
			val=$( check_atg_lock )
			if [ $val -eq 0 ]; then
				./atgd.sh restart as >> $LOGFILE 2>&1 &
				pid=`echo $!`
				sleep 3
				wait $pid
				exit_status=$?
				if [ $exit_status -ne 0 ]; then
					log_it "Admin Restart command failed , checking admin server health.."
					wget -q -t 1 --timeout=10 --delete-after http://$host:$ADMN_PORT/console
					val=`echo $?`
					if  [ $val -ne 0 ]; then
						ADMIN_STATE="false"
						retval=1
					fi
				fi
			fi
		fi
	else
		log_it "[+] ADMIN SERVER  *****  ${RED}[ NOT RUNNING ]${NC}"
		log_it " STARTING NOW "
		/$APP_SID/admin/bin/atgd.sh start as >> $LOGFILE
		sleep 3
		wget -q -t 1 --timeout=10 --delete-after http://$host:$ADMN_PORT/console
		val=`echo $?`
		if  [ "$val" -ne 0 ]; then
				 ADMIN_STATE="false"
				 retval=1
		fi
	fi
        # Process to check Node manager running in all app hosts

	NM_HOSTS=`grep "<weblogic-node-manager" $BIN_PATH/environment-config.xml | sed 's|<.*\ host="\(.*\)"\ \/>|\1|' | sed 's/^[ \t\r]*//' | sed 's/[ \t\r]*$//' | sed '/^\s*$/d' | sort | uniq`
	OFS=$IFS
	IFS=$'\n'
	for server in ${NM_HOSTS} ; do
			   log_it "CHECKING TCP CONNECTION TO NM PORT ON MANAGED SERVERS : /dev/tcp/${server}/${NM_PORT} ....."
			   (echo > /dev/tcp/${server}/${NM_PORT}) > /dev/null 2>&1
			   state=`echo $?`
			   #echo $state
			   if [ $state -eq 0 ] ; then
					log_it "        (x) NODE MANNAGER  ******  ${GREEN}[ RUNNING ]${NC} in $server \n"
					retval=0
			   else
					log_it "        (x) NODE MANNAGER  ******  ${RED}[ NOT RUNNING ]${NC} in $server \n"
					log_it "STARTING NOW ..."
					NM_NAME=`cat /$APP_SID/admin/bin/environment-config.xml | grep "weblogic-node-manager" | grep $server | sed -e  's|<.*\ name="\(.*\)"\ \/>|\1|' | awk -F\" '{print $1}' | sed 's/^[ \t\r]*//' | sed 's/[ \t\r]*$//' | sed '/^\s*$/d' | sort | uniq`
					log_it "Node Manager Name is : $NM_NAME"
					/$APP_SID/admin/bin/atgd.sh start $NM_NAME >> $LOGFILE
					sleep 1
					(echo > /dev/tcp/${server}/${NM_PORT}) > /dev/null 2>&1
					state=`echo $?`
					if [ $state -eq 0 ] ; then
							log_it " (x) NODE MANNAGER  ******  ${GREEN}[ RUNNING ] AGAIN ${NC} in $server"
							retval=0
					else
							NM_STATE="false"
							retval=1
							break
					fi
			   fi
	done
	log_it "#################################################################################"
	IFS=$OFS
	#IFS==' \t\n'
	if [ "$ADMIN_STATE" == "true" ] && [ "$NM_STATE" == "true" ]; then
			## GET WEBLOGIC SERVER DETAILS
			val=$( get_weblogic_managed_server_info )
			if [ $val -eq 0 ]; then
				echo 0
			else
				echo 1
			fi
	else
			echo 1
	fi
	
    	log_it "############################################################################### \n"
}

function connect_DB(){

	DB_HOST=$1
	DB_PORT=$2
	DB_SRV_NAME=$3
	env=$4
	CLIENT=`echo /$APP_SID/admin/oracle1104client/instantclient_11_2`
	if [ ! -d $CLIENT ]; then
	  log_it "*** Quit: Oracle Client not found @ $CLIENT"
	  exit 1
	fi
	## NOW CONNECT TO SCHEMA AND TEST CONNECTIVITY
	conn1="$CLIENT/sqlplus -L '${SCHEMA_NAME}/${SCHMEA_PASS}@(DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = ${DB_HOST})(PORT = ${DB_PORT}))(CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = ${DB_SRV_NAME})))'"
	export LD_LIBRARY_PATH=$CLIENT:$LD_LIBRARY_PATH
	DOM=`hostname -d`
	OFS=$IFS
	IFS=$'\n'
	SCHEMAS_TO_TEST=`${PASSWD_MGR} -getall | grep "$APP_SID"_`
	run_val=`echo $?`
	FAILED=0
	if [ $run_val -eq 0 ]; then
			  if [ "$SCHEMAS_TO_TEST"X == "X" ]; then
					  log_it "PASSWORD MANAGER NOT SET WITH DB CREDENTIALS"
			  else
					  for SCHEMA_TO_TEST in ${SCHEMAS_TO_TEST}; do
							  echo $SCHEMA_TO_TEST
							  SCHEMA_NAME=`echo ${SCHEMA_TO_TEST} | awk -F: '{print $1}'`
							  SCHMEA_PASS=`echo ${SCHEMA_TO_TEST} | awk -F: '{print $2}'`
							  #sql=$( echo exit | sqlplus -L $username/$password@$APP_SID )
							  #count=$( echo $sql | grep Connected | wc -l )
							  conn1="$CLIENT/sqlplus -L '${SCHEMA_NAME}/${SCHMEA_PASS}@(DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = ${DB_HOST})(PORT = ${DB_PORT}))(CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = ${DB_SRV_NAME})))'"
							  count=`eval echo "exit | $conn1" | grep Connected | wc -l`
							  if [ $count -eq 1 ]; then
									  log_it ".... ${GREEN} (0) $SCHEMA_NAME successfully connected ${NC} ....\n"
							  else
									  log_it ".... ${RED} (0) $SCHEMA_NAME failed to connect : Reason : $( echo exit | echo $conn1 | grep "ORA*" ) ${NC} ...."
									  FAILED=$(( FAILED + 1 ))
							  fi
						done
				if [ $FAILED -gt 0 ]; then
							  log_it "SQLPLUS CONNECTION ATTEMPT FAILED , POSSIBLE REASON -- SYSTEM PASSWORD EXPIRED OR PASSWORD MGR HAVING WRONG PASSWORD"
							  echo "FAILURE"
				else
							  echo "SUCCESS"
				fi
	fi
	#(Pwd_mgr issue)
	else # ( Connecting directly to system User as last try ..)
					   log_it "PASSWORD MANAGER NOT WORKING"
					   log_it "TESTING DB CONNECTIVITY VIA SYS USER ...."
					   util="/ptsadmin/ohscommerce/helpers/utils"
					   SCHMEA_PASSS="12AkH+mas2+YuYbTh1+//wqY4UvhJQ=="
					   pass=`$util/crypto.sh -decrypt -s ${SCHMEA_PASSS}|head -1` > /dev/null 2>&1
					   conn1="$CLIENT/sqlplus -L 'system/${SCHMEA_PASS}@(DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = ${DB_HOST})(PORT = ${DB_PORT}))(CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = ${DB_SRV_NAME})))'"
					   count=`eval echo "exit | $conn1" | grep Connected | wc -l`
					   if [ $count -eq 1 ]; then
								log_it ".... ${GREEN} (0) system successfully connected ${NC} .... \n"
								echo "SUCCESS"
					   else
								log_it ".... ${RED} (0) system failed to connect : Reason : $( echo exit | echo $conn1 | grep "ORA*" ) ${NC} ...."
								echo "FAILURE"
					   fi
	fi

	IFS=$OFS
}


## TEST DB CONN FROM APPLICATION

function TEST_DB_CONN(){

	env=$1
	params=`grep -n "url" $JDBC_CFG/*.xml | head -1 | awk -F\<url\> '{print $2}' | awk -F\<\/url\> '{print $1}' | sed 's|.*(HOST = \(.*\))(PORT = \(.*\))).*(SERVICE_NAME = \(.*\))))|\1:\2:\3|'`
	DB_HOST=`echo $params | awk -F: '{print $1}'`
	DB_PORT=`echo $params | awk -F: '{print $2}'`
	DB_SRV_NAME=`echo $params | awk -F: '{print $3}'`

	log_it "[+] DB HOST IS: ${YELLOW}$DB_HOST${NC}\n"
	log_it "[+] DB PORT IS: ${YELLOW}$DB_PORT${NC}\n"
	log_it "[+] DB SERVICE NAME IS: ${YELLOW}$DB_SRV_NAME${NC}\n"
	log_it "###########################################################\n"
	log_it "#               TESTING DB CONNECTVITY...                 #\n"
	log_it "###########################################################\n"
	(echo > /dev/tcp/${DB_HOST}/${DB_PORT}) > /dev/null 2>&1
	state=`echo $?`
	#echo $state
	if [ $state -eq 0 ] ; then
			log_it "[+] TELNET CHECK  ****** ${GREEN}[ PASSED ]${NC}\n"
	else
			log_it "[+] TELNET CHECK  ****** ${RED}[ FAILED ]${NC}\n"
	fi
	## ANYWAYS DO A CHECK FOR SCHEMA CONNECTIVITY VIA SQLPLUS
	RET_CODE=$(connect_DB $DB_HOST $DB_PORT $DB_SRV_NAME $env)
	if [[ "$RET_CODE" =~ .*SUCCESS.* ]]; then
	   log_it "###########################################################\n"
	   log_it " RESULT ****** ${GREEN} SQL CONNECT PASSED ${NC} ******** \n"
	   log_it "###########################################################\n"
	   echo 0
	elif [[ "$RET_CODE" =~ .*FAILURE.* ]] ; then
	   log_it " RESULT ****** ${RED} SQL CONNECT FAILED  ${NC} ********** \n"
	   log_it "###########################################################\n"
	   echo 1
	fi
}

## TESTING APP CONNECTIVITY 

function TEST_APP_CONN(){

	#method to check url status/response code.
	#Arguments:-
	# 1. Application URL
        
	host=`hostname -f`
    env=$1
	instance=$2
	
	if [ "$env" == "Prod" ]; then
		if [ "$instance" == "admin1a" ]; then
			admin_applicationURL="https://ccadmin-prod-xxxx.oracleoutsourcing.com/occs-admin/"
			Local_admin_applicationURL="http://$host:3021/occs-admin/"
		else
			## Fetching Instance host and port from wlsinfo.txt
			if [ -f $ATOM_PATH/wlsinfo.txt ] ; then
				instance_host=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $3}'`
				instance_port=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $2}'`
				log_it "Instance: $instance_host $instance_port"
			fi
			Local_store_InstanceURL="http://$instance_host:$instance_port"
			STATUS_CODE=`curl --max-time 20 --output /dev/null --silent --head --write-out '%{http_code}\n' $Local_store_InstanceURL`
			if [[ $STATUS_CODE =~  20[0-9] ]]; then
						echo 0
			else
						echo 1
			fi			
		fi
	elif [ "$env" == "Test" ] ; then
			if [[ "$APP_SID" =~ ^[s|S].* ]] ; then
				if [ "$instance" == "test_admin1a" ]; then
						admin_applicationURL="https://ccadmin-stage-xxxx.oracleoutsourcing.com/occs-admin/"
						Local_admin_applicationURL="http://$host:5021/occs-admin/"
				else
						## Fetching Instance host and port from wlsinfo.txt
						if [ -f $ATOM_PATH/wlsinfo.txt ] ; then
							instance_host=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $3}'`
							instance_port=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $2}'`
							log_it "Instance: $instance_host $instance_port"
						fi
						Local_store_InstanceURL="http://$instance_host:$instance_port"
						STATUS_CODE=`curl --max-time 20 --output /dev/null --silent --head --write-out '%{http_code}\n' $Local_store_InstanceURL`
						if [[ $STATUS_CODE =~  20[0-9] ]]; then
									echo 0
						else
									echo 1
						fi	
				fi
			else
				if [ "$instance" == "test_admin1a" ]; then
						admin_applicationURL="https://ccadmin-test-xxxx.oracleoutsourcing.com/occs-admin/"
						Local_admin_applicationURL="http://$host:5021/occs-admin/"
				else
						## Fetching Instance host and port from wlsinfo.txt
						if [ -f $ATOM_PATH/wlsinfo.txt ] ; then
							instance_host=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $3}'`
							instance_port=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $2}'`
							log_it "Instance: $instance_host $instance_port"
						fi
						Local_store_InstanceURL="http://$instance_host:$instance_port"
						STATUS_CODE=`curl --max-time 20 --output /dev/null --silent --head --write-out '%{http_code}\n' $Local_store_InstanceURL`
						if [[ $STATUS_CODE =~  20[0-9] ]]; then
									echo 0
						else
									echo 1
						fi
				fi
			fi
	elif [ "$env" == "Sandbox" ] ; then
			if [ "$instance" == "test_admin1a" ]; then
				admin_applicationURL="https://ccadmin-xxxx.oracleoutsourcing.com/occs-admin/"
				Local_admin_applicationURL="http://$host:5021/occs-admin/"
			else
				## Fetching Instance host and port from wlsinfo.txt
				if [ -f $ATOM_PATH/wlsinfo.txt ] ; then
					instance_host=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $3}'`
					instance_port=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $2}'`
					log_it "Instance: $instance_host $instance_port"
				fi
				Local_store_InstanceURL="http://$instance_host:$instance_port"
				STATUS_CODE=`curl --max-time 20 --output /dev/null --silent --head --write-out '%{http_code}\n' $Local_store_InstanceURL`
				if [[ $STATUS_CODE =~  20[0-9] ]]; then
							echo 0
				else
							echo 1
				fi
			fi
	fi
     
	if [ ! -z "$admin_applicationURL" ] ; then 
		admin_applicationURL=`echo "$admin_applicationURL" | sed -e 's/xxxx/'"$APP_PREFIX"'/'`
		STATUS_CODE=`curl --max-time 20 --output /dev/null --silent --head --write-out '%{http_code}\n' $admin_applicationURL`
		
		if [[ $STATUS_CODE =~  20[0-9] || $STATUS_CODE =~ 226 || $STATUS_CODE =~ 302 ]]; then
				 echo 0
		else
				 log_it "${RED} ADMIN URL NOT RESPONDING TO CURL REQ -- trying Wget now ${NC}"
				 wget -q --delete -t 1 --timeout=10 $Local_admin_applicationURL
				 output=$?
				 if [ $output -eq 0 ]; then
						echo 0
				 else
						echo 1
				 fi
		fi
	fi
}

## BASELINE CHECK

function check_baseline(){

	dynadmin_password=$(${PASSWD_MGR} -getall | grep DYNADMIN_PASSWORD  | awk -F: '{print $2}')
	dynadmin_user=admin
	NODE_NAME=`hostname -f`
	if [ "$env" == "Prod" ]; then
			PORT_NUMBER="3021"
			Local_admin_applicationURL="http://$NODE_NAME:$PORT_NUMBER"
	else
			PORT_NUMBER="5021"
			Local_admin_applicationURL="http://$NODE_NAME:$PORT_NUMBER"
	fi
	STATUS_CODE=`curl --max-time 20 --output /dev/null --silent --head --write-out '%{http_code}\n' $Local_admin_applicationURL`
        
	if [[ $STATUS_CODE =~  20[0-9] ]]; then
		curl --user $dynadmin_user:$dynadmin_password --cookie-jar $ATOM_PATH/cookie.txt --silent http://$NODE_NAME:$PORT_NUMBER/dyn/admin
		SECONDS=0
		IN=1
		TIME_LAPSED=0
		end=$((SECONDS+7200))
		while [[ $SECONDS -lt $end ]];
		do
			 curl -s --cookie $ATOM_PATH/cookie.txt 'http://'$NODE_NAME':'$PORT_NUMBER'/dyn/admin/nucleus/atg/commerce/endeca/index/ProductCatalogSimpleIndexingAdmin/?renderStatus=true' > $ATOM_PATH/RESPONSE.log
			 sleep 3
			 ##Checking If no indexing is running ..
			 running_count=$(cat $ATOM_PATH/RESPONSE.log | grep "activelyIndexing" | grep "hidden" | grep true | wc -l)
			 if [ $running_count -eq 0 ];  then
					end_time=$(cat ${ATOM_PATH}/RESPONSE.log | grep "Finished:" | awk -F\< '{print $1}')
					if [ ! -z "$end_time" ]; then
						   log_it " ${GREEN} NO INDEXING RUNNING NOW , LAST ONE [[ $(cat ${ATOM_PATH}/RESPONSE.log | grep "Finished:" | awk -F\< '{print $1}') ]] ${NC}"
					else
						   curl -s --cookie $ATOM_PATH/cookie.txt 'http://'$NODE_NAME':'$PORT_NUMBER'/dyn/admin/nucleus/atg/commerce/endeca/index/ProductCatalogSimpleIndexingAdmin/?histIdx=0' > $ATOM_PATH/RESPONSE.log
						   finish_time=`awk '/Forced To Baseline/{print; nr[NR+5]; next}; NR in nr' ${ATOM_PATH}/RESPONSE.log | head -2 | sed -e 's|<.*>\(.*\)<\/.*>|\1|' | sed '/^\s*$/d' | sed 's/^[ \t\r]*//' | sed 's/[ \t\r]*$//' | awk -F\. '{print $1}' | grep -v "Forced To Baseline"`
						   log_it " ${GREEN} NO INDEXING RUNNING NOW , LAST ONE [[ ${finish_time} ]] ${NC}"
					fi
					echo 0
					break
			 else
				if [ $IN -eq 1 ]; then
					   log_it "**** ${RED} INDEXING RUNNING ,  --> [[ $(cat $ATOM_PATH/RESPONSE.log | grep "Started:" | awk -F\< '{print $1}') ]] ${NC}"
					   log_it "**** WAITING FOR INDEXING TO COMPLETE .... "
				else
					   #TIME_LAPSED=`echo "scale=2; $SUM / 60" |bc`
					   #MIN=`echo ${TIME_LAPSED} | awk -F\. '{print $1}'`
					   #SEC=`echo ${TIME_LAPSED} | awk -F\. '{print $2}'`
					   log_it "**** INDEXING RUNNING  *******"
				fi
				IN=$((IN + 1 ))
			 fi
			 SECONDS=$((SECONDS + 1))
			 sleep 10
			 #echo "SECOND #" $SECONDS
		done
	elif [ $STATUS_CODE == 401 ] ; then
		  log_it "${RED} DYN/ADMIN PASSWORD SEEMS TO BE INCORRECT ${NC}"
		  echo 0
	else
		  log_it "${RED} INSTANCE NOT REACHABLE ,  SO SKIPPING BASELINE CHECK! ${NC}"
		  echo 0
	fi
	if [ -f ATOM_PATH/cookie.txt ]; then
       		 rm $ATOM_PATH/cookie.txt
	fi
	if [ -f $ATOM_PATH/RESPONSE.log ]; then
        	rm $ATOM_PATH/RESPONSE.log
	fi
    log_it "################################################################ \n"
}

## PERFORM HEALTH CHECK

function pre_check(){

	retval=1
	atgd_path="$BIN_PATH"
	script_name="atgd.sh"
	script="$BIN_PATH/$script_name"
	env=$1
	DB_CONN_STATE=0
	APP_CONN_STATE=0
	operation=${2:-default}
	if [ "$env" == "Prod" ] ; then
		instance="admin1a"
	else
		instance="test_admin1a"
	fi
	if [ ! -d "$atgd_path" ]; then
			log_it "BIN DIRECTORY DOES NOT EXIST"
			exit 1
	else
			log_it "###########################################################\n"
			log_it "#             PRE-CHECK IN PROGRESS ......                #\n"
			log_it "###########################################################\n"
			if [ ! -f "$script" ] ; then
					log_it "ATGD.SH SCRIPT DOES NOT EXIST"
					exit 1
			else
					##CHECKING AS AND Node MANAGERS HEALTH

					ADM_NM_STATE=$( check_Admin_Node_availablity $env )
					#log_it "Return Value $ADM_NM_STATE"
					if [ $ADM_NM_STATE -eq 0 ]; then
							ADM_NM_STATE=0
					else
							ADM_NM_STATE=1
					fi
					##TESTING DB CONNECTIVITY FROM APP HOST'S
					## CHECK ONLY START , RESTART OPERATIONS
			
					if [ "$operation" == "default" ]; then
						DB_CONN_STATE=$( TEST_DB_CONN $env )
					
						if [ $DB_CONN_STATE -eq 0 ]; then
							DB_CONN_STATE=0
						else
							DB_CONN_STATE=1
						fi

						##PRE-CHECK STORE AND ADMIN APP HEALTH ....
					
						APP_CONN_STATE=$( TEST_APP_CONN $env $instance )
					
						if [ $APP_CONN_STATE -eq 0 ]; then
							APP_CONN_STATE=0
							log_it " RESULT ****** ${GREEN} OCCS-ADMIN URL RESPONDING ${NC} ******** ${NC} \n"
						else
							APP_CONN_STATE=1
							log_it " RESULT ****** ${RED} OCCS-ADMIN URL NOT RESPONDING TO CURL REQUEST ${NC} ******** ${NC} \n"
						fi
					fi
                        
					log_it "###########################################################\n"
					log_it "#            ATGD STATUS BEFORE OPERATION                 #\n"
					log_it "###########################################################\n"
					/usr/bin/time --format='%C took %e seconds' /$APP_SID/admin/bin/atgd.sh status >> $LOGFILE 2>&1 &
					pid=`echo $!`
                        
					if [ "$env" == "Prod" ]; then
								sleep 15
					else
								sleep 10
					fi
					SECONDS=0
					TIME_LAPSED=0
					ATGD_STATE=0
					end=$((SECONDS+50))
					while kill -0 $pid 2> /dev/null ;
					do
						if [[ $TIME_LAPSED -lt $end ]]; then
							  TIME_LAPSED=$(( TIME_LAPSED + 5 ))
							  sleep 5

						else
							log_it "Status command is running more than expected time , check if all instances are healthy \n"
							log_it "$pid is the Process ID for given command"
												
							#log_it "############################################################\n"
							#log_it "        PRE-CHECK DID NOT COMPLETE SUCCESSFULLY            \n"
							#log_it "###########################################################\n"
							ATGD_STATE=1
							if [ kill -0 $pid 2> /dev/null ] ; then
								kill -9 $pid
								break
							fi		
						fi
					done
			fi
     fi

	if [[ $ADM_NM_STATE -eq 0 && $DB_CONN_STATE -eq 0 ]] ; then
		if [ $ATGD_STATE -ne 1 ] ; then
			echo 0
		else
			echo 21
		fi
	else
		echo 1
	fi
	log_it "################################################################"
}

function parse_log(){

        SPLIT_LINE=$'\n'
        TAB=$'\t'
        INSTANCE=$1
        APP_SID=`grep 0c0 /etc/passwd | grep Application | awk -F: '{print $1}' | sed 's|ia\(.*\)|\1|'`
        VIEW_LOG_FILE=$ATOM_PATH/$INSTANCE"_ERROR.log"
        LOG_FILE="/$APP_SID/logs/weblogic/$INSTANCE.out"
        log_it "INFO: Extracting errors from logfile $LOG_FILE"
        log_it "####################################"
        ERR_STR1="**** Error${TAB}[A-Z][a-z][a-z]"
        ERR_STR2="SEVERE:"
        ERR_STR3="Exception"
        grep -B2 -A5 "$ERR_STR1\|$ERR_STR2\|$ERR_STR3" $LOG_FILE  > $VIEW_LOG_FILE 2>&1
        awk '/Error/||/Caused by/||/SEVERE/||/Exception/||/500: Internal Server/&&/SQL/||Unable to start service{gsub(/Error|Caused by|SEVERE|Exception|500: Internal Server|SQL|Unable to start service/,"\033[1;36m&\033[1;000m");print $0,"\n+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"}' $VIEW_LOG_FILE > $ATOM_PATH/$INSTANCE"_capture.log" 2>&1
		#grep -v "An account already exists for this email address. Please enter a different email address." $VIEW_LOG_FILE > $ATOM_PATH/$INSTANCE"_capture.log" 2>&1
        rm $VIEW_LOG_FILE
        log_it "######### Please see error's in HOST : `hostname -f` @ path : $ATOM_PATH/$INSTANCE"_capture.log" #######"
        log_it "########################################################################################################"
}

# Arguments:-
# 1.Satus code of the operation
# 2.Messge to be logged.
# 3.Continue execution - continue/stop
function check_execution(){
       server=$1
       exit_code=$2
       msg=$3
       if [ $exit_code -ne 0 ]; then
               log_it "WARN: $msg."
                log_it "WARN: Status code received is $exit_code."
                if [ $4 == "stop" ]; then
                        log_it "ERROR: Exiting the operation on $server because of unwanted behavior."
                        #exit $exit_code
                        $BIN_PATH/atgd.sh cancel
                fi
       fi
}


# Check Server state
# Arguments:-
# 1.log file directory
# 2.log file name
# 3.string to search for
function check_server_state(){
	state="xxx"
	find "$1" -type f -name "$2" | while read file
	do
	  RESULT=$(grep "$3" "$file")
	  #echo "RESULT IS $RESULT"
	  if [ ! -z "$RESULT" ];
	  then
		state=0
	  else
		state=1
	  fi
	  return "$state"
	done
}

# Check server status continuously for a period of time
# Arguments:-
# 1.log file directory
# 2.log file name
# 3.string to search for
# 4.max time to wait in seconds

function check_server_status_in_logs(){

	ctr=0
	trailer=9999
	maxtime=$4
	while [ $ctr -lt $maxtime ]
	do
		check_server_state "$1" "$2" "$3"
		status=$?
		#echo "status is $status"
		if [ "$status" == 0 ]
		then
			 trailer=1000
			 break
		fi
		ctr=`expr $ctr + 1`
	done

	if [ $trailer -eq 9999 ]
	then
			log_it "WARN: server operation failed in the stipulated time period.. exiting"
			#exit 1
	elif [ $trailer -eq 1000 ]
	then
			log_it "INFO: server status changed to required state"
	else
			log_it "WARN: you should not be seeing this"
	fi
}


function Timmer(){
		
	#log_it "In Timmer Function -- $1 $2"
	log_it "/$APP_SID/admin/bin/logs/last.log ::::"  
	ls -lrt /$APP_SID/admin/bin/logs/last.log >> $LOGFILE
	#log_file=`readlink -f /$APP_SID/admin/bin/logs/last.log`
	process_id=$1
	instance=$2
	job=$3
	sleep 1
	log_file=`ls -lrt /$APP_SID/admin/bin/logs/*?$job-$instance.log | tail -1 | grep -v last.log | awk '{print $9}'`
	log_it "Log File: ${YELLOW} $log_file ${NC}"
	log_it "Proces ID ${RED} $process_id ${NC}"
	log_it "Instance Name: ${GREEN} $instance ${NC} and ${GREEN} Operation is $3 ${NC}"
	
	if [ -f $ATOM_PATH/wlsinfo.txt ] ; then
		instance_host=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $3}'`
		instance_port=`cat $ATOM_PATH/wlsinfo.txt | grep "$instance" | awk '{print $2}'`
		log_it " HOST : ${YELLOW} $instance_host ${NC} and PORT : ${YELLOW} $instance_port ${NC}"
	fi
	i=0
	counter_reset=1
	Local_admin_applicationURL="http://$instance_host:$instance_port"
	while kill -0 $process_id 2> /dev/null ;
	do
		i=$(( $i + 1 ))
		sleep 10

	    if [ $counter_reset -ne 0 ]; then
			down_count=`cat $log_file | grep "%" | awk '{print $4}' | sed 's|/!\(.*\)%'$instance'|\1|' | wc -l`
	    fi
	  
		  #log_it "Down Count : $down_count"
		  
	   if [ $down_count -ge 5 ]; then
			log_it "Instance trying to go down for more than 5 attempts .."
			(echo > /dev/tcp/${instance_host}/${instance_port}) > /dev/null 2>&1
			val=`echo $?`
			if [ $val -ne 0 ]; then
				log_it "$instance Instance seems to be in bad state , moving data folder since process died "
				log_it "${RED} $DOMAIN_HOME/servers/$instance/data ---> $DOMAIN_HOME/servers/$instance/data_$(date +%s) ${NC}"
				mv $DOMAIN_HOME/servers/$instance/data $DOMAIN_HOME/servers/$instance/data_$(date +%s)
				counter_reset=0
				down_count=0
			fi
		fi	
	done
	## Capture Exit Code of the bg process ( Equivalent to atgd return status codes )
	wait $process_id
	exit_status=$?
	if [ $exit_status -eq 0 ]; then
		return 0
	else
		return $val
	fi
}

function operate(){

        env=$1
        job=$2
		#set=${3:-default}
        flag="default"
        if [ "$job" == "restart-store" ] || [ "$job" == "stop-store" ] || [ "$job" == "start-store" ] || [ "$job" == "kill-store" ] || [ "$job" == "killstart-store" ]; then
                flag="storeonly"
        elif [ "$job" == "restart-aux" ] || [ "$job" == "stop-aux" ] || [ "$job" == "start-aux" ] || [ "$job" == "kill-aux" ] || [ "$job" == "killstart-aux" ]; then
                flag="auxonly"
        elif [ "$job" == "restart-admin" ] || [ "$job" == "stop-admin" ] || [ "$job" == "start-admin" ] || [ "$job" == "kill-admin" ] || [ "$job" == "killstart-admin" ]; then
                flag="adminonly"
        else
                flag="default"
        fi

        if [ "$env" == "Prod" ]; then
                ##If only Prod Storefront alone requested
                if [ "$flag" == "storeonly" ]; then
                        SERVER_LIST=`awk '/<instance name=(.*).>/{print $0}' $BIN_PATH/environment-config.xml  | awk -F\" '{print$2}' | grep "^prod" | sort`
                        job=`echo ${job} | awk -F- '{print $1}'`
                elif [ "$flag" == "auxonly" ]; then
                        SERVER_LIST=`awk '/<instance name=(.*).>/{print $0}' $BIN_PATH/environment-config.xml  | awk -F\" '{print$2}' | grep "^aux" | sort -r`
                        job=`echo ${job} | awk -F- '{print $1}'`
                elif [ "$flag" == "adminonly" ]; then
                        SERVER_LIST=`awk '/<instance name=(.*).>/{print $0}' $BIN_PATH/environment-config.xml  | awk -F\" '{print$2}' | grep "admin" | sort`
                        job=`echo ${job} | awk -F- '{print $1}'`
                else
                        SERVER_LIST=`awk '/<instance name=(.*).>/{print $0}' $BIN_PATH/environment-config.xml  | awk -F\" '{print$2}' | sort`
                fi
                OFS=$IFS
                IFS=$'\n'
                for server in $SERVER_LIST ; do
                        export BOUNCE_STEP="$server:$job:$DOMAIN_HOME/servers/$server/logs/$server.log:stop:300"
                        instance=`echo $BOUNCE_STEP | cut -d: -f1`
                        operation=`echo $BOUNCE_STEP | cut -d: -f2`
                        logfile=`echo $BOUNCE_STEP | cut -d: -f3`
                        continue_execution=`echo $BOUNCE_STEP | cut -d: -f4`
                        timeout_server_operation=`echo $BOUNCE_STEP | cut -d: -f5`
                        ## Monitor the Restart Progress for Success
                        start_time=$(date +"%s")
                        log_date=`date +%Y-%m-%d-%H:%M`
                        log_it "${log_date}    : INFO: "$job"ing Instance $instance ..."
                        log_it "################################################################ \n"
						start_time=$(date +"%Y%m%d-%H%M%S")
						if [ "$instance" == "admin1a" ]; then
							if [ "$job" != "start" ]; then
									go_ahead=$( check_baseline $env )
									if [ $go_ahead -eq 0 ]; then
										$BIN_PATH/atgd.sh $operation $instance >> $LOGFILE 2>&1 &
									fi
							else
									$BIN_PATH/atgd.sh $operation $instance >> $LOGFILE 2>&1 &
							fi
						else  
							$BIN_PATH/atgd.sh $operation $instance >> $LOGFILE 2>&1 &
						fi
						pid=`echo $!`
						Timmer "$pid" "$instance" "$operation"
                        state=`echo $?`
                        check_execution "$server" "$state" "Error performing $operation operation on $server..." "$continue_execution"
						
                        log_it "###################################################################################"
                        
						if [ $state -eq 0 ]; then
                             INST_STATUS=`$BIN_PATH/atgd.sh status $instance | grep "$instance" | grep -v Goal | grep -v Build | grep -v "Downloaded" | awk '{print $4}' | sed '/^$/d'`
                             if [ "$operation" == "restart" ] || [ "$operation" == "start" ] || [ "$operation" == "killstart" ]; then
                                        PATTERN_1="RUNNING"
                                        PATTERN_2="Active"
										EAR_STATUS=`$BIN_PATH/atgd.sh status $instance | grep "$instance" | grep -v Goal | grep -v Build | grep -v "Downloaded" | awk '{print $13}'| sed '/^$/d'`
                             else
                                        PATTERN_1="shutdown"
                                        PATTERN_2="New"
										EAR_STATUS=`$BIN_PATH/atgd.sh status $instance | grep "$instance" | grep -v Goal | grep -v Build | grep -v "Downloaded" | awk '{print $12}'| sed '/^$/d'`
                             fi
                              #log_it "$INST_STATUS $EAR_STATUS"
                                
							 if [[ "$INST_STATUS" =~ "$PATTERN_1" && "$EAR_STATUS" =~ "$PATTERN_2" ]]; then
                                        log_it "$operation completed successfully"
                             else # If instance started well but
                                        log_it "$operation completed but seems instance to be in Different state :[ $EAR_STATUS ], checking Dynamo Admin for instance accessibility"
                                        if [[ "$EAR_STATUS" =~ "Admin" ]]; then
                                                APP_CONN_STATE=$( TEST_APP_CONN $env $instance )
                                                if [ $APP_CONN_STATE -eq 0 ]; then
                                                        APP_CONN_STATE=0
                                                        log_it " RESULT ****** ${GREEN} INSTANCE URL RESPONDING IR-RESPECTIVE OF EAR STATUS ${NC} ******** ${NC} \n"
                                                else
                                                        APP_CONN_STATE=1
                                                        log_it " RESULT ****** ${RED} INSTANCE URL NOT RESPONDING TO REQUESTS, restarting once again ${NC} \n"
														$BIN_PATH/atgd.sh restart $instance >> $LOGFILE 2>&1 &
														pid=`echo $!`
														Timmer "$pid" "$instance" "restart"
														state=`echo $?`
														check_execution "$server" "$state" "Error performing $operation operation on $server..." "$continue_execution"
                                                fi
                                        fi                            
							 fi
                                
							  log_it "INFO: Checking server status messages in logs"
                                
							  dirname=`dirname $logfile`
							  filename=`basename $logfile`
								
							  if [ "$operation" == "restart" ] || [ "$operation" == "start" ] || [ "$operation" == "killstart" ] ; then
									msg="The server started in RUNNING mode."
						 	  else
									msg="JMS shutdown is complete"
							  fi
                                
						      check_server_status_in_logs "$dirname" "$filename" "$msg" $(( $timeout_server_operation ))

							  log_it "########################################################################## \n"
						
								#log_it "JOB NAME IS : $job"			
								if [ "$job" != "stop" ] && [ "$job" != "kill" ] ; then
										#log_it "INSIDE PARSE"
										parse_log "$server"
										log_it "################################################################ \n"
								fi
						else
								log_it "Server operation did not complete successfully"
						fi
				done
			IFS=$OFS 
	## (If not Prod environment)
        
		elif [ "$env" == "Test" ] || [ "$env" == "Sandbox" ] ; then
                if [ "$flag" == "storeonly" ]; then
                        SERVER_LIST=`awk '/<instance name=(.*).>/{print $0}' $BIN_PATH/environment-config.xml  | awk -F\" '{print$2}' | grep "test_store1b" | sort`
                        job=`echo ${job} | awk -F- '{print $1}'`
                elif [ "$flag" == "auxonly" ]; then
                        SERVER_LIST=`awk '/<instance name=(.*).>/{print $0}' $BIN_PATH/environment-config.xml  | awk -F\" '{print$2}' | grep "^aux" | sort -r`
                        job=`echo ${job} | awk -F- '{print $1}'`
                elif [ "$flag" == "adminonly" ]; then
                        SERVER_LIST=`awk '/<instance name=(.*).>/{print $0}' $BIN_PATH/environment-config.xml  | awk -F\" '{print$2}' | grep "admin" | sort`
                        job=`echo ${job} | awk -F- '{print $1}'`
                else
                        SERVER_LIST=`awk '/<instance name=(.*).>/{print $0}' $BIN_PATH/environment-config.xml  | awk -F\" '{print$2}' | sort`
                fi
                OFS=$IFS
                IFS=$'\n'
                for server in $SERVER_LIST ; do
                        export BOUNCE_STEP="$server:$job:$DOMAIN_HOME/servers/$server/logs/$server.log:stop:300"
                        instance=`echo $BOUNCE_STEP | cut -d: -f1`
                        operation=`echo $BOUNCE_STEP | cut -d: -f2`
                        logfile=`echo $BOUNCE_STEP | cut -d: -f3`
                        continue_execution=`echo $BOUNCE_STEP | cut -d: -f4`
                        timeout_server_operation=`echo $BOUNCE_STEP | cut -d: -f5`
                        ## Monitor the Restart Progress for Success
                        start_time=$(date +"%s")
                        log_date=`date +%Y-%m-%d-%H:%M`
                        log_it "${log_date}    : INFO: "$job"ing Instance $instance ..."
                        
						log_it "################################################################ \n"

                        if [ "$instance" == "test_admin1a" ]; then
                                if [ "$job" != "start" ]; then
                                        go_ahead=$( check_baseline $env )
                                        if [ $go_ahead -eq 0 ]; then
                                                $BIN_PATH/atgd.sh $operation $instance >> $LOGFILE 2>&1 &
                                        fi
                                else
                                        $BIN_PATH/atgd.sh $operation $instance >> $LOGFILE 2>&1 &
                                fi
                        else
                                $BIN_PATH/atgd.sh $operation $instance >> $LOGFILE 2>&1 &
                        fi
						pid=`echo $!`
                        Timmer "$pid" "$instance" "$operation"
						state=`echo $?`
                        check_execution "$server" "$state" "Error performing $operation operation on $server..." "$continue_execution"

                        log_it "###################################################################################"

                        if [ $state -eq 0 ]; then
                                INST_STATUS=`$BIN_PATH/atgd.sh status $instance | grep "$instance" | grep -v Goal | grep -v Build | grep -v "Downloaded" | awk '{print $4}' | sed '/^$/d'`
                                #EAR_STATUS=`$BIN_PATH/atgd.sh status $instance | grep "$instance" | grep -v Goal | grep -v Build | grep -v "Downloaded" | awk '{print $13}'| sed '/^$/d'`
                                if [ "$operation" == "restart" ] || [ "$operation" == "start" ] || [ "$operation" == "killstart" ]; then
                                        PATTERN_1="RUNNING"
                                        PATTERN_2="Active"
										EAR_STATUS=`$BIN_PATH/atgd.sh status $instance | grep "$instance" | grep -v Goal | grep -v Build | grep -v "Downloaded" | awk '{print $13}'| sed '/^$/d'`
                                else
                                        PATTERN_1="shutdown"
                                        PATTERN_2="New"
										EAR_STATUS=`$BIN_PATH/atgd.sh status $instance | grep "$instance" | grep -v Goal | grep -v Build | grep -v "Downloaded" | awk '{print $12}'| sed '/^$/d'`
                                fi
                                log_it "$EAR_STATUS $INST_STATUS"
                                if [[ "$INST_STATUS" =~ "$PATTERN_1" && "$EAR_STATUS" =~ "$PATTERN_2" ]]; then
                                        log_it "$operation completed successfully"
                                else # If instance started well but
                                        log_it "$operation completed but seems instance to be in Different state :[ $EAR_STATUS ], checking Dynamo Admin for instance accessibility"
										if [[ "$EAR_STATUS" =~ "Admin" ]]; then
										APP_CONN_STATE=$( TEST_APP_CONN $env $instance )
										if [ $APP_CONN_STATE -eq 0 ]; then
											APP_CONN_STATE=0
											log_it " RESULT ****** ${GREEN} INSATNCE URL RESPONDING IR-RESPECTIVE OF EAR STATUS ${NC} ******** ${NC} \n"
										else
											APP_CONN_STATE=1
											log_it " RESULT ****** ${RED} INSTANCE ADMIN URL NOT RESPONDING TO REQUESTS, PLEASE CHECK HEALTH OF THE INSTANCE $instance ${NC} \n"
											$BIN_PATH/atgd.sh restart $instance >> $LOGFILE 2>&1 &
											pid=`echo $!`
											Timmer "$pid" "$instance" "restart"
											state=`echo $?`
											check_execution "$server" "$state" "Error performing $operation operation on $server..." "$continue_execution"											
										fi
								fi
						fi
						log_it "INFO: Checking server status messages in logs"
						dirname=`dirname $logfile`
						filename=`basename $logfile`
						if [ "$operation" == "restart" ] || [ "$operation" == "start" ] || [ "$operation" == "killstart" ] ; then
								msg="The server started in RUNNING mode."
						else
								msg="JMS shutdown is complete"
						fi
						check_server_status_in_logs "$dirname" "$filename" "$msg" $(( $timeout_server_operation ))

						log_it "########################################################################## \n"
						if [ "$job" != "stop" ] && [ "$job" != "kill" ] ; then
								parse_log "$server"
								log_it "################################################################ \n"
						fi					
					else
							log_it "Server operation did not complete successfully"
					fi
                done
           IFS=$OFS
	else
           log_it "Invalid Env passed to Operate Function"
    fi
}

function get_sid_segment(){

	pre="vmatg"
	mid=`grep 0c0 /etc/passwd | grep Application | awk '{ split($0, a, ":"); print a[1] }' | cut -c 4-7`
	combined="$pre$mid"
	#echo $combined
	#box=`hostname -s`
	#post=${box##`echo $combined`}
	#echo $post
	domain=".oracleoutsourcing.com"
	#formed_box="$pre$mid$post$domain"
	echo "$combined|$domain"
}

function Restart_All(){

		env=${1:-default}
		## Do pre-check if script and path exist
		retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env killstart
		fi
		if [ $retval -eq 0 ] ; then
				operate $env restart
		else
				log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}

function Stop_All(){

## Do pre-check if script and path exist

		env=${1:-default}
		
		## Do pre-check if script and path exist
		retval=$( pre_check $env )
	
		if [ $retval -eq 21 ] ; then
			operate $env kill
		fi				
                
		if [ $retval -eq 0 ] ; then
			operate $env stop
		else
			log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}
function Start_All(){

		env=${1:-default}
                
		## Do pre-check if script and path exist
		retval=$( pre_check $env )
		
		if [ $retval -eq 21 ] ; then
			operate $env killstart
		fi	
                
		if [ $retval -eq 0 ] ; then
			operate $env start
		else
			log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}

function Restart_Store(){

		env=${1:-default}
		## Do pre-check if script and path exist
                
		retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env killstart-store
		fi	
                
		if [ $retval -eq 0 ] ; then
			operate $env restart-store
		else
			log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}

function Restart_Admin(){

		env=${1:-default}
		## Do pre-check if script and path exist
        retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env killstart-admin
		fi
                
		if [ $retval -eq 0 ] ; then
			operate $env restart-admin
		else
			 log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}

function Restart_Aux(){

		env=${1:-default}
		## Do pre-check if script and path exist
                
		retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env killstart-aux
		fi
                
		if [ $retval -eq 0 ] ; then
		    operate $env restart-aux
		else
		   log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}
function Stop_Store(){

		env=${1:-default}
		## Do pre-check if script and path exist
                
		retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env kill-store
		fi
                
		if [ $retval -eq 0 ] ; then
				operate $env stop-store
		else
				log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}

function Start_Store(){

		env=${1:-default}
		## Do pre-check if script and path exist
                
		retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env killstart-store
		fi
                
		if [ $retval -eq 0 ] ; then
			operate $env start-store
		else
			log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}

function Stop_Admin(){

		env=${1:-default}
		## Do pre-check if script and path exist
		retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env kill-admin
		fi
                
		if [ $retval -eq 0 ] ; then
				operate $env stop-admin
        else
                log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
        fi
}

function Start_Admin(){

		env=${1:-default}
		## Do pre-check if script and path exist

		retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env killstart-admin
		fi
                
		if [ $retval -eq 0 ] ; then
		   operate $env start-admin
		else
		   log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}

function Stop_Aux(){

		env=${1:-default}
		## Do pre-check if script and path exist
                
		retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env kill-aux
		fi
                
		if [ $retval -eq 0 ] ; then
			 operate $env stop-aux
		else
			 log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}

function Start_Aux(){

		env=${1:-default}
		## Do pre-check if script and path exist
                
		retval=$( pre_check $env )
		if [ $retval -eq 21 ] ; then
			operate $env killstart-aux
		fi
                
		if [ $retval -eq 0 ] ; then
				operate $env start-aux
		else
				log_it "PRE-CHECK FAILED, PLEASE SEE ABOVE FOR DETAILS"
		fi
}

#check_atg_lock

if [ "$environment" == "Prod" ] ; then
    
    ##Run script only on admin host of pattern ( vmatg****001.oracleoutsourcing.com ) for Prod environment , where **** is decided based on client sid.
    retval="$(get_sid_segment)"
    OFS=$IFS
    IFS="|"
    set -- $retval
    combined=$1
    domain=$2
    machine_to_run="$combined"001"$domain"
    #machine_to_run=`cat $BIN_PATH/environment-config.xml | grep "weblogic-admin-server" | sed 's|<.*\ host="\(.*\)"\ \/>|\1|' | sed 's/^[ \t\r]*//' | sed 's/[ \t\r]*$//' | sed '/^\s*$/d'`
    #echo $machine_to_run
    ##Pattern match the current hostname with the formed one
    ## when atom issues task from UI, we need to execute only in admin host and exit gracefully from all other Servers.
    if  [[ `hostname -f` =~ ^$machine_to_run* ]]; then
                case "$atgd_option" in
                         Restart-All)  Restart_All $environment
                                       ;;
                       Restart-Store)  Restart_Store $environment
                                       ;;
                       Restart-Admin)  Restart_Admin $environment
                                       ;;
                         Restart-Aux)  Restart_Aux $environment
                                       ;;
                            Stop-All)  Stop_All $environment
                                       ;;
                           Start-All)  Start_All $environment
                                       ;;
                          Stop-Store)  Stop_Store $environment
                                       ;;
                         Start-Store)  Start_Store $environment
                                       ;;
                          Stop-Admin)  Stop_Admin $environment
                                       ;;
                         Start-Admin)  Start_Admin $environment
                                       ;;
                            Stop-Aux)  Stop_Aux $environment
                                       ;;
                           Start-Aux)  Start_Aux $environment
                                       ;;
                                   *)  log_it "Invalid option for this prod environment"
                                       ;;
                esac
    IFS=$OFS
    else
               echo -e "Production Environment `hostname -f` is not an Admin Host to run the script"
    fi
elif [ "$environment" == "Test" ] || [ "$environment" == "Sandbox" ]; then

    ##Run script only on admin host of pattern ( vmatg****009.oracleoutsourcing.com or vmatg****011.oracleoutsourcing.com or vmatg****013.oracleoutsourcing.com ) for Test environment , where **** is decided based on client sid.
    machine_to_run=`cat $BIN_PATH/environment-config.xml | grep "weblogic-admin-server" | sed 's|<.*\ host="\(.*\)"\ \/>|\1|' | sed 's/^[ \t\r]*//' | sed 's/[ \t\r]*$//' | sed '/^\s*$/d'`
    #retval="$(get_sid_segment)"
    #OFS=$IFS
    #IFS="|"
    #set -- $retval
    #combined=$1
    #domain=".oracleoutsourcing.com"
    #machine_to_run="$machine_to_run"
    #echo $machine_to_run
    ##Pattern match the current hostname with the formed one
    ## when atom issues task from UI, we need to execute only in admin host and exit gracefully from all other Servers.
        if  [[ `hostname -f` =~ ^$machine_to_run*  ]]; then
                case "$atgd_option" in
                        Restart-All) Restart_All $environment
                                     ;;
                           Stop-All) Stop_All $environment
                                     ;;
                          Start-All) Start_All  $environment
                                     ;;
                        Start-Store) Start_Store $environment
                                     ;;
                         Stop-Store) Stop_Store $environment
                                     ;;
                         Stop-Admin) Stop_Admin $environment
                                     ;;
                        Start-Admin) Start_Admin $environment
                                     ;;
                      Restart-Store) Restart_Store $environment
                                     ;;
                      Restart-Admin) Restart_Admin $environment
                                     ;;
                                  *) log_it "Invalid option for this Non prod environment"
                                     ;;
                esac
        else
                log_it "SKIPPING .. SINCE IT IS NOT ADMIN HOST"
        fi
else
                log_it "NOT AN VALID ENVIRONMENT : $environment"
fi

## Echo'ing Content of the file
if [ -f $ATOM_PATH/run.log ] ; then
        cat $ATOM_PATH/run.log
        rm -f $ATOM_PATH/run.log
fi
