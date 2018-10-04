#!/bin/ksh
#================================================================================
#
#  AUPMFileMover.ksh
#
#  Written by: 
#        Date: 
#
#  Inputs: full path filename for INI file
#
#  Description:
#     This script is designed to use configurations from an INI file to
#  deliver files to any of three destination servers.  Load balancing
#  and fail-over are achieved by the use of configurations.  See INI
#  file for more details on configurations.
#     This application runs in an infinite loop and terminates whebn the
#  INI parameter RUN_MODE is not equal to "RUN".  INI paramters can be
#  changed while the script is operating and will take effect on the next
#  iteration of processing (as defined by the SLEEP_TIME paramter in INI).
#     Alarm file are generated at every iteration if problems exist.  Each
#  file is configured to be delivered to three possible servers.  Failure
#  to send to the first server generates a "warning" alarm file.  Failure
#  to send to the second server generates a "severe" file.  Failure to deliver
#  to all three servers generates a "critical" file.  An "info" file will be
#  generated with all the files that were successfully delivered.
#
#================================================================================
if [[ $# -lt 1 ]]; then
   print "You must provide an INI file for this script."
   exit 666
fi

FIRST_CHAR=`print ${1} | cut -b1`

if [ "${FIRST_CHAR}" != "/" ]; then
   print "You must provide a FULL path to the INI file."
   exit 666
fi

INI_FILE=${1}

#echo "Ini File ${INI_FILE}"



#
#
#   ENVIRONMENT
#
#
export ORACLE_HOME=/opt/stage/oracle/product/10.2.0/client_1
export ORACLE_BIN=/opt/stage/oracle/product/10.2.0/client_1/bin
export TNS_ADMIN=/opt/stage/oracle/product/10.2.0/client_1/network/admin
#export ORACLE_SID=AUPMPRD_GATEWAY
export PATH=${PATH}:${ORACLE_BIN}:.


#================================================================================
#
#
#  This process exists in an infinite loop as long as the RUN_MODE
#  variable in the INI file is set to "RUN"
#
#
#================================================================================
while [ 1 ]
do
   RUN_MODE=`grep "^RUN_MODE" ${INI_FILE} | cut -d"=" -f2`
   SLEEP_TIME=`grep "^SLEEP_TIME" ${INI_FILE} | cut -d"=" -f2`

   if [ "${RUN_MODE}" != "RUN" ]; then
      print "Exiting application"
      exit 0
   fi


        PE_INPUT_DIR=`grep "^PE_INPUT_DIR" ${INI_FILE} | cut -d"=" -f2`
        ALARM_DIR=`grep "^ALARM_DIR" ${INI_FILE} | cut -d"=" -f2`


        ARCHIVE_DIR=`grep "^ARCHIVE_DIR" ${INI_FILE} | cut -d"=" -f2`
        LOG_DIR=`grep "^LOG_DIR" ${INI_FILE} | cut -d"=" -f2`
        DUP_FILES_DIR=`grep "^DUP_FILES_DIR" ${INI_FILE} | cut -d"=" -f2`
        INVALID_FILES_DIR=`grep "^INVALID_FILES_DIR" ${INI_FILE} | cut -d"=" -f2`
        DEDUPE_WORK_DIR=`grep "^DEDUPE_WORK_DIR" ${INI_FILE} | cut -d"=" -f2`
        MASTER_LIST_DIR=`grep "^MASTER_LIST_DIR" ${INI_FILE} | cut -d"=" -f2`
        MOVER_INPUT_DIR=`grep "^MOVER_INPUT_DIR" ${INI_FILE} | cut -d"=" -f2`


   #ADDITIONAL_STAGING_PATH=`grep "^ADDITIONAL_STAGING_PATH" ${INI_FILE} | cut -d"=" -f2`  #  RT Moved to AUPMFileSorter
   TIMESTAMP=`date +%Y%m%d%H%M%S`
   LOG_FILE=${LOG_DIR}/AUPMFileMover.${TIMESTAMP}.log
   INFO_FILE=${ALARM_DIR}/AUPMFileMover.${TIMESTAMP}.info
   WARNING_FILE=${ALARM_DIR}/AUPMFileMover.${TIMESTAMP}.warning
   SEVERE_FILE=${ALARM_DIR}/AUPMFileMover.${TIMESTAMP}.severe
   CRITICAL_FILE=${ALARM_DIR}/AUPMFileMover.${TIMESTAMP}.critical


#   echo "PE_INPUT_DIR                  $PE_INPUT_DIR"
#   echo "ALARM_DIR                             $ALARM_DIR"
#   echo "ARCHIVE_DIR                   $ARCHIVE_DIR"
#   echo "DUP_FILES_DIR                         $DUP_FILES_DIR"
#   echo "DEDUPE_WORK_DIR               $DEDUPE_WORK_DIR"
#   echo "MASTER_LIST_DIR           $MASTER_LIST_DIR"
#   echo "MOVER_INPUT_DIR               $MOVER_INPUT_DIR"


   cd ${PE_INPUT_DIR}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

#---------------------------------------------------------------------------------------------------
#
#   New Dedupe logic starts here
#
#---------------------------------------------------------------------------------------------------

        RUN_DTTM=`date`

        # move the done files and associated data files to the dedupe working area

        for DONE_FILE in `ls -d *.done` ;
    do

                # remove the extension
                BASENAME="${DONE_FILE%.done}"

                mv ${PE_INPUT_DIR}/${BASENAME}* ${DEDUPE_WORK_DIR}

    done  #

        # change to the tmp dir to complete processing
        cd ${DEDUPE_WORK_DIR}


        # Unzip any zipped  files
        gunzip *.gz


        for DONE_FILE in `ls -d *.done` ;
        do
#               echo "${DONE_FILE}"

                BASENAME="${DONE_FILE%.done}"
                ALARM_FILE="${ALARM_DIR}/${BASENAME}.crit"

                FIRST_3="${DONE_FILE:0:3}"

#               echo "FIRST_3 = $FIRST_3"

                #==========================================================================
                #  Determine the file type and check the appropriate master list
                #========================================================================


                if [[ "${FIRST_3}" = "ABC" ]]; then

                        FILE_TYPE="ABC"

                        YYYYMM="${DONE_FILE:16:6}"
                        MASTER_LIST=${MASTER_LIST_DIR}/abc_master_list_${YYYYMM}.dat
                        DATA_FILE="${BASENAME}.dat"

#                       echo "ABC file"

                else

                    FILE_TYPE="WIFI"

                    MASTER_LIST=${MASTER_LIST_DIR}/wifi_master_list.dat
                        DATA_FILE="${BASENAME}"
#                       echo "WIFI file"

                fi


                #---------------------------------------------------------------------------------------------------
                #
                #   Validate the file
                #
                #---------------------------------------------------------------------------------------------------




                # Verify the data file exists

                if [[ -f ${DATA_FILE} ]]; then

                        # Verify the data file is greater than zero length

                        if [[ -s ${DATA_FILE} ]]; then


                            # If its an ABC file verify the ARM exists in the ini

                                if [[ "${FILE_TYPE}" = "ABC" ]]; then

                                    ARM="${DATA_FILE:0:8}"
                                        grep "^${ARM}" ${INI_FILE} > /dev/null

                                        if [[ $? != 0 ]]; then

                                                print "${BASENAME}   No ini entry for ABC = ${ARM}.  Fix ini and reprocess from ${INVALID_FILES_DIR}" >> ${INFO_FILE}
                                                print "${BASENAME}   No ini entry for ABC = ${ARM}.  Fix ini and reprocess from ${INVALID_FILES_DIR}" > ${ALARM_FILE}

                                                FILE_TYPE="INVALID"
                                        fi

                                fi

                        else

                                FILE_TYPE="INVALID"
                                print "${DATA_FILE} zero length data file" >> ${INFO_FILE}
                                print "${DATA_FILE} zero length data file" > ${ALARM_FILE}

                        fi


                else
                        FILE_TYPE="INVALID"
                        print "${DATA_FILE} data file does not exist" >> ${INFO_FILE}
                        print "${DATA_FILE} data file does not exist" > ${ALARM_FILE}

                fi



                #==========================================================================
                #  If the file is invalid, move it to the invalid files directory
                #=======================================================================
                if [[ "${FILE_TYPE}" = "INVALID" ]]; then

                        mv ${DEDUPE_WORK_DIR}/${BASENAME}* ${INVALID_FILES_DIR}/

                else

                        touch ${MASTER_LIST}

                        grep "${BASENAME}" ${MASTER_LIST} > /dev/null
                        if [[ $? = 0 ]]; then


                                #==========================================================================
                                #  The file has already been processed, send it to the duplicate dir
                                #==========================================================================

                    print "${BASENAME}  has already been processed" >> ${INFO_FILE}
                                mv ${DEDUPE_WORK_DIR}/${BASENAME}* ${DUP_FILES_DIR}/

                        else

                    print "${DATA_FILE} is valid" >> ${INFO_FILE}

                                #==========================================================================
                                #  Create the SUNTEC done file
                                #==========================================================================
                                SUNTEC_DONE_FILE="${DATA_FILE}.done"
                                touch ${DEDUPE_WORK_DIR}/${SUNTEC_DONE_FILE}


                                #==========================================================================
                                #  Move the files into the mover input directory
                                #==========================================================================

                                cp ${DEDUPE_WORK_DIR}/${DATA_FILE} ${MOVER_INPUT_DIR}/${DATA_FILE}
                                cp ${DEDUPE_WORK_DIR}/${SUNTEC_DONE_FILE} ${MOVER_INPUT_DIR}/${SUNTEC_DONE_FILE}


                                #==========================================================================
                                #  Copy the file to the Archive Directory and add the name to the master list
                                #==========================================================================

                                mv ${DEDUPE_WORK_DIR}/${DATA_FILE} ${ARCHIVE_DIR}/${DATA_FILE}

                                echo "${BASENAME} - ${RUN_DTTM}" >> ${MASTER_LIST}

                                rm -f ${DEDUPE_WORK_DIR}/${BASENAME}*

                        fi


                fi
        done



                cd ${MOVER_INPUT_DIR}

                  for DONE_FILE in `ls -d *.done` ;
                  do
                         #==========================================================================
                         #  Identify Filenames
                         #==========================================================================

                         DATA_FILE="${DONE_FILE%.done}"         #<<<<<<<<<<<<<<<<<RT Add

                        FILE_NAME_PART="${DONE_FILE:0:3}"


                        if [ -s ${DATA_FILE} ]; then

                                if [[ "${FILE_NAME_PART}" = "ABC" ]]; then
                                        ARM="${DONE_FILE:0:8}"

                                        grep "^${ARM}" ${INI_FILE} > /dev/null

                                        # Get the ABC destination servers

                                        if [[ $? = 0 ]]; then

                                           DEST_PRIMARY=`grep "^${ARM}" ${INI_FILE} | cut -d"=" -f2 | cut -d"," -f1`
                                           DEST_SECONDARY=`grep "^${ARM}" ${INI_FILE} | cut -d"=" -f2 | cut -d"," -f2`
                                           DEST_TERTIARY=`grep "^${ARM}" ${INI_FILE} | cut -d"=" -f2 | cut -d"," -f3`

                                                FILE_TYPE="ABC"

                                        else

                                                print "*** SHOULD NOT SEE THIS **** ${BASENAME}   No ini entry for ABC = ${ARM}." >> ${INFO_FILE}

                                                mv ${DEDUPE_WORK_DIR}/${BASENAME}* ${INVALID_FILES_DIR}/

                                                FILE_TYPE="INVALID"
                                        fi

                                        #echo "ABC file"
                                else

                                        #echo "WIFI file"

                                                DEST_PRIMARY=`grep "^WIFI" ${INI_FILE} | cut -d"=" -f2 | cut -d"," -f1`
                                                DEST_SECONDARY=`grep "^WIFI" ${INI_FILE} | cut -d"=" -f2 | cut -d"," -f2`
                                                DEST_TERTIARY=`grep "^WIFI" ${INI_FILE} | cut -d"=" -f2 | cut -d"," -f3`

                                                FILE_TYPE="WIFI"

                                fi


                                SEND_FIRST=`grep "^${DEST_PRIMARY}" ${INI_FILE} | cut -d"=" -f2`
                                SEND_NEXT=`grep "^${DEST_SECONDARY}" ${INI_FILE} | cut -d"=" -f2`
                                SEND_LAST=`grep "^${DEST_TERTIARY}" ${INI_FILE} | cut -d"=" -f2`


#                           echo "SEND_FIRST    -->  $SEND_FIRST"



                                #==========================================================================
                                # INDIVIDUAL ALARM_FILE
                                #==========================================================================
                                ALARM_FILE=`echo ${DONE_FILE} | awk -F'.' '{print $1}'`.alarm
                                ALARM_FILE=${ALARM_DIR}/${ALARM_FILE}
                                print " " > ${ALARM_FILE}



                                #==========================================================================
                                #
                                #  Actual SCP
                                #
                                #==========================================================================
                                #scp ${DATA_FILE} ${SUNTEC_DONE_FILE} ${SEND_FIRST} >> ${ALARM_FILE} 2>&1  #<<<<<<<<<<<<<<<<<RT Change


                                FIRST_CHAR="${SEND_FIRST:0:1}"

#                           echo "Primary copy ~~~~~~~~~~~~~~~~~~~~~~~~~"

                                if [[ "${FIRST_CHAR}" != "/" ]]; then

                                        echo "SCPing the file"

                                        scp ${DATA_FILE} ${DONE_FILE} ${SEND_FIRST} >> ${ALARM_FILE} 2>&1

                                else
#                                       echo "Copying  the file"

                                        cp ${DATA_FILE} ${SEND_FIRST}/${DATA_FILE}
                                        cp ${DONE_FILE} ${SEND_FIRST}/${DONE_FILE}

                                fi



                                if [[ $? != 0 ]]; then
                                   print "Failure on: scp ${DATA_FILE} ${DONE_FILE} ${SEND_FIRST}" >> ${ALARM_FILE}
                                   #------------------------------
                                   # FIRST send failed, try NEXT
                                   #------------------------------
                                   #scp ${DATA_FILE} ${SUNTEC_DONE_FILE} ${SEND_NEXT} >> ${ALARM_FILE} 2>&1  #<<<<<<<<<<<<<<<<<RT Change

#                                  echo "Secondary copy ~~~~~~~~~~~~~~~~~~~~~~~~~"

                                        FIRST_CHAR="${SEND_NEXT:0:1}"

                                        if [[ "${FIRST_CHAR}" != "/" ]]; then

                                                echo "SCPing the file"

                                                scp ${DATA_FILE} ${DONE_FILE} ${SEND_NEXT} >> ${ALARM_FILE} 2>&1

                                        else
#                                               echo "Copying  the file"

                                                cp ${DATA_FILE} ${SEND_NEXT}/${DATA_FILE}
                                                cp ${DONE_FILE} ${SEND_NEXT}/${DONE_FILE}

                                        fi




                                   if [[ $? != 0 ]]; then
                                          print "Failure on: scp ${DATA_FILE} ${DONE_FILE} ${SEND_NEXT}" >> ${ALARM_FILE}
                                          #------------------------------
                                          # NEXT send failed, try LAST
                                          #------------------------------
                                          #scp ${DATA_FILE} ${SUNTEC_DONE_FILE} ${SEND_LAST} >> ${ALARM_FILE} 2>&1  #<<<<<<<<<<<<<<<<<RT Change

#                                           echo "Tertiary copy ~~~~~~~~~~~~~~~~~~~~~~~~~"

                                                FIRST_CHAR="${SEND_LAST:0:1}"

                                                if [[ "${FIRST_CHAR}" != "/" ]]; then

                                                        echo "SCPing the file"

                                                        scp ${DATA_FILE} ${DONE_FILE} ${SEND_LAST} >> ${ALARM_FILE} 2>&1

                                                else
#                                                       echo "Copying  the file"

                                                        cp ${DATA_FILE} ${SEND_LAST}/${DATA_FILE}
                                                        cp ${DONE_FILE} ${SEND_LAST}/${DONE_FILE}

                                                fi



                                          if [[ $? != 0 ]]; then
                                                 print "Failure on: scp ${DATA_FILE} ${DONE_FILE} ${SEND_NEXT}" >> ${ALARM_FILE}
                                                 #------------------------------
                                                 # LAST send failed, CRITICAL
                                                 #------------------------------
                                                 mv ${ALARM_FILE} ${ALARM_FILE}.crit
                                          else
                                                 #------------------------------
                                                 # LAST send succeeded, SEVERE
                                                 #------------------------------
                                                 mv ${ALARM_FILE} ${ALARM_FILE}.sev
                                                 print "copy ${DATA_FILE} ${DONE_FILE} ${SEND_LAST}" >> ${INFO_FILE}


                                                 #cp ${DATA_FILE} ${SUNTEC_DONE_FILE} ${ADDITIONAL_STAGING_PATH}  #<<<<<<<<<<<<<<<<<RT Change
                                                 #rm -f ${DATA_FILE} ${DONE_FILE} ${SUNTEC_DONE_FILE}             #<<<<<<<<<<<<<<<<<RT Change

                                                 rm -f ${DATA_FILE} ${DONE_FILE}             #<<<<<<<<<<<<<<<<<RT Change


                                          fi

                                   else
                                          #------------------------------
                                          # Next send succeeded, WARN
                                          #------------------------------
                                          mv ${ALARM_FILE} ${ALARM_FILE}.warn
                                          print "copy ${DATA_FILE} ${DONE_FILE} ${SEND_NEXT}" >> ${INFO_FILE}

                                          #cp ${DATA_FILE} ${SUNTEC_DONE_FILE} ${ADDITIONAL_STAGING_PATH} #<<<<<<<<<<<<<<<<<RT Change
                                          rm -f ${DATA_FILE} ${DONE_FILE} ${SUNTEC_DONE_FILE} #<<<<<<<<<<<<<<<<<RT Change

                                          rm -f ${DATA_FILE} ${DONE_FILE}
                                   fi

                                else
                                   #------------------------------
                                   # No issues...clear alarm
                                   #------------------------------


                                   rm -f ${ALARM_FILE}
                                   print "copy ${DATA_FILE} ${DONE_FILE} ${SEND_FIRST}" >> ${INFO_FILE}

                                   #cp ${DATA_FILE} ${SUNTEC_DONE_FILE} ${ADDITIONAL_STAGING_PATH}  #<<<<<<<<<<<<<<<<<RT Change
                                   #rm -f ${DATA_FILE} ${DONE_FILE} ${SUNTEC_DONE_FILE} #<<<<<<<<<<<<<<<<<RT Change

                                   rm -f ${DATA_FILE} ${DONE_FILE}
                                fi


                        fi  # If there is size to the DATA file

                  done   # While there are file to process


           #==========================================================
           #  Consolidate individual alarm files
           #==========================================================


           ls ${ALARM_DIR}/*warn > /dev/null 2>&1
           WARNS_PRESENT=$?
           if [ "${WARNS_PRESENT}" = "0" ]; then
                  cat ${ALARM_DIR}/*warn >> ${WARNING_FILE}
           fi
           rm -f ${ALARM_DIR}/*warn

           ls ${ALARM_DIR}/*sev > /dev/null 2>&1
           SEVS_PRESENT=$?
           if [ "${SEVS_PRESENT}" = "0" ]; then
                  cat ${ALARM_DIR}/*sev >> ${SEVERE_FILE}
           fi
           rm -f ${ALARM_DIR}/*sev

           ls ${ALARM_DIR}/*crit > /dev/null 2>&1
           CRITS_PRESENT=$?

           if [ "${CRITS_PRESENT}" = "0" ]; then

              echo "cat critical file"

                  cat ${ALARM_DIR}/*crit >> ${CRITICAL_FILE}
           fi
           rm -f ${ALARM_DIR}/*crit




           #==========================================================
           #  Sleep before next iteration
           #==========================================================
           sleep ${SLEEP_TIME}


           #==========================================================
           #  Clear old info files
           #==========================================================
           find ${ALARM_DIR} -type f -name '*info' -mtime +30 | xargs rm -f


done
