#!/bin/bash

# file: runtest.sh,  v1.15
# date: 2015-02-10
# by:   Ildar Khisambeev, ildar@cs.niisi.ras.ru
# aim:  to launch the given test in 2 models and compare results;
#		try to allow flexible and universal input
#
# version history:
#	1.00	2013-11-13	release;
#	1.01	2013-11-15	add exit code (0/1/2) and some verbosity;
#	1.02	2013-11-15	prepare files for RTL here;
#	1.03	2013-11-22	minor corrections;
#	1.04	2013-12-20	* output format fixed;
#						* flag for using *.asc instead of *.bin input files for RTL;
#						* check vmips for good ending (v0==0x1234) in vmips-only mode;
#	1.05	2014-02-18	change 'which' for 'type' builtin;
#	1.06	2014-03-12	trap INT and USR2 signals to interrupt RTL simulation;
#	1.07	2014-03-13	add timelimit option (-t);
#	1.08	2014-04-29	create RTL logs inplace using '-p' feature of ncv.sh;
#	1.09	2014-05-15	change -o argument expected format;
#	1.10	2014-05-21	add option for 8G RAM images via hi.bin & lo.bin;
#	1.11	2014-06-20	recompile project anew for each test that has it's own special_options.cfg;
#	1.12	2014-08-22	trap USR1 to stop ncsim correctly;
#	1.13	2014-09-04	correct case of RTL-only mode with log2_common.txt;
#	1.14	2014-12-18	remove 'self-delete' option; sleep only in sge mode;
#	1.15	2014-12-18	remove sleep; add resultflag file

# Exit codes:
#	0: no mismatch; or v0 = 0x1234 in vmips-only mode; or '-h' run;
#	1: there is mismatch; or v0 != 0x1234 in vmips-only mode;
#	2: bad run: wrong options, missing files, etc.
# Signal handlers:
#	INT, USR2: stop ncverilog, continue normally;
#
# TODO:
#	- check test input files before action
#	- supply default vmips_initstate in case of $path1 != '' && ! -f $testdir/vmips_initstate ???
#	- more strict check if $1 is a valid test dir
#
echo "$(date +'%F %T') Starting ${0##*/} at host $(hostname -s)"
############################   PREPARE ENVIRONMENT   ###########################
. /etc/profile.d/modules.sh
module load INCISIV cenv
PATH=$PATH:$HOME/bin

##################################   USAGE   ###################################
usage() {
	echo "Usage: ${0##*/} [-s SIZE] [-o VMIPS_OPTIONS] [-1 VMIPS_PATH] [-2 PRJ_PATH] [-t TIMELIMIT] [-p] [-V] [-R] [-x] [-d] [-h] [PATH_TO_TEST]"
	echo "  -s SIZE          - stop simulation after SIZE instructions"
	echo "  -o VMIPS_OPTIONS - pass VMIPS_OPTIONS string to vmips (e.g. -o configfile=../vmips_options)"
	echo "  -1 VMIPS_PATH    - run certain VMIPS_PATH/vmips ($(type -p vmips) by default)"
	echo "  -2 PRJ_PATH      - path to compiled and ready project (current dir by default)"
	echo "  -t TIMELIMIT     - limit CPU time for RTL simulation to TIMELIMIT seconds (36000 by default)"
	echo "  -p               - piped mode: vmips and RTL run in parallel with comparison"
	echo "  -V               - vmips-only mode: get log1a.txt and exit"
	echo "  -R               - RTL-only mode: use current log1a.txt instead of vmips run"
	echo "  -x               - use *.asc files as input files for RTL (*.bin as default)"
	echo "  -h               - help mode: print this message and exit"
	echo "  PATH_TO_TEST     - change workdir to PATH_TO_TEST ( -1 and -2 paths are relative to this!)"
}
#################################   OPTIONS   ##################################
size=
vargs=
path1=
path2="."
piped=
vmipsonly=
rtlonly=
asc=
#del=
timelimit='36000'						# 10 hours by default
while getopts :s:o:1:2:t:pVRxdh option
do
	case $option in
	s) size=$OPTARG;;
	o) vargs+=" -o $OPTARG";;
	1) path1=$OPTARG;;
	2) path2=$OPTARG;;
	t) timelimit=$OPTARG;;
	p) piped='&';;
	V) vmipsonly=true;;
	R) rtlonly=true;;
	x) asc=true;;
	h) usage
		exit 0 ;;
	\?)	echo >&2 "Wrong argument $OPTARG. Exit."
		usage
		exit 2 ;;
	esac
done

[ "$vmipsonly" ] && piped=''				# no reason to use pipe in vmips-only mode
if [ "$vmipsonly" -a "$rtlonly" ]; then
	echo >&2 "User, you demand both vmips-only and RTL-only modes. Please, try again. Exit."
	exit 2
fi

[ "$timelimit" -gt 0 ] >/dev/null 2>&1 || {
	echo >&2 "Wrong timelimit: $timelimit. Exit"
	usage
	exit 2
}

shift $((OPTIND-1))

workdir=$PWD
[ $1 ] && { cd $1 || exit 2; }	# TODO more strict check if this is a valid test dir
testdir=$PWD
testname=${PWD##*/}

if [ "$rtlonly" ]; then
	:
#	if [ ! -f log1a.txt ]; then
#		echo >&2 "User, you don't have log1a.txt in RTL-only mode. Try again. Exit."
#		exit 2
#	fi
else
	[ "$path1" ] && path1+=/
	${path1}vmips --version >/dev/null 2>&1 || {
		echo >&2 "Can't find ${path1}vmips. Exit."
		exit 2
	}
fi
if [ ! "$vmipsonly" ]; then
	type reg_v2h.pl >/dev/null 2>&1 || {
		echo >&2 "${0##*/}: Can't find tool reg_v2h.pl. Exit."
		exit 2
	}
	type cch_v2h.pl >/dev/null 2>&1 || {
		echo >&2 "${0##*/}: Can't find tool cch_v2h.pl. Exit."
		exit 2
	}
	[ "$path2" ] && path2+=/
	[ -d "$path2" -a \( -d "${path2}INCA_libs" -o -d "${path2}worklib" \) ] || {
		echo >&2 "Project path $path2 is not ready. Exit."
		exit 2
	}
fi

###################################   MAIN   ###################################
echo "$(date +'%F %T') Running test $testname"
echo "Start time $(date +'%F %T')" > report.txt
echo "Test $testname" >> report.txt
[ $piped ] && echo "Piped mode."

#################################   RUN VMIPS   ################################
if [ ! "$rtlonly" ]; then
ram=''
[ -f rom.bin ] || {
	echo "Can't find rom.bin." >> report.txt
	echo >&2 "Can't find rom.bin."
	exit 2
}
if [ -f ram.bin ]; then
	ram="-o ramfile=ram.bin -o ramfileaddr=0x40000000"
elif [ -f lo.bin -a -f hi.bin ]; then
	ram="-o ram=\"lo.bin 0x0 hi.bin 0x140000000\""		# 2 rank memory: test 2*256M chunks
else
	echo "Can't find any RAM file (ram.bin or lo.bin)" >> report.txt
	echo >&2 "Can't find any RAM file (ram.bin or lo.bin)"
	exit 2
fi
[ -f vmips_initstate ] && vargs+=" -o initstatefile=vmips_initstate"
[ -f dump_cache ] && vargs+=" -o cachefile=dump_cache"
[ -f dump_sysctrl ] && vargs+=" -o sysctrl_initstate=dump_sysctrl"
[ $size ] && vargs+=" -o haltoninstcount -o haltinstcount=$size"
[ -f vmips_options ] && vargs+=" -o configfile=vmips_options"
	rm log1a.txt 2>/dev/null
	[ $piped ] && mkfifo log1a.txt
	echo "$(date +'%F %T') Running vmips model..."
	eval "${path1}vmips \
		$ram \
		-o dumpaddrtrans \
	    -o dumpdcache -o dumpscache \
	    -o excmsg_all  \
	    -o dumpdmemacc=1 \
	    -o instdumpnum \
	    -o dumpregwrite \
		-o dumptlbwrite \
		-o haltdumpcpu \
		-o haltdumpcp0 \
		-o instcounts \
		$vargs \
	    rom.bin 2>log1a.txt $piped"
	[ $piped ] && vm_pid=$!
	if [ "$vmipsonly" ]; then
		read _ _ _ v0 _ <<< $(tac log1a.txt | egrep -m 1 '  00  r0=\w{16}  r1=\w{16}  v0=\w{16}  v1=\w{16}')
		sbioport=$(tac log1a.txt | egrep -m 1 -A 2 HALT | grep 'Code of successful end of modeling was written to kmd64 io port')
		test "$v0" == "v0=0000000000001234" || [ "$sbioport" ]
		result=$?
		[ "$sbioport" ] \
		&& echo "$sbioport" >> report.txt \
		|| echo "$v0 (vmips result)" >> report.txt
		tac log1a.txt | egrep -m 2 'instructions\ executed\ in|instructions\ per\ second' >> report.txt
		echo "$(date +'%F %T') You have your log1a.txt. $v0. Exit $result."
#		[ "$JOB_ID" ] && sleep 60		# in case of network filesystem lags
		echo $result > resultflag
		exit $result
	fi
fi
###############################   RUN NCVERILOG   ##############################
rm log2*.txt 2>/dev/null
ram=''
if [ -f ram.bin ]; then
	ram="0 ram.bin"
elif [ -f lo.bin -a -f hi.bin ]; then
	ram="0 lo.bin\n10000000 hi.bin"		# 2 rank memory
else
	echo "Can't find any RAM file for RTL (ram.bin or lo.bin)" >> report.txt
	echo >&2 "Can't find any RAM file for RTL (ram.bin or lo.bin)"
	exit 2
fi
[ -f ram_table.ini ] ||
echo -e "$ram" > ram_table.ini || {
	echo "Can't create ram_table.ini" >> report.txt
	echo >&2 "Can't create ram_table.ini"
	exit 2
}
if [ "$asc" ]; then
	rm r{a,o}m.asc 2>/dev/null
	xxd -p -c 8 rom.bin > rom.asc
	xxd -p -c 8 ram.bin > ram.asc
	[ -f ram.asc -a -f rom.asc ] || {
		echo >&2 "Can't find/make rom.asc, ram.asc"
		echo "Can't find/make rom.asc, ram.asc" >> report.txt
		exit 2
	}
fi
reuse='-R'
[ -f special_options.cfg ] && {
	reuse=
	[ "$asc" ] || reuse+=" -b"
}
[ -f vmips_initstate ] && reg_v2h.pl vmips_initstate
[ -f dump_cache ] && cch_v2h.pl --file=dump_cache || cch_v2h.pl -0 # for old prj compatibility
[ $piped ] && mkfifo log2_common.txt
echo "$(date +'%F %T') Running RTL-model..."
ulimit -St $timelimit
setsid $path2/scripts/ncv.sh -p $path2 $reuse >/dev/null 2>&1 &
ncv_pid=$!
ulimit -St unlimited

trap "kill -s TERM -- -$ncv_pid; echo '                    RTL simulation interrupted.'" INT USR2
trap "kill -s STOP -- -$ncv_pid; echo '                    RTL simulation stopped...'" USR1
[ $piped ] || wait $ncv_pid

echo "rtl exit code is $?"

##############################   COMPARE RESULTS   #############################

if [ "$rtlonly" -a ! -f log1a.txt ]; then	# check v0
	[ -f log2_common.txt ] && log2="log2_common.txt" || log2="log2_uns.txt"
	v0=$(tac $log2 | egrep -m 1 'r2 \(v0\)=\w{16}')
	v0=${v0#*(v0)=}
	test "$v0" == "0000000000001234"
	result=$?
	echo "v0=$v0 (RTL result)" >> report.txt
else	# compare with log1a.txt
	[ $piped ] && common="-m common" || common=''
	[ log2_common.txt -nt report.txt ] && common="-m common"
	echo -e "$(date +'%F %T') Comparing models... \c"
	compare.pl $common >> report.txt
	result=$?
	if [ "$piped" -a $result -ne 0 ]; then
		kill $vm_pid
		kill -s 15 -- -$ncv_pid
	fi
fi
trap - INT USR1 USR2

echo "Finish time $(date +'%F %T')" >> report.txt
echo "Result:"
echo "----------------------------------------"
cat report.txt
echo "----------------------------------------"

[ $piped ] && rm log1a.txt log2_common.txt k128cp2.log
#[ "$JOB_ID" ] && sleep 60			# in case of network filesystem lags
echo $result > resultflag
exit $result
