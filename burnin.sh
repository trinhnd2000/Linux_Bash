#!/bin/bash
# 05-04-23: Trinh Nguyen: Create new version 1.1.0 which include:
#                       : - Use function
#                       : - Create file /mnt/pmem/burn_in_progress.log to save burn-in PASSED status, it will detete when done all test
#                       : - DIAG_START.sh will read information from /mnt/pmem/burn_in_progress.log to continue test or stop
#                       : - function get_data move to /IRON/util4ka.sh, which use to get data from /mnt/pmem/burn_in_progress.log
#
# 05-12-23: Trinh Nguyen: v1.1.1
#                       : PASSED/FAILED write data to /mnt/pmem/burn_in_progress.log
#                       : Ask CHOOSE_YESNO to continue test with scheduled or create a new schedule  
##############################################################
# INIT ENVIRONMENT
##############################################################

source /IRON/util4ka.sh
init_environment
init_log_test
DATE_ISSUE="05-12-2023"
TEST_VER="v1.1.1"
break_time=60 ### break time 60 minutes to cooling down unit under test
max_hours=168
SOURCE_LOGS=$UUT_SRC_LOGS                ## /corefiles/diags
DESTIN_LOGS=$UUT_CAN_LOGS_BURNIN         ## /IRON/CSS-$SBBSN/$SBBCANSN/burnin

##############################################################
# USER FUNCTIONAL
##############################################################
kill_process(){
declare -a PIDLIST=( $( ps -Af  | grep -i $1 | grep -v grep |awk ' { print $2 }') ) 2> /dev/null
kill -15 ${PIDLIST[@]} 2>/dev/null  >/dev/null
}

#-----------------------------------------------------------------------------
# Kill all burn-in process when suspend test
#-----------------------------------------------------------------------------
stop_burnin(){
kill_process Optane_PMEM_Exerciser.sh
kill_process IOPF
kill_process Start_Disk_Exerciser.sh
kill_process start_SSD_exerciser.sh
kill_process start_random_read_write.sh
kill_process CPU_burnP6.sh
kill_process CPU_memtester.sh
kill_process main.sh
kill_process burnin.sh
rm -fr $SOURCE_LOGS/* 2>/dev/null
rm -f /mnt/pmem/Optane*
dmesg -C
ipmitool sel clear
}

#-----------------------------------------------------------------------------
# This function use for burn-in test only
# Before burnin test
# Move original DIAG_START.sh to DIAG_START.sh.orig
#-----------------------------------------------------------------------------
copy_DIAG_START(){
if [ ! -f /opt/omneon/manuf_tools/mfg-test-scripts/DIAG_START.sh.orig ]; then 
    mv /opt/omneon/manuf_tools/mfg-test-scripts/DIAG_START.sh /opt/omneon/manuf_tools/mfg-test-scripts/DIAG_START.sh.orig
    cp /IRON/DIAG_START.sh /opt/omneon/manuf_tools/mfg-test-scripts/
fi
}

#-----------------------------------------------------------------------------
# This function use for burn-in test only
# Check /opt/omneon/manuf_tools/mfg-test-scripts/DIAG_START.sh.orig existed
# Remove the current scripts DIAG_START.sh and then
# Move back original DIAG_START.sh script. 
# Use for end of test or suspend test
#-----------------------------------------------------------------------------
move_back(){
if [ -f /opt/omneon/manuf_tools/mfg-test-scripts/DIAG_START.sh.orig ]; then 
    rm -f /opt/omneon/manuf_tools/mfg-test-scripts/DIAG_START.sh
    mv /opt/omneon/manuf_tools/mfg-test-scripts/DIAG_START.sh.orig /opt/omneon/manuf_tools/mfg-test-scripts/DIAG_START.sh
fi
return 0
}

#-----------------------------------------------------------------------------
# Bump up Inlet Temperature shutdown temperature for test run only
# For thermal testing   Change inlet temperature thresholds to 70C LNC and 72C UC
#-----------------------------------------------------------------------------
setup_inlet(){
/opt/mg/bin/whatami -k | grep "\-4000A\-" >/dev/null
if [ $? -eq 0 ]; then
    echo "Thermal Inlet threshold before setup."
    ipmitool sensor | grep Inlet
    echo
    ipmitool raw 0x4 0x26 0x26 0x30 0x00 0x00 0x00 0x00 70 72
    if [ $? -eq 0 ]; then
        echo "Setup thermal Inlet threshold success."
        ipmitool sensor | grep Inlet
    else
        echo "Can not setup thermal Inlet threshold."
        exit 1
    fi
fi
## Gets reset on reboot
}

#---------------------------------------------------------
# Input information
#---------------------------------------------------------
input_data(){
x=False
while [[ "$x" != "True" ]]; do
    echo
    echo
    test_times=''
    while [[ ! ${test_times} =~ ^([[:digit:]]{1})$ ]]; do
        read -p "How many times to run burn-in test (range 1-7): " anytime
        case $anytime in
            1|2|3|4|5|6|7) test_times=$anytime ;;
            *) echo -ne "\e[0A\e[K\r"  ;;
        esac
    done

    test_day=()
    i=0
    while [ $i -lt $test_times ]; do
        test_hours=''
        while [[ ! "${test_hours}" =~ ^([[:digit:]]{1,3})$ ]]; do
            read -p "Enter hours test $((i+1)): " test_hours
            if [[ $test_hours =~ ^([[:digit:]]{1,3})$ ]] ; then
                if [[ $test_hours -lt 1 ]] || [[ $test_hours -gt 168 ]]; then
                    test_hours=''
                    echo -ne "\e[0A\e[K\r"
                else
                    test_day+=( $test_hours )
                fi
            else
                echo -ne "\e[0A\e[K\r"
            fi
        done
        i=$((i+1))
    done
    unset i

    sum_args=0
    for i in ${test_day[@]}; do sum_args=$((sum_args + $i)); done  
    if [ $sum_args -gt $max_hours ]; then      ### sum all arguments must has value <=7 (days)
        echo
        echo "*** Total burn-in hours should not larger than 7 days (168 hours) ...! ***"
        sleep 5
        x="False"
    else
        x="True"
    fi
done
unset x

echo "Times for burn-in : ${#test_day[@]}"
echo "Hours test time by order: ${test_day[@]}"
}

#--------------------------------------------------------------------------
# Create file /mnt/pmem/burn_in_progress.log
#--------------------------------------------------------------------------
create_burnin_log(){
touch /mnt/pmem/burn_in_progress.log
input_data                        # input information to burn_in_progress.txt
echo "CSS-4000A-Testday=$test_times" >>/mnt/pmem/burn_in_progress.log
echo "CSS-4000A-Testhour=" >>/mnt/pmem/burn_in_progress.log

for i in ${test_day[@]}; do     # array test_day from input_data
    sed -i "/^CSS-4000A-Testhour/ s/$/$i|/"  /mnt/pmem/burn_in_progress.log
done
echo "CSS-4000A-Result=" >>/mnt/pmem/burn_in_progress.log
}

#--------------------------------------------------------------------------
# Show log get data from /mnt/pmem/burn_in_progress.log
#--------------------------------------------------------------------------
show_log(){
#echo "show_log"
get_data
#last_count=${#arr_last_results[@]}
echo "=========================================="
echo " TESTED $test_x_times times with results: "
for (( i=0; i<$test_x_times; i++)); do
echo " Test $((i+1)):  ${arr_test_hours[$i]}  ${arr_test_results[$i]}"
done
echo "=========================================="
#echo "end show_log"

}

#--------------------------------------------------------------------------
INIT_BEFORE_TEST(){
rm -f /mnt/pmem/Optane*
dmesg -C
ipmitool sel clear
}

#--------------------------------------------------------------------------
MOVE_LOGS(){
local c_logfile
current_date=$(date +%F)
datestamp=$(date +%F__%H%M)
log_directory=$(basename $SOURCE_LOGS/*/)                        ### Just get folder name Chassis....
log_folder_fullname=$(ls -d $SOURCE_LOGS/Chassis* 2>/dev/null)   ### Get the whole directry path /corefiles/diags/Chassis...

if [[ -z $log_folder_fullname ]]; then
    echo " LOG FOLDER IS NOT FOUND. Program exit now....!"
    exit 0
fi

## Backup log to /IRON/bklog
if [ ! -d /IRON/bklog ]; then mkdir /IRON/bklog; fi
if [ ! -d /IRON/bklog/$current_date ]; then mkdir /IRON/bklog/$current_date; fi

/bin/tar -zcvf /IRON/bklog/$current_date/$log_directory.tgz $SOURCE_LOGS/ 2>/dev/null >/dev/null
if [ $? != 0 ]; then 
    echo "Something wrong. Cannot backup log files to /IRON/bklog/$current_date directory"
    exit 1
fi
############################

cat $log_folder_fullname/Diag_Test_Log.out | grep "FAILED"
if [ $? != 0 ]; then
   result_log="PASSED"
else 
   result_log="FAILED"
fi

# echo "result_log: $result_log"
#--------------------------
#### if PASSED write data to /mnt/pmem/burn_in_progress.log
# write data PASSED/FAILED to /mnt/pmem/burn_in_progress.log
get_data
#if [[ "$result_log"=="PASSED" ]]; then
    max_logfile=$test_x_times
    c_logfile=${#arr_test_results[@]}
#    echo  "max_logfile: $max_logfile  -- c_logfile: $c_logfile"
    if [ $c_logfile -lt $max_logfile ]; then 
        sed -i "/^CSS-4000A-Result/ s/$/$result_log|/"  /mnt/pmem/burn_in_progress.log
    fi
#fi
#cat /mnt/pmem/burn_in_progress.log
#pause
# End of write data

#---------------------------
# Check CSJ-4240A is existing on test
# Copy log CSJ-4240A
if [ $(lsscsi | grep SEAGATE -c) -gt 24 ]; then
    jbod_serial_number
    JBOD_LOGS_BURNIN="/IRON/CSJ-$JBODSN"
    if [ ! -d $JBOD_LOGS_BURNIN ]; then mkdir $JBOD_LOGS_BURNIN; fi
    ## If found CSJ-4240A, then copy log to  /IRON/CSJ-$JBODSN
    cp -fr $log_folder_fullname $JBOD_LOGS_BURNIN
    if [ $? -ne 0 ]; then
        echo -e ${RED}
        echo -ne " Something wrong. Cannot copy log to $JBOD_LOGS_BURNIN...!"
        echo -ne ${STD}
    else
        echo
        echo "CSJ-4240A-$JBODSN $result_log."
        echo "Please check log in $JBOD_LOGS_BURNIN/$log_directory/Diag_Test_Log.out for more information."
    fi
fi

# End of copy log CSJ-4240A

#--------------------------
# Copy log CSS-4000A
if [ ! -d  "$DESTIN_LOGS/$current_date" ]; then mkdir $DESTIN_LOGS/$current_date >/dev/null; fi
dest_dir_log=$DESTIN_LOGS/$current_date

## And then move log to /IRON/CSS-4000A-$SBBSN/$SBBCANSN/burnin
mv -f $log_folder_fullname $dest_dir_log         ### just move directory log from DIAG_START, keep test*.log

# Create some files for CSS-4000A
css_sn=$(mgcmtool enclist 2>/dev/null | grep sbb | awk -F":" '{print $3}' | tr -d ' ')
ipmitool sel list -v 2>/dev/null > $dest_dir_log/ipmitool_sel_list_$datestamp.txt
ipmitool sensor 2>/dev/null > $dest_dir_log/ipmitool_sensor_$datestamp.txt
mgcmtool encdisks esn=$css_sn phy=yes 2>/dev/null >  $dest_dir_log/encdisks_$datestamp.txt 
mgcmtool enclist esn=$css_sn 2>/dev/null > $dest_dir_log/enclist_$datestamp.txt 

# End of copy CSS-4000A

#----------------------------
echo
echo "CSS-$SBBSN - $SBBCANSN $result_log."
echo "Please check log in $dest_dir_log/Diag_Test_Log.out for more information."
echo
unset current_date
unset datestamp

if [[ "$result_log" == "PASSED" ]]; then       # if PASSED then show log from /mnt/pmem/burn_in_progress
    get_data
    local result_count=${#arr_test_results[@]}
#    echo ${arr_test_result[@]}
    if [ $result_count -eq $test_x_times ]; then
        move_back
        show_log
        rm -f /mnt/pmem/burn_in_progress.log
    elif [ $result_count -lt $test_x_times ]; then # if not finish test yet, shutdown system.
        move_back
        poweroff
    fi
else
    move_back
    echo "Program exit now ...!"
    echo
fi
exit 0
}


##############################################################
# MAIN
##############################################################

# ----------------------------------------------
# Trap CTRL+C, CTRL+Z and quit singles
# ----------------------------------------------
trap 'echo " BURNIN TEST terminate now...!"; move_back; stop_burnin; exit '  2 3 6  # SIGINT SIGQUIT SIGABRT

if [ ! -f /mnt/pmem/burn_in_progress.log ]; then
    create_burnin_log
else    
    if [ $( cat /mnt/pmem/burn_in_progress.log |wc -c ) -eq 0 ]; then
        echo "***** File /mnt/pmem/burn_in_progress.log is empty...!"
        echo "***** Input data again."
        rm -f /mnt/pmem/burn_in_progress.log
        create_burnin_log
    else
        show_log
        CHOOSE_YESNO "Continue scheduled (type Y) or create new schedule (type N)(default Y)? " "Y"
        if [ "$returnYESNO" == "NO" ]; then
            rm -f /mnt/pmem/burn_in_progress.log
            create_burnin_log
        fi
    fi
fi

#------------------------------------------------------
# Run DIAG_START.sh
#------------------------------------------------------
#show_log
# get_data        # test_x_times; arr_test_hours; arr_test_results
# echo ${arr_test_hours[@]}
pass_count=${#arr_test_results[@]} 
if [ $pass_count -lt $test_x_times ]; then   # test_x_times from get_data
    setup_inlet
    copy_DIAG_START
    INIT_BEFORE_TEST
    cd /opt/omneon/manuf_tools/mfg-test-scripts/
    echo "test hour: ${arr_test_hours[@]}"
    echo "test result: ${arr_test_results[@]}"
    current_test_hour="${arr_test_hours[$pass_count]}:00:00"
    echo "current_test_hour : $current_test_hour"
#    pause
    ./DIAG_START.sh $current_test_hour IRON
    sleep 30 # to make sure all logs write to folder
    MOVE_LOGS
fi



