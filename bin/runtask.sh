#!/bin/bash

# file: runtask.sh, v1.00
# date: 2014-12-25
author="Ildar Khisambeev <ildar@cs.niisi.ras.ru>"
# aim:  to prepare and run simulation of the set of tests in one of 3 scenarios:
#       1) test list;
#       2) a series of random tests;
#       3) OS launch, sliced in chunks;
#       task parameters are taken from file
#
# version history:
ver="1.00 (2014-12-25)" # release;
#
# TODO:
#   - more strict checktest()
#   - deal with spaces in filenames
#   - single host (non-sge) mode
#   - comments!
#   - manuals!
#   - embed frag cutting
#
echo "$(date +'%F %T') Starting ${0##*/} at host $(hostname -s)"
###############################   SUBROUTINES   ################################
usage() {
    echo -e "\033[1mNAME\033[0m"
    echo -e "       ${0##*/} - prepare and run simulation of the set of tests"
    echo
    echo -e "\033[1mSYNOPSIS\033[0m"
    echo -e "       \033[1m${0##*/}\033[0m [\033[4mOPTION\033[24m]... [\033[4mPATH\033[24m]...        (1st form)"
    echo -e "       \033[1m${0##*/}\033[0m [\033[4mOPTION\033[24m]... \033[4mTEMPLATE\033[24m \033[4mNUMBER\033[24m  (2nd form)"
    echo -e "       \033[1m${0##*/}\033[0m [\033[4mOPTION\033[24m]... \033[4mBIGTASKFILE\033[24m      (3rd form)"
    echo
    echo -e "\033[1mDESCRIPTION\033[0m"
    echo -e "       In the 1st form, run tests found in PATHs (which may contain bash wildcards). If omitted, look for tests in the current directory."
    echo -e "       In the 2nd form, run a series of NUMBER random tests (NUMBER=0 means unlimited series), generated from template file TEMPLATE."
    echo -e "       In the 3rd form, run big code sequence (e.g. linux boot), split into a series of chunks according to the task given in BIGTASKFILE."
    echo
    echo -e "       \033[1m-c\033[0m \033[4mCONFIG_FILE\033[24m   - use configuration from file CONFIG_FILE (rt.conf by default)"
    echo -e "       \033[1m-b\033[0m               - run only bugged tests (1st form only)"
    echo -e "       \033[1m-V\033[0m               - vmips-only mode: make log1a.txt and check it for 'good end'"
    echo -e "       \033[1m-R\033[0m               - RTL-only mode: use existing log1a.txt for comparison OR check RTL logs for 'good end'"
    echo -e "       \033[1m-f\033[0m \033[4mLIST_FILE\033[24m     - take list of test names from LIST_FILE (1st form only)"
    echo -e "       \033[1m-G\033[0m               - tergen-only mode: generate tests and exit  (2nd form with NUMBER>0 only)"
#   echo -e "       \033[1m-m\033[0m               - mass mode: don't check vmips, piped mode preferred"
    echo -e "       \033[1m-h\033[0m               - display this help and exit"
    echo -e "       \033[1m-v\033[0m               - output version information and exit"

}
checktest() {
    [[ -d "$1" && -f "$1/rom.bin" ]] &&
    if [ "$bugsonly" ]; then
        ! grep "No mismatches" $1/report.txt >/dev/null 2>&1
    else
        :
    fi
    return
}
isBugged() {
    if [ "$vmipsonly" ]; then
        ! egrep -q 'successful end of modeling|v0=0000000000001234' $1/report.txt
    elif [ "$rtlonly" ]; then
        ! egrep -q 'v0=0000000000001234' $1/report.txt
    else
        ! egrep -q 'No mis' $1/report.txt
    fi
    return
}
################################   ARGUMENTS   #################################
# set defaults
fileconf="rt.conf"
vmipsonly=
rtlonly=
genonly=
bugsonly=
filelist=()
while getopts :c:f:hbVRG option
do
    case $option in
    c) fileconf=$OPTARG;;
    b) bugsonly=true;;
    V) vmipsonly="-V";;
    R) rtlonly="-R";;
    G) genonly=true;;
    f) filelist+=("$OPTARG");;
    h) usage
        exit 0 ;;
    v) echo "${0##*/} $ver"
       echo "Written by: $author"
        exit 0 ;;
    \:) echo "Option $OPTARG requires an argument, which is not found. Exit."
        usage
        exit 2 ;;
    \?) echo "Wrong option $OPTARG. Exit."
        usage
        exit 2 ;;
    esac
done
shift $((OPTIND-1))

if [ "$vmipsonly" -a "$rtlonly" ]; then
    echo >&2 "User, you demand both vmips-only and RTL-only modes. Please, try again. Exit."
    exit 2
fi

################################   CHECK TOOLS   ###############################
type compare.pl >/dev/null 2>&1 || {
    echo >&2 "${0##*/}: Can't find tool compare.pl. Exit."
    exit 2
}
type reg_v2h.pl >/dev/null 2>&1 || {
    echo >&2 "${0##*/}: Can't find tool reg_v2h.pl."
#   echo >&2 "${0##*/}: Can't find tool reg_v2h.pl. Exit."
#   exit 2
}
type cch_v2h.pl >/dev/null 2>&1 || {
    echo >&2 "${0##*/}: Can't find tool cch_v2h.pl."
#   echo >&2 "${0##*/}: Can't find tool cch_v2h.pl. Exit."
#   exit 2
}
type checkipc.pl >/dev/null 2>&1 || {
    echo >&2 "${0##*/}: Can't find tool checkipc.pl."
#   echo >&2 "${0##*/}: Can't find tool cch_v2h.pl. Exit."
#   exit 2
}
runtest=$(type -p runtest.sh)
if [ ! "$runtest" ]
then
    echo >&2 "${0##*/}: Can't find script runtest.sh. Exit."
    exit 2
fi

##############################   GET TEST LIST   ###############################
cd $(readlink -e .)             # to set PWD to absolute path

testlist=()
for file in ${filelist[@]}
do
#   echo "file is [$file]"
    if [ -f "$file" ]; then
        for line in $(cat $file)
        do
            line=${line%/}                                                      # remove trailing slash if any
            line=$(readlink -e $line)                                           # full path to test
            [[ "$line" =~ ^$PWD ]] || { echo "Test [$line] is not here"; continue; }
            checktest "$line" && testlist+=("$line")
        done
    else
        echo >&2 "${0##*/}: Warning. File $file not found."
    fi
done

[ -z "$*" ] && here='.' || here=
for file in "$@" "$here"
do
    [ -d "$file" ] && for line in $(find $file -type d)
#   [ -d "$file" ] && find $file -type d -print0 | while read -r -d '' line
    do
        line=$(readlink -e "$line")
        [[ "$line" =~ ^$PWD ]] || { echo >&2 "Test [$line] is not here"; continue; }
        checktest "$line" && testlist+=("$line")
    done
done

if [ ${#testlist[@]} -eq 0 ]; then
    usage
    echo >&2 "${0##*/}: Tests not found. Exit."
    exit 2
fi

#for tn in ${testlist[@]}; do
#   echo "testname is [$tn]"
#done

#exit 0

##########################   GET SETTINGS FROM FILE   ##########################
TL_PRJ_PATH='.'
TL_VMI_PATH=
TL_VMI_OPTFILE=
TL_PIPED=
TL_DEL=
TL_ASC=
TL_TIMELIMIT=
TL_THREADS=0
TL_PASSDIR=
    
if [ -f "$fileconf" ]; then
    echo -e "$(date +'%F %T') Configuration file: \033[1m$fileconf\033[0m"
    . $fileconf
else
    usage
    echo >&2 "${0##*/}: Configuration file $fileconf not found. Exit."
    exit 2
fi

###########################   CHECK CONFIGURATION   ############################
echo -e "                    Working directory: \033[1m$PWD\033[0m"
[ "$TL_TASKID" ] || TL_TASKID=tl.$(id -un).$(date +%F).$(hostname -s).$$
echo -e "                    Task ID: \033[1m$TL_TASKID\033[0m"

[ "$TL_DEL" ]       && TL_DEL="-d"
[ "$TL_ASC" ]       && TL_ASC="-x"
[ "$TL_PIPED" ]     && TL_PIPED="-p"
[ "$TL_THREADS" ]   || TL_THREADS=0
[ "$TL_THREADS" -ge 0 ] >/dev/null 2>&1 || {
    echo >&2 "${0##*/}: Wrong threads limit '$TL_THREADS'. Exit"
    exit 2
}
if [ "$TL_TIMELIMIT" ]; then
[ "${TL_TIMELIMIT##-t }" -gt 0 ] >/dev/null 2>&1 || {
    echo >&2 "${0##*/}: Wrong timelimit ${TL_TIMELIMIT##-t }. Exit"
    usage
    exit 2
}
fi
if [ "$TL_PASSDIR" ]; then
    mkdir -p $TL_PASSDIR || echo >&2 "Can't make directory [$TL_PASSDIR]."
    TL_PASSDIR=$(readlink -e "$TL_PASSDIR")
    if [[ -d "$TL_PASSDIR" && "$TL_PASSDIR" =~ ^$PWD ]]; then
        TL_DEL=''
        echo -e "                    Passed tests dir: \033[1m$TL_PASSDIR\033[0m"
    else
        echo >&2 "Passed tests dir [$TL_PASSDIR] is unavailable. Skipping."
        TL_PASSDIR=''
    fi
fi

################################   CHECK VMIPS   ###############################
rev=
if [ ! "$rtlonly" ]; then
    [ "$TL_VMI_PATH" ] && TL_VMI_PATH+=/
    if ${TL_VMI_PATH}vmips --version >/dev/null 2>&1
    then
        rev=$(${TL_VMI_PATH}vmips --version | head -1)
        echo -e "                    Vmips version: \033[1m${rev#Revision: }\033[0m"
    else
        echo >&2 "${0##*/}: Can't run ${TL_VMI_PATH}vmips. Exit."
        exit 2
    fi
#   echo "TL_VMI_OPTFILE is [$TL_VMI_OPTFILE]"
fi
    [ "$TL_VMI_OPTFILE" ] &&
    if [ -f "$TL_VMI_OPTFILE" ]; then
        TL_VMI_OPTFILE="-o configfile=$(readlink -e $TL_VMI_OPTFILE)"
    else
        [ ! "$rtlonly" ] && echo >&2 "${0##*/}: Warning. Vmips options file '$TL_VMI_OPTFILE' not found."
        TL_VMI_OPTFILE=
    fi

#################################   CHECK RTL   ################################
if [ ! "$vmipsonly" ]; then
    if [ $TL_PRJ_PATH ]; then
        TL_PRJ_PATH=$(readlink -e "$TL_PRJ_PATH")
        TL_PRJ_PATH+=/
        if [ ! -d "$TL_PRJ_PATH" -o \( ! -d "$TL_PRJ_PATH/INCA_libs" -a ! -d "$TL_PRJ_PATH/worklib" \) ]; then
            echo >&2 "${0##*/}: Project path $TL_PRJ_PATH is not ready. Exit."
            exit 2
        fi
        if [ ! -x "$TL_PRJ_PATH/scripts/ncv.sh" ]; then
            echo >&2 "${0##*/}: Can't execute script $TL_PRJ_PATH/scripts/ncv.sh. Exit."
            exit 2
        fi
        echo -e "                    Project path: \033[1m${TL_PRJ_PATH%/prj/}\033[0m"
    else
        echo >&2 "${0##*/}: TL_PRJ_PATH is not set. Exit."
        exit 2
    fi
fi
###############################   SUBMIT LOOP   ################################
totalreport=bugs.${TL_TASKID}.txt
echo "$(date +'%F %T') Start submitting." >> $totalreport
totalstat=stat.${TL_TASKID}.txt

for tn in ${testlist[@]}; do
    while [ $TL_THREADS -ne 0 -a $(qstat -r | grep 'Full jobname' | grep $TL_TASKID | wc -l) -ge $TL_THREADS ]
    do
#       echo "Queue is full ($TL_THREADS threads). \
#             Sleeping 5 seconds and trying test $tn again..." >&2
        echo -n "."
        sleep 5
    done

    rm -rf $tn/prev
    mkdir -p $tn/prev
    mv -f $tn/{report.txt,sge.outerr,irun.log,test_cost.txt} $tn/prev 2>/dev/null

    echo -e "\r\033[K$(date +'%F %T') Submitting test [\033[1m${tn#$PWD/}\033[0m]"
    while JobId=$(qsub -@ sge_request -v PATH -N ${TL_TASKID}${tn//\//---} -o ${tn}/sge.outerr \
        $runtest -1 "$TL_VMI_PATH" $TL_PIPED $TL_DEL $TL_ASC $TL_TIMELIMIT -2 "$TL_PRJ_PATH" \
        $vmipsonly $rtlonly $TL_VMI_OPTFILE \
        $tn ); test -z "$JobId"
    do
        echo >&2 "${0##*/}: Submitting ${tn#$PWD/} failed, sleeping and trying again..."
        sleep 10
    done
done
###########################   WAIT AND REPORT LOOP   ###########################
donelist=()
echo -e "\033[1;4mWaiting tests to finish, $((${#testlist[@]} - ${#donelist[@]})) to go...\033[0m"
while [ ${#donelist[@]} -ne ${#testlist[@]} ]; do
    for tn in ${testlist[@]}; do
        if ! [[ "${donelist[@]}" =~ " ${TL_TASKID}${tn//\//---} " ]] &&
        [ -z "$(qstat -r | grep 'Full jobname' | grep ${TL_TASKID}${tn//\//---}'$')" ]
        then
            if [ -f "${tn##*/}.report.txt" ]; then
                cat ${tn##*/}.report.txt | grep -v " time "                     # this means 'to delete' & 'test passed' conditions
                rm ${tn##*/}.report.txt
            else
                cat $tn/report.txt | grep -v " time "
                if isBugged "$tn"; then
                    cat $tn/report.txt >> $totalreport
                    echo >> $totalreport
                    rm $tn/test_cost.txt 2>/dev/null
                    [ "$TL_PIPED" ] && {
                        echo -n "Make vmips logs again..."
                        mv $tn/report.txt{,.orig}
                        $runtest -1 "$TL_VMI_PATH" $TL_VMI_OPTFILE -V $tn >/dev/null
                        mv -f $tn/report.txt{.orig,}
                        echo "done!"
                    }
                    compare.pl -s -1=$tn >/dev/null
                elif [ -z "$vmipsonly" -a -f "$tn/test_cost.txt" ]; then
# -----------------> print header to $totalstat here if it's empty
                    if [ ! -f "$totalstat" ]; then
                        touch "$totalstat" &&
                        perl -nwe 'print unless /^\s*$|^#/; last if /# output/' $tn/test_cost.txt > "$totalstat"
                        echo >> "$totalstat"
                    fi
# -----------------> statistics analysis goes here:
                    checkipc.pl "$tn" >> "$totalstat"
                fi
            fi
            if [ "$TL_PASSDIR" -a -z "$vmipsonly" ] && ! isBugged "$tn"; then           # move to old bugs
                if [ ! -e "${TL_PASSDIR}/${tn##*/}" ]; then
                    mv $tn $TL_PASSDIR
                else                                                            # choose unique proper target name
                    i=1
                    while [ -e "${TL_PASSDIR}/${tn##*/}.$i" ]; do
                        (( i+=1 ))
                    done
                    mv $tn $TL_PASSDIR/${tn##*/}.$i
                fi
            fi
            donelist+=(" ${TL_TASKID}${tn//\//---} ")
            [ ${#donelist[@]} -ne ${#testlist[@]} ] &&
            echo -e "\033[1;4mWaiting tests to finish, $((${#testlist[@]} - ${#donelist[@]})) to go...\033[0m"
        else
#           echo "${TL_TASKID}.${tn//\//---} still running"
            :
        fi
    done
    [ ${#donelist[@]} -ne ${#testlist[@]} ] &&
    sleep 5
done
echo -e "\033[1;4m$(date +'%F %T') All tests finished, see reports above.\033[0m"
echo "$(date +'%F %T') Finished." >> $totalreport
if [ -z "$vmipsonly" -a -f "$totalstat" ]; then
# -----------------> statistics report goes here (to totalreport and totalstat both):
average_ipc_report=$(cat <<'PERLSCRIPT'
my ($i, $c, $oc, $ti, $tc, $otc, $n) = "0" x 7;
while (<>) {
    ($i,$c,$oc) = /Instr: (\d+)\s+Cycles: (\d+)\s+IPC: [\d\.]+(?:.*\((\d+) cycles\))?/;
    next unless $c;
    $n++; $ti+=$i; $tc+=$c; $otc+=($oc ? $oc : $c);
}
if ($tc) {
    my ($ipc, $old);
    $ipc = sprintf "%1.4f", $ti / $tc;
    $old = sprintf "%1.4f", $ti / $otc;
    $old = ("$ipc" eq "$old") ? "" : " (was $old)";
    print "Average IPC over all $n tests: $ipc$old\n";
}
PERLSCRIPT
)
avermsg=$(perl -we "$average_ipc_report" "$totalstat")
echo >> "$totalstat"
echo "$avermsg" >> "$totalstat"
echo "$avermsg" >> "$totalreport"
echo "$avermsg"
fi

exit 0
