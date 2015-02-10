#!/bin/bash

# file: linuxrun.sh,  v1.08
# date: 2014-12-02
# by:   Ildar Khisambeev, ildar@cs.niisi.ras.ru
# aim:  to prepare fragments of long program (e.g. linux boot) and queue them for simulation;
#		task parameters are taken from file
#
# version history:
#	1.00	2013-11-13	release;
#	1.01	2013-11-15	link projects via separate script;
#	1.02	2013-11-15	put preparing input files for RTL on runtest.sh's shoulders;
#	1.03	2013-12-19	set LR_PIPED variable to run in piped mode;
#	1.04	2014-05-21	add 8GB RAM compatibility;
#	1.05	2014-05-22	many small tweaks and checks for conformance with other scripts;
#	1.06	2014-07-15	implement disk;
#	1.07	2014-07-25	fix some small issues with disk;
#	1.08	2014-12-02	explicit dir remove; catch ctrl+c in vmips initial run;
#
# TODO:
#	- add run from beginning (LR_START = 0) feature
#	- add vmips-only feature and option?
#	- single host (non-sge) mode
#	- comments!
#	- manuals!
#	- embed frag cutting

echo "$(date +'%F %T') Starting ${0##*/}"
############################   PREPARE ENVIRONMENT   ###########################
PATH=$PATH:$HOME/bin

##################################   USAGE   ###################################
usage() {
	echo "Usage: ${0##*/} [LR_FILE]"
	echo "  LR_FILE   - take configuration & task from file LR_FILE (lr.conf by default)"
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

################################   CHECK TOOLS   ###############################
type compare.pl >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Can't find tool compare.pl. Exit."
	exit 2
}
type reg_v2h.pl >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Can't find tool reg_v2h.pl. Exit."
	exit 2
}
type cch_v2h.pl >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Can't find tool cch_v2h.pl. Exit."
	exit 2
}
runtest=$(type -p runtest.sh)
if [ ! "$runtest" ]
then
	echo >&2 "${0##*/}: Can't find script runtest.sh. Exit."
	exit 2
fi

#####################   GET TASKS AND SETTINGS FROM FILE   #####################
LR_PRJ_PATH='.'
LR_VMI_PATH=
LR_VMI_OPTFILE=
LR_PIPED=
LR_DEL=
LR_ASC=
LR_TIMELIMIT=
LR_THREADS=0

LR_INI=
LR_SIZE=
LR_START=
LR_COUNT=
LR_DISK=
LR_DISKOPT=

if [ "$#" -gt 0 ]; then
	LR_FILE=$1
	shift
else
#	echo "${0##*/}: Task not given. Running task 'lr.conf'"
	LR_FILE=lr.conf
fi
if [ ! -f "$LR_FILE" ]; then
	usage
	echo >&2 "${0##*/}: Task file $LR_FILE not found. Exit."
	exit 2
fi
echo -e "$(date +'%F %T') Configuration file: \033[1m$LR_FILE\033[0m"
. $LR_FILE

###########################   CHECK CONFIGURATION   ############################
echo -e "                    Working directory: \033[1m$PWD\033[0m"
[ "$LR_TASKID" ] || LR_TASKID=linuxrun.$(date +%F).$(hostname -s).$$
echo -e "                    Task ID: \033[1m$LR_TASKID\033[0m"

[ "$LR_DEL" ]		&& LR_DEL="-d"
[ "$LR_ASC" ]		&& LR_ASC="-x"
[ "$LR_PIPED" ]		&& LR_PIPED="-p"
[ "$LR_THREADS" ]	|| LR_THREADS=0
[ "$LR_THREADS" -ge 0 ] >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Wrong threads limit '$LR_THREADS'. Exit"
	exit 2
}

if [ "$LR_DISK" ]; then
	[ -f "$LR_DISK" ] || {
		echo >&2 "${0##*/}: Can't read disk file '$LR_DISK'. Exit"
		exit 2
	}
	cp "$LR_DISK" "${LR_DISK##*/}.$LR_TASKID"
	LR_DISK="${LR_DISK##*/}.$LR_TASKID"
	LR_DISKOPT=" -o disk -o diskfile=${LR_DISK} "
fi

if [ "$LR_TIMELIMIT" ]; then
[ "${LR_TIMELIMIT##-t }" -gt 0 ] >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Wrong timelimit ${LR_TIMELIMIT##-t }. Exit"
	usage
	exit 2
}
fi

[ "$LR_INI" -a "$LR_SIZE" -gt 0 -a "$LR_START" -gt 0 -a "$LR_COUNT" -gt 0 ] >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Wrong task, INI is [$LR_INI], SIZE=$LR_SIZE, START=$LR_START, COUNT=$LR_COUNT. Exit"
	exit 2
}

################################   CHECK VMIPS   ###############################
rev=
[ "$LR_VMI_PATH" ] && LR_VMI_PATH+=/
if ${LR_VMI_PATH}vmips --version >/dev/null 2>&1
then
	rev=$(${LR_VMI_PATH}vmips --version | head -1)
	echo -e "                    Vmips version: \033[1m${rev#Revision: }\033[0m"
else
	echo >&2 "${0##*/}: Can't run ${LR_VMI_PATH}vmips. Exit."
	exit 2
fi
[ "$LR_VMI_OPTFILE" ] &&
if [ -f "$LR_VMI_OPTFILE" ]; then
	LR_VMI_OPTFILE="-o configfile=$(readlink -e $LR_VMI_OPTFILE)"
else
	echo >&2 "${0##*/}: Warning. Vmips options file '$LR_VMI_OPTFILE' not found."
	LR_VMI_OPTFILE=
fi

#################################   CHECK RTL   ################################
if [ $LR_PRJ_PATH ]; then
	LR_PRJ_PATH+=/
	if [ ! -d $LR_PRJ_PATH -o ! -d $LR_PRJ_PATH/INCA_libs ]; then
		echo >&2 "${0##*/}: Project path $LR_PRJ_PATH is not ready. Exit."
		exit 2
	fi
	echo -e "                    Project path: \033[1m${LR_PRJ_PATH%/prj/}\033[0m"
else
	echo >&2 "${0##*/}: LR_PRJ_PATH is not set. Exit."
	exit 2
fi

############################   INITIAL VMIPS RUN   #############################
trap '' INT
${LR_VMI_PATH}vmips $LR_VMI_OPTFILE \
					-o noinstcounts \
					-o dumpinstnumn=10000000 \
					-o noinstdump \
					-o initstatefile=${LR_VMI_PATH}vmips_initstate \
					-o savestate=$LR_START \
					-o savestateprefix=${LR_TASKID}_ \
					$LR_DISKOPT \
					"$LR_INI" boot.bin &
pid=$!
wait $pid
status=$?
rm -f ${LR_TASKID}_0001{flash,cp2} k128cp2.log
if [ $status -ne 0 ]; then
	echo "${0##*/}: Vmips initial run failed. Exit $status."
	exit $status
fi
trap - INT
###############################   SUBMIT LOOP   ################################
for i in $(seq -f %04g $LR_COUNT); do
	status=
	nexti=$(printf "%04d" $((10#$i+1)))		# explicit decimal number to avoid octal arithmetic
	while [ $(qstat -r | grep 'Full jobname' | grep $LR_TASKID | wc -l) -ge $LR_THREADS ]
    do
#		echo "Queue is full ($LR_THREADS threads). \
#			  Sleeping 10 seconds and trying chunk $nexti again..." >&2
		echo -n "."
		sleep 10
    done
	echo -ne "\r\033[K"
	if [ $i -lt $LR_COUNT -o "$LR_DISK" ]; then # do next vmips dump except the last iteration
		echo -e "$(date +'%F %T') Get slice \033[1m$nexti\033[0m from slice $i..."
		[ "$LR_DISK" ] && cp "$LR_DISK" "${LR_TASKID}_${i}disk"
		${LR_VMI_PATH}vmips $LR_VMI_OPTFILE \
							-o initstatefile=${LR_TASKID}_${i}reg \
							-o ramfile=${LR_TASKID}_${i}ram \
							-o ramfileaddr=0x40000000 \
							-o cachefile=${LR_TASKID}_${i}cache \
							-o sysctrl_initstate=${LR_TASKID}_${i}sysctrl \
							-o noinstdump \
							-o instcounts \
							$LR_DISKOPT \
							-o dumpdisk=2 \
							-o instdumpnum \
							-o savestate=$LR_SIZE \
							-o savestateprefix=${LR_TASKID}_${nexti} \
							${LR_TASKID}_${i}rom >/dev/null 2>log1_disk.$i.txt
		status=$?
		rm -f ${LR_TASKID}_${nexti}0001{flash,cp2} k128cp2.log
		[ "$LR_DISK" ] || rm -f log1_disk.$i.txt
		if [ $status -ne 0 ]; then
			echo >&2 "${0##*/}: Vmips failed while run from dump $i. Exit $status."
			exit $status
		fi
		for dump in rom ram reg cache sysctrl; do
			[ $i -eq $LR_COUNT ] \
			&& rm ${LR_TASKID}_${nexti}0001$dump \
			|| mv ${LR_TASKID}_${nexti}0001$dump ${LR_TASKID}_${nexti}$dump
		done
	fi
	# prepare i-th chunk 
	echo -e "$(date +'%F %T') Prepare chunk \033[1m$i\033[0m... "
	mkdir ${LR_TASKID}.$i
	cd ${LR_TASKID}.$i
		if [ $(stat -c '%s' ../${LR_TASKID}_${i}ram) -ge $((1024*1024*1024)) ]; then	# no less than 1GB of RAM
			dd if=../${LR_TASKID}_${i}ram of=lo.bin bs=256M count=1
			dd if=../${LR_TASKID}_${i}ram of=hi.bin bs=256M count=1 skip=16
			rm ../${LR_TASKID}_${i}ram
			[ "$LR_ASC" ] && {
				echo >&2 "${0##*/}: Warning. Refuse to use ASC files for such big RAM."
				LR_ASC=
			}
		else
			mv ../${LR_TASKID}_${i}ram ram.bin
		fi
		mv ../${LR_TASKID}_${i}rom rom.bin
		mv ../${LR_TASKID}_${i}reg vmips_initstate
		mv ../${LR_TASKID}_${i}cache dump_cache
		mv ../${LR_TASKID}_${i}sysctrl dump_sysctrl
		[ "$LR_DISK" ] && {
			mv ../${LR_TASKID}_${i}disk dump_disk
			mv ../log1_disk.$i.txt log1a.txt						# error-prone name choice
			compare.pl -s disk
			rm log1a.txt
			echo -e "disk\ndiskfile=dump_disk" >> vmips_options
		}
		echo -e "haltoninstcount\nhaltinstcount=$LR_SIZE" >> vmips_options
	cd ..
	echo -e "$(date +'%F %T') Send chunk \033[1m$i\033[0m to queue..."
    while JobId=$(qsub -@ sge_request -N ${LR_TASKID}.${i} -o ${LR_TASKID}.$i/sge.outerr \
				$runtest -1 "$LR_VMI_PATH" -2 "$LR_PRJ_PATH" $LR_PIPED $LR_ASC $LR_TIMELIMIT -s $LR_SIZE $LR_VMI_OPTFILE \
				${LR_TASKID}.$i); test -z "$JobId"
    do
	echo >&2 "Submitting chunk $i failed, sleeping and trying again..."
	sleep 10
    done
done
###########################   WAIT AND REPORT LOOP   ###########################
testlist=( $(seq -f %04g $LR_COUNT) )
donelist=()
echo -e "\033[1;4mWaiting chunks to finish, $((${#testlist[@]} - ${#donelist[@]})) to go...\033[0m"
while [ ${#donelist[@]} -ne ${#testlist[@]} ]; do
	for tn in ${testlist[@]}; do
		if ! [[ "${donelist[@]}" =~ " $tn " ]] &&
		[ -z "$(qstat -r | grep 'Full jobname' | grep ${LR_TASKID}.${tn})" ]
		then
			cat ${LR_TASKID}.${tn}/report.txt | grep -v " time "
			if isBugged "${LR_TASKID}.$tn"; then
				[ "$LR_DISK" ] && rm ${LR_TASKID}.${tn}/dump_disk				# space economy
			else
				[ "$LR_DEL" ] && sleep 60 && rm -r "${LR_TASKID}.${tn}" &		# this means 'to delete' & 'test passed' conditions
			fi
			donelist+=(" $tn ")
			[ ${#donelist[@]} -ne ${#testlist[@]} ] &&
			echo -e "\033[1;4mWaiting chunks to finish, $((${#testlist[@]} - ${#donelist[@]})) to go...\033[0m"
		else
			:
		fi
	done
	[ ${#donelist[@]} -ne ${#testlist[@]} ] &&
	sleep 1
done
echo -e "\033[1;4m$(date +'%F %T') All chunks finished, see reports above.\033[0m"

exit 0
