#!/bin/bash

# file: rtbatchrun.sh,  v1.10
# date: 2014-12-18
# by:   Ildar Khisambeev, ildar@cs.niisi.ras.ru
# aim:  to run simulation of a series of random tests on the prepared models;
#		task parameters are taken from file
#
# version history:
#	1.00	2013-12-18	release;
#	1.01	2013-12-23	add check of vmips result (in 'not-mass' mode);
#	1.02	2013-12-23	main loop via 'while';
#	1.03	2013-12-23	count tergen and vmips fails; fix & improve output;
#	1.04	2014-03-18	* create own working environment (prj & template copies);
#						* use timelimit for RTL runs;
#						* handle some signals;
#						* remake set of vmips logs for bugged tests;
#	1.05	2014-04-08	fix bug with RT_VMI_PATH;
#	1.06    2014-05-16  change -o argument format;
#	1.07    2014-05-28  many small tweaks and checks for conformance with other scripts;
#	1.08    2014-07-28  location of .stp file can be set; bad bugs add counter;
#	1.09    2014-08-04  introduce multibugs counter: stop series after 5 consecutive bugs;
#	1.10    2014-12-18  explicit dir remove;
#
# TODO:
#	- use {ram,rom}.bin files in first hand;
#	- add vmips-only feature and option?
#	- randomize template and macros every tergen run;
#	- embed frag_cutter;
#	- sge mode? (check if iterations or threads < limit)
#	- comments!
#	- manuals!
#	- randomize cache (via tergen?);
#	- do not count RTL fails as a bug?
#	- append new statistics
#	- check all features from previous scripts (mine and Igor's)
#
echo "$(date +'%F %T') Starting ${0##*/} at host $(hostname -s)"
##################################   USAGE   ###################################
usage() {
	echo "Usage: ${0##*/} [-h] [-c CONFIG_FILE] [-G] [-m] TEMPLATE N"
	echo "  -h               - help mode: print this message and exit"
	echo "  -c CONFIG_FILE   - use configuration from file CONFIG_FILE (rt.conf by default)"
	echo "  -G               - tergen-only mode: generate tests and exit"
	echo "  -m               - mass mode: don't check vmips, piped mode preferred"
	echo "  TEMPLATE         - name of template to run"
	echo "  N                - integer number of iterations to run (greater than 0)"
}
################################   ARGUMENTS   #################################
fileconf="rt.conf"
genonly=''
massmode=''
while getopts :c:hmG option
do
	case $option in
	c) fileconf=$OPTARG;;
	G) genonly=true;;
	m) massmode=true;;
	h) usage
		exit 0 ;;
	\?)	echo "Wrong argument $OPTARG. Exit."
		usage
		exit 2 ;;
	esac
done
shift $((OPTIND-1))
template=$1
n=$2

if [ -z "$template" ]; then
	echo >&2 "Template name not given. Exit"
	usage
	exit 2
fi
[ "$n" -gt 0 ] >/dev/null 2>&1 || {
	echo >&2 "Wrong number of iterations to run: $n. Exit"
	usage
	exit 2
}

##########################   GET SETTINGS FROM FILE   ##########################
RT_PRJ_PATH='.'
RT_TRG_PATH=
RT_TRG_STPFILE=
RT_VMI_PATH=
RT_VMI_OPTFILE=
RT_PIPED=
RT_ASC=
RT_DEL=
RT_TIMELIMIT=
RT_THREADS=0

RT_SIZE=

RT_BUGDIR=bugs
RT_BADBUGDIR=badbugs
RT_TEMPLATEDIR=templates
RT_MACRODIR=macros
RT_ROMDIR=boot
	
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

# TODO: check options for correctness and set defaults
[ "$RT_DEL" ]		&& RT_DEL="-d"
[ "$RT_ASC" ]		&& RT_ASC="-x"
[ "$RT_PIPED" ]		&& RT_PIPED="-p"
[ "$RT_THREADS" ]	|| RT_THREADS=0
[ "$RT_THREADS" -ge 0 ] >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Wrong threads limit '$RT_THREADS'. Exit"
	exit 2
}
if [ "$RT_TIMELIMIT" ]; then		# TODO: check that it begins with '-t '
[ "${RT_TIMELIMIT##-t }" -gt 0 ] >/dev/null 2>&1 || {
	usage
	echo >&2 "${0##*/}: Wrong timelimit ${RT_TIMELIMIT##-t }. Exit"
	exit 2
}
fi

if [ "$RT_SIZE" ]; then		# TODO: check that it begins with '-s '
[ "${RT_SIZE##-s }" -gt 0 ] >/dev/null 2>&1 || {
	usage
	echo >&2 "${0##*/}: Wrong test size limit ${RT_SIZE##-s }. Exit"
	exit 2
}
fi

readlink -e "$RT_TEMPLATEDIR" >/dev/null 2>&1 \
&& RT_TEMPLATEDIR=$(readlink -e "$RT_TEMPLATEDIR") \
|| echo >&2 "${0##*/}: No templates directory '$RT_TEMPLATEDIR'."

readlink -e "$RT_MACRODIR" >/dev/null 2>&1 \
&& RT_MACRODIR=$(readlink -e "$RT_MACRODIR") \
|| echo >&2 "${0##*/}: No templates directory '$RT_MACRODIR'."

readlink -e "$RT_ROMDIR" >/dev/null 2>&1 \
&& RT_ROMDIR=$(readlink -e "$RT_ROMDIR") \
|| echo >&2 "${0##*/}: No templates directory '$RT_ROMDIR'."

mkdir -p "$RT_BUGDIR" || {
	echo >&2 "${0##*/}: No access to bugs directory '$RT_BUGDIR'."
	exit 2
}
RT_BUGDIR=$(readlink -e "$RT_BUGDIR")

mkdir -p "$RT_BADBUGDIR" || {
	echo >&2 "${0##*/}: No access to bad bugs directory '$RT_BADBUGDIR'."
	exit 2
}
RT_BADBUGDIR=$(readlink -e "$RT_BADBUGDIR")

#[ "$RT_TMP" ] || RT_TMP="$HOME/tmp"
#RT_TMP=$RT_TMP/rtbatch.$(hostname -s).$$
#[ -e "$RT_TMP" ] && rm -rf $RT_TMP
#mkdir -p $RT_TMP || {
#	echo >&2 "${0##*/}: No access to directory '$RT_TMP'."
#	exit 2
#}
#echo "${0##*/}: Temporary workspace for the current batch is '$RT_TMP'"
#cd $RT_WORKDIR

{ [ -f "$template" ] && fulltn=$PWD/$template && template=${template%.tsk}; } ||
{ [ -f "${template}.tsk" ] && fulltn=$PWD/${template}.tsk; } ||
{ [ -f "${RT_TEMPLATEDIR}/$template" ] && fulltn=${RT_TEMPLATEDIR}/$template && template=${template%.tsk}; } ||
{ [ -f "${RT_TEMPLATEDIR}/${template}.tsk" ] && fulltn=${RT_TEMPLATEDIR}/${template}.tsk; } ||
{ echo >&2 "${0##*/}: Can't find template $template. Exit."; exit 2; }
#cp $fulltn $RT_TMP
#fulltn=$RT_TMP/${template}.tsk
#cp vmips_options $RT_TMP

[ "$RT_TASKID" ] || RT_TASKID=$template.$(date +%y%m%d)
echo -e "                    Task ID: \033[1m$RT_TASKID\033[0m"

###############################   CHECK TERGEN   ###############################
rev=
[ "$RT_TRG_PATH" ] && RT_TRG_PATH+=/
if [ -x $(type -p ${RT_TRG_PATH}tergen) ]; then
	rev=$(${RT_TRG_PATH}tergen | head -1)
	rev=${rev#NIISI Test Generator Version }
	rev=${rev%% *}
	echo -e "                    Tergen version: \033[1m${rev}\033[0m"
else
	echo >&2 "${0##*/}: can't find or execute ${RT_TRG_PATH}tergen. Exit."
	exit 2
fi
[ "$RT_TRG_STPFILE" ] &&
if [ -f "$RT_TRG_STPFILE" ]; then
	RT_TRG_STPFILE="-S $(readlink -e $RT_TRG_STPFILE)"
else
	echo >&2 "${0##*/}: Warning. Tergen settings file '$RT_TRG_STPFILE' not found."
	RT_TRG_STPFILE=
fi


if [ ! "$genonly" ]; then
################################   CHECK TOOLS   ###############################
type compare.pl >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Can't find tool compare.pl. Exit."
	exit 2
}
type reg_v2h.pl >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Can't find tool reg_v2h.pl."
#	echo >&2 "${0##*/}: Can't find tool reg_v2h.pl. Exit."
#	exit 2
}
type cch_v2h.pl >/dev/null 2>&1 || {
	echo >&2 "${0##*/}: Can't find tool cch_v2h.pl."
#	echo >&2 "${0##*/}: Can't find tool cch_v2h.pl. Exit."
#	exit 2
}
runtest=$(type -p runtest.sh)
if [ ! $runtest ]
then
	echo >&2 "${0##*/}: Can't find script runtest.sh. Exit."
	exit 2
fi
################################   CHECK VMIPS   ###############################
rev=
[ "$RT_VMI_PATH" ] && RT_VMI_PATH+=/
if ${RT_VMI_PATH}vmips --version >/dev/null 2>&1
then
	rev=$(${RT_VMI_PATH}vmips --version | head -1)
	echo -e "                    Vmips version: \033[1m${rev#Revision: }\033[0m"
else
	echo >&2 "${0##*/}: Can't run ${RT_VMI_PATH}vmips. Exit."
	exit 2
fi
[ "$RT_VMI_OPTFILE" ] &&
if [ -f "$RT_VMI_OPTFILE" ]; then
	RT_VMI_OPTFILE="-o configfile=$(readlink -e $RT_VMI_OPTFILE)"
else
	echo >&2 "${0##*/}: Warning. Vmips options file '$RT_VMI_OPTFILE' not found."
	RT_VMI_OPTFILE=
fi
#################################   CHECK RTL   ################################
if [ $RT_PRJ_PATH ]; then
	RT_PRJ_PATH+=/
	if [ ! -d $RT_PRJ_PATH -o ! -d $RT_PRJ_PATH/INCA_libs ]; then
		echo >&2 "${0##*/}: Project path $RT_PRJ_PATH is not ready. Exit."
		exit 2
	fi
#	mkdir -p $RT_TMP/prj
#	linkprj.sh $RT_PRJ_PATH $RT_TMP/prj || exit 2
#	RT_PRJ_PATH=$RT_TMP/prj
else
	echo >&2 "${0##*/}: RT_PRJ_PATH is not set. Exit."
	exit 2
fi
fi	# if [ ! "$genonly" ]

################################   MAIN LOOP   #################################
stop=0
pid=
mis2=
trap "" INT
trap "stop=1; echo '${0##*/}: Script interrupted, last iteration run.'; wait $pid; mis2=$?" QUIT TERM
#cd $RT_TMP
tergbugs=0
vmipsbugs=0
rtlbugs=0
multibugs=0
i=1
#for i in $(seq $n); do
while [ $i -le $n ]; do
	if [ $multibugs -ge 5 ]; then
		echo -e >&2 "$(date +'%F %T') \033[31mWarning! $multibugs fails in a row! Stop immediately.\033[0m"
		break
	fi
	trap "kill -s 12 -- $pid 2>/dev/null; echo '${0##*/}: Script interrupted, exit immediately.'; break 2" USR2
	echo "$(date +'%F %T') Start iteration $i of $n:"
	testname=${RT_TASKID}$(date +%H%M%S).$i
	while [ -d "$testname" ]; do
		testname=$testname.$$
	done
	mkdir $testname
	cd $testname
#################################   GET TEST   #################################
	cp $fulltn .
	for macro in $(perl -e 'push @a, /\b([\w\+\-\.]+\.tsm)\b/g while (<>); print "@a";' $fulltn); do
		cp $RT_MACRODIR/$macro .
	done
	echo -e "                    Running tergen... \c"
	${RT_TRG_PATH}tergen \
		-E terg_errs.lst \
		-A programm.lst \
		-B ram.asc \
		-M . \
		$RT_TRG_STPFILE \
		${fulltn##*/} \
	|| {
		trap "stop=1; echo '${0##*/}: Script interrupted, last iteration run.'" USR2
		echo "generation failed on interation $i."
		cat terg_errs.lst
		cd ..
		(( tergbugs += 1 ))
		(( multibugs += 1 ))
		mv $testname $RT_BADBUGDIR/$testname.tergenfail$tergbugs
		(( i += 1 ))
		[ "$stop" -gt 0 ] && break || continue
	}
	echo "$(cat $RT_ROMDIR/rom_cut.asc ram.asc)" > ram.asc
	yes 'deadbeefdeadbeef' | head -n 500000 >> ram.asc
	xxd -r -p ram.asc > ram.bin
	ln -s $RT_ROMDIR/rom.asc .
	ln -s $RT_ROMDIR/boot.bin rom.bin
	echo "done. Template ${fulltn##*/} has been resolved."
	cd ..
	if [ "$genonly" ]; then (( i += 1 )); [ "$stop" -gt 0 ] && break || continue; fi
#################################   RUN TEST   #################################
	if [ "$massmode" ]; then
		$runtest $RT_PIPED $RT_ASC $RT_TIMELIMIT -1 "$RT_VMI_PATH" -2 "$RT_PRJ_PATH" \
			$RT_VMI_OPTFILE $RT_SIZE \
			$testname &
		pid=$!
		wait $pid
		mismatch=$?
		[ "$mis2" ] && mismatch=$mis2
		pid=
		mis2=
		trap "stop=1; echo '${0##*/}: Script interrupted, last iteration run.'" USR2
	else
		if $runtest $RT_SIZE -1 "$RT_VMI_PATH" $RT_VMI_OPTFILE -V $testname >/dev/null
		then
			$runtest $RT_PIPED $RT_ASC $RT_TIMELIMIT -2 "$RT_PRJ_PATH" -R $testname &
			pid=$!
			wait $pid
			mismatch=$?
			[ "$mis2" ] && mismatch=$mis2
			pid=
			mis2=
			trap "stop=1; echo '${0##*/}: Script interrupted, last iteration run.'" USR2
		else
			trap "stop=1; echo '${0##*/}: Script interrupted, last iteration run.'" USR2
			echo "$(date +'%F %T') Vmips failed on iteration $i."
			(( vmipsbugs += 1 ))
			(( multibugs += 1 ))
			mv $testname $RT_BADBUGDIR/$testname.vmipsfail$vmipsbugs
			(( i += 1 ))
			[ "$stop" -gt 0 ] && break || continue
		fi
	fi
	if [ $mismatch -ne 0 ]; then
		(( rtlbugs += 1 ))
		(( multibugs += 1 ))
		if [ "$stop" -eq 0 ]; then
			mv $testname/report.txt{,.orig}
			$runtest $RT_SIZE -1 "$RT_VMI_PATH" $RT_VMI_OPTFILE -V $testname >/dev/null
			compare.pl -s -1=$testname
			mv -f $testname/report.txt{.orig,}
		fi
		mv $testname $RT_BUGDIR
		testname=$RT_BUGDIR/$testname
	else
		[ "$RT_DEL" ] && sleep 60 && rm -r "$testname" &
		multibugs=0
	fi
	echo -e "\033[1;4m$(date +'%F %T') Finish iteration $i of $n. Bugs: $rtlbugs. Test errors: $(( vmipsbugs + tergbugs )).\033[0m"
	echo
	if [ $mismatch -ne 0 ] || [ ! "$RT_DEL" ]; then	# save orig, logs, etc
#		mv ${RT_PRJ_PATH}/log2*.txt $testname 2>/dev/null
#		mv ${RT_PRJ_PATH}/{irun,ncverilog}.log $testname 2>/dev/null
		rm $testname/rom.{asc,bin}		# links
		cp $RT_ROMDIR/rom.asc $testname
		cp $RT_ROMDIR/boot.bin $testname/rom.bin
		cp $RT_ROMDIR/boot.s $testname
		mkdir $testname/orig
		cp $testname/{boot.s,*.tsb,*.tsm,report.txt} $testname/orig/
		
	else
		:
#		rm ${testname}.report.txt	# test already deleted, do smth with ${testname}.report.txt
	fi
	(( i += 1 ))
	[ "$stop" -gt 0 ] && break
done
trap - INT QUIT TERM USR2
#cd $RT_WORKDIR
exit 0
