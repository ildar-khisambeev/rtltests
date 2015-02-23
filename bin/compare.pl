#!/usr/bin/perl -w
use strict;

# file: compare.pl,  v2.10
# date: 2015-02-23
# by:   Ildar Khisambeev, ildar@cs.niisi.ras.ru
# aim:  compare vmips log with the set of RTL logs;

# version history:
#	1.00	2012-10-04	release;
#	1.01	2012-10-08	traces and registers buffers are extended to 32 entries each;
#	1.02	2012-10-18	cp3 comparison added; total number of instructions compared is now printed;
#	1.03	2012-11-19	changed algorithm in traces, registers and mem_wr sections for more strict comparing;
#	2.00	2013-08-29	total revision, support for log2_common.txt;
#	2.01	2013-08-30	add slashes to paths from options --path1, --path2;
#	2.02	2013-09-30	fix bug with not recognizing RTL traces lines with picoseconds field;
#	2.03	2013-10-03	recognize x-values in RTL logs;
#	2.04	2013-12-19	fix bug with case of empty RTL logs (fail while forming report);
#	2.05	2014-01-29	add icache comparison;
#	2.06	2014-07-15	add disk in squeezer mode;
#	2.07	2014-07-25	fix disk files path;
#	2.08	2014-09-17	enlarge buffers, fix diskfiles creation;
#	2.09	2014-11-13	do not compare cache bypass lines;
#	2.10	2015-02-23	update CPV templates, compare CPV logs by default;
#						ATTENTION: CPV template is named 'c3rf', but log files are named 'log*_cp2*';
# TODO: 
#	- check Sayapin's "cache writethrough" mode;
#	- "warm tube sound" mode: report ALL mismatches in order of appearance (--wtf);
#	- embed frag_cutter;
#	- check 4-way icache compatibility;
#	- add other squeezer formats: cp0, dma;
#	- save sorted files by request via some option;

#################################   OPTIONS   ##################################
use Getopt::Long;

my @sq_in = ();						# list of protocols to squeeze
my @noc = ();						# protocols to be skipped
my $path1 = '';						# path to vmips log file (current dir by default)
my $path2 = '';						# path to RTL log files (current dir by default)
my @cut_in = ();					# list of files with fragments to cut
my $help = '';						# help mode
my $mode = 'set';					# log2 mode: can be "set" (set of old log2 files) or "common" (one log for correct piped handling)
my $verbose = '';					# verbose mode

GetOptions	(
	"squeeze:s{,}" => \@sq_in,		# zero or more option values, e.g. "-s inst dcch" or "--squeeze" for extracting all protocols
	"no=s{,}" => \@noc,				# one or more option values, e.g. "--no gprf" for skipping GPR comparison. 
	"path1|1=s" => \$path1,			# can be used like -1=..
	"path2|2=s" => \$path2,			# can be used like -2=$PRJ_DIR
	"cut:s" => \@cut_in,
	"help|?" => \$help,				# prints usage, other options ignored
	"log2|m=s" => \$mode,			# can be used like "-m common"; default is 'set' mode
	"verbose" => \$verbose,			# like "-v"
);

$path1 .= "/" if $path1;			# when paths are given without ending "/"
$path2 .= "/" if $path2;

##################################   USAGE   ###################################
if ( $help )	{
	print "Usage: $0 [-s [LIST]] [-m <MODE>] [-n <LIST>] [-1 <PATH1>] [-2 <PATH2>] [-c [FILELIST]] [-v] [-h]\n";
	print "\t-s, --squeeze [LIST]\t- squeezer mode: squeezing needed logs from the common vmips log\n";
	print "\t\t\t\t  all, inst, gprf, fprf, c2rf, c3rf, dcch, mmwr, exc, addr, disk, icch, cp0;\n";
	print "\t-m, --log2=<MODE>\t- log2 mode can be 'set' (log2*.txt, default) or 'common' (log2_common.txt)\n";
	print "\t-n, --no <LIST>\t\t- not compare logs from the list: ('--no inst' is denied)\n";
	print "\t\t\t\t  gprf, fprf, c2rf, c3rf, dcch, icch, l2ch, mmwr, mmwb;\n";
	print "\t-1, --path1\t\t- path to vmips log location\n";
	print "\t-2, --path2\t\t- path to RTL logs location\n";
	print "\t-c, --cut [FILELIST]\t- cut code fragments described in files from FILELIST (frag_to_cut by default)\n";
	print "\t-v, --verbose\t\t- verbose mode (prints about bad lines in logs, etc.)\n";
	print "\t-h, -?, --help\t\t- print this help and exit\n";
	exit 0;
}
################################   LOG2 MODE   #################################
if ($mode ne 'common' and $mode ne 'set') {
	print "Unknown log2 mode: $mode\nAssuming compatible mode (set of log2*.txt)\n";
	$mode = 'set';																# compatibility
}

@noc = split(/,/,join(',',@noc));												# split multiple comma-separated values
my %noc = ();																	# hash defining protocols for which we skip comparison;
$noc{$_} = 1 foreach (@noc);													# init from option "--no", see above
if ($noc{inst}) {
	print "Refuse to skip traces comparison. Option '--no inst' is denied. Use traces fragments cutting for workaround.\n";
	delete $noc{inst};
}
$noc{xz} = 1;
$noc{icch} = 1;	# remove/comment this line for use with projects with icache log;
$noc{c2rf} = 1;	# remove/comment this line for use with projects with old cp2;
#$noc{c3rf} = 1;	# remove/comment this line for use with projects with cp3;

#############################   LIST TO SQUEEZE   ##############################
$sq_in[0]="all" if (($#sq_in == 0) and ($sq_in[0] eq ""));						# special case of short notation ('compare.pl -s' shall squeeze all)
@sq_in = split(/,/,join(',',@sq_in));											# split multiple comma-separated values
my %sq	= (																		# hash of formats to squeeze
	inst => 0,
	gprf => 0,
	fprf => 0,
	c2rf => 0,
	c3rf => 0,
	dcch => 0,
	mmwr => 0,
	exc => 0,
	addr => 0,
	disk => 0,
	icch => 0,
	cp0 => 0,
);

foreach (@sq_in)	{															# filling list of formats to squeeze
	if ($_ eq "all") {
		for (values %sq)	{ $_++; }
	} elsif ( defined $sq{$_} ) {
		$sq{$_}++;
	} else {
		print "Warning! Unknown squeeze protocol: $_!\n";
	}
}

##########################   CODE FRAGMENTS TO CUT   ###########################

@cut_in = split(/,/,join(',',@cut_in));

##############################   VMIPS FORMATS   ###############################
my %log1;																		# hash of regexps: log1 formats

$log1{bpss} = qr/.*cache.*bypass.*/;
# lines for dcache or scache bypasses
$log1{inst}	= qr/^\s*(\d+)?\s*\bPC=0x([\da-fA-F]{16})\s+\[([\da-fA-F]{16})\]\s+([\da-fA-F]{8})\s+(.*$)/;
#		  $1 - vin, $2 - va, $3 - pa, $4 - opcode, $5 - mnemo
$log1{gprf}	= qr/^\s*(\d+)?\s*\bReg write ([\datvskgpr]{2,3})=([\da-fA-F]{16})/;
#		  $1 - vin, $2 - gpr number, $3 - value
$log1{fprf}	= qr/^\s*(\d+)?\s*\bReg write f\[(\d{1,2})\]=([\da-fA-F]{16})(?:\s+FCSR\(fcr31\)=([\da-fA-F]{8}))?/;
#		  $1 - vin, $2 - fpr number, $3 - fpr value, $4 - fcsr value
$log1{c2rf}	= qr/^\s*(\d+)?\s*\bReg write (?:s\[(\d)\] )?c\[(\d{2})\]=([\da-fA-F]{16})(?:\s+CMCSR\(cmcr31\)=([\da-fA-F]{8}))?/;
#		  $1 - vin, $2 - set, $3 - cp2 reg number, $4 - cp2 reg value, $5 - cmcr value
$log1{c3rf}	= qr/^\s*(\d+)?\s*\bReg write cmgr\[(\d{2})\]=([\da-fA-F]{32})(?:\s+CMCSR\(cmcr31\)=([\da-fA-F]{8}))?/;
#		  $1 - vin, $2 - cp3 reg number, $3 - cp3 reg value, $4 - cmcr value
# old format: $log1{dcch} = qr/^\s*(\d+)?\s*\b([\da-fA-F]{8})\s+VA=([\da-fA-F]+)\s+no_cache=([01])\s+attr=([01]{3})\s+PA=([\da-fA-F]+)\s+hitv=([01]{4})\s+repl=([01]{4})\s+WS=([01]{6})\s+\((\d{4})\)/;
#		  $1 - vin, $2 - opcode, $3 - cline, $4 - no_cache, $5 - policy, $6 - PA, $7 - hitv, $8 - repl, $9 - ws, $10 - ws_dec
$log1{dcch}	= qr/^\s*(\d+)?\s*dcache\s+\b([\da-fA-F]{8})[\s\w\/]*\s+pol=(\d)\s+VA=[\da-fA-F]{16}\s+PA=([\da-fA-F]{9})\s+line=([\da-fA-F]+)\s+hitv=([01]+)\s+ro=(\d+)(.*dma)?/;
#		  $1 - vin, $2 - opcode, $3 - policy, $4 - PA, $5 - line, $6 - hitv, $7 - ro, $8 - dma
$log1{icch}	= qr/^\s*(\d+)?\s*icache\s+\b([\da-fA-F]{8})([\s\w\/]*)\s+pol=\d\s+VA=([\da-fA-F]{16})\s+PA=([\da-fA-F]{9})\s+line=([\da-fA-F]+)\s+hitv=([01]+)\s+ro=(\d+)\s+tag=[\da-fA-F]+\s+V=([01]+)\s+L=([01]+)(.*dma)?/;
#		  vin, opcode, optype, VA, PA, line, hitv, ro, V, L, dma
$log1{l2ch}	= qr/^\s*(\d+)?\s+scache\s+([\da-fA-F]{8})[\s\w\/]*\s+pol=\d\s+VA=[\da-fA-F]{16}\s+PA=[\da-fA-F]{9}\s+line=([\da-fA-F]+)\s+hitv=([01]+)\s+ro=(\d+)\s+tag=[\da-fA-F]+\s+V=[01]+\s+W=([01]+)(.*dma)?/;
# 1/4 ways: $1 - vin, $2 - opcode, $3 - line, $4 - hitv, $5 - ro, $6 - W, $7 - dma
$log1{mmwr} = qr/^\s*(\d+)?\s+dmemacc:\s+store\s+\d{1}\s+addr=([\da-fA-F]{9})\s+data=([\da-fA-F]{16})\s+mask=([\da-fA-F]{8})(?!.*(cline|disk|L2|dma|CP2|pci))/;
#		  $1 - vin, $2 - PA, $3 - data, $4 - be, $5 - WB (if any)
$log1{mmwb} = qr/^\s*(\d+)?\s+dmemacc:\s+store\s+\d{1}\s+addr=([\da-fA-F]{9})\s+data=([\da-fA-F]{16})\s+mask=([\da-fA-F]{8})\s+cline(?!.*(disk|L2|dma|CP2|pci))/;
#		  $1 - vin, $2 - PA, $3 - data, $4 - be, $5 - WB (if any)
$log1{disk} = qr/^\s*(\d+)?\s+dmemacc:\s+store\s+\d{1}\s+addr=([\da-fA-F]{9})\s+data=([\da-fA-F]{16})\s+mask=([\da-fA-F]{8})\s+disk/;
#		  $1 - vin, $2 - PA, $3 - data, $4 - be

###############################   RTL FORMATS   ################################
my %log2;																		# hash of regexps: log2 formats

$log2{inst}	= qr/^(?:inst:)?\s*(\d+)?\s*\b([\da-fA-FxX]{16})\s+([\da-fA-FxX]{8})(?:\s+([\d\. a-z]+))?\s*$/;
#		  $1 - inum, $2 - va, $3 - opcode, $4 - time
$log2{gprf}	= qr/^(?:gprf:)?\s*(\d+)?\s*\br(\d{2})=([\da-fA-FxX]{16})\s*$/;
#		  $1 - inum, $2 - regnum, $3 - data
$log2{fprf}	= qr/^(?:fprf:)?\s*(\d+)?\s*\bfr(\d{2})=([\da-fA-FxX]{16})(?:\s+C1_SR=([\da-fA-FxX]{8}))?\s*$/;
#		  $1 - inum, $2 - regnum, $3 - data, $4 - fcsr value (if any)
$log2{c2rf}	= qr/^(?:c2rf:)?\s*(\d+)?\s*\bs\[(\d)\]\s+c(\d{2})=([\da-fA-FxX]{16})(?:\s+CCSR=([\da-fA-FxX]{8}))?\s*$/;
#		  $1 - inum, $2 - set, $3 - regnum, $4 - data, $5 - ccsr value (if any)
$log2{c3rf}	= qr/^(?:c3rf:)?\s*(\d+)?\s*\bc(\d{2})=([\da-fA-FxX]{32})(?:\s+CMCSR=([\da-fA-FxX]{8}))?\s*$/;
#		  $1 - inum, $2 - regnum, $3 - data, $4 - ccsr value (if any)
$log2{dcch}	= qr/^(?:dcch:)?\s*(\d+)?\s*\b([\da-fA-FxX]{8}|snooping)\s+c_adr=([\da-fA-FxX]{2})\s+no_cache=([01xX])\s+attr=([01xX]{3})\s+PA=([\da-fA-FxX]{9})\s+hitv=([01xX]{4})\s+repl=([01xX]{4})\s+WS=([01xX]{6})\s*$/;
#		  $1 - inum, $2 - opcode, $3 - cline, $4 - nocch, $5 - policy, $6 - PA, $7 - hitv, $8 - repl, $9 - WS
$log2{icch}	= qr/^(?:icch:)?\s*(\d+)?\s+VA=([\da-fA-FxX]{16})\s+IPA=([\da-fA-FxX]{9})\s+c_line=([\da-fA-FxX]{2})\s+hit=([01xX]+)\s+vlw=([01xX]{3})\s+repl=([01xX]+)\s+WS=([01xX]+)\((\d+)\)\s*$/;
#		  inum, VA, PA, cline, hitv, vlw, repl, WS, ro
$log2{l2ch}	= qr/^(?:dcch:)?\s*(\d+)?\s*\b([\da-fA-FxX]{8}|snooping)\s+line=([\da-fA-FxX]{3,4})\s+hitv=([01xX]{1,4})\s+W=([01xX]{1,4})(?:\s+repl=([01xX]{4})\s+WS=([01xX]{6}))?/;
# 1/4 ways: $1 - inum, $2 - opcode, $3 - cline, $4 - hitv, $5 - W, ($6 - repl, $7 - WS)
$log2{mmwr}	= qr/^(?:mmwr:)?\s*(\d+)?\s*\bPA=([\da-fA-FxX]{9})\s+ram_addr=[\da-fA-FxX]+\s+data_in=([\da-fA-FxX]{16})\s+be=([01xX]{8})\s+WB=0(?:\s+dma=([01xX]))?/;
#		  $1 - inum, $2 - PA, $3 - data, $4 - be, $5 - WB, $6 - dma (if any)
$log2{mmwb}	= qr/^(?:mmwr:)?\s*(\d+)?\s*\bPA=([\da-fA-FxX]{9})\s+ram_addr=[\da-fA-FxX]+\s+data_in=([\da-fA-FxX]{16})\s+be=([01xX]{8})\s+WB=1(?:\s+dma=([01xX]))?/;
#		  $1 - inum, $2 - PA, $3 - data, $4 - be, $5 - WB, $6 - dma (if any)

##############################   TABLES & SUBS   ###############################
my %regdef = (	"00" => "r0", "01" => "r1", "02" => "v0", "03" => "v1",			# vmips register names table
				"04" => "a0", "05" => "a1", "06" => "a2", "07" => "a3",
				"08" => "t0", "09" => "t1", "10" => "t2", "11" => "t3",
				"12" => "t4", "13" => "t5", "14" => "t6", "15" => "t7",
				"16" => "s0", "17" => "s1", "18" => "s2", "19" => "s3",
				"20" => "s4", "21" => "s5", "22" => "s6", "23" => "s7",
				"24" => "t8", "25" => "t9", "26" => "k0", "27" => "k1",
				"28" => "gp", "29" => "sp", "30" => "s8", "31" => "ra",
				"--" => "--" );
my %ws_tab = (																	# 4way WS value by the corresponding r(eplace)o(rder)
"0123" => "000000", "1023" => "000100", "2013" => "100010", "3012" => "011001",
"0132" => "000001", "1032" => "000101", "2031" => "110010", "3021" => "011011",
"0213" => "000010", "1203" => "100100", "2103" => "100110", "3102" => "011101",
"0231" => "010010", "1230" => "101100", "2130" => "101110", "3120" => "111101",
"0312" => "010001", "1302" => "001101", "2301" => "111010", "3201" => "111011",
"0321" => "010011", "1320" => "101101", "2310" => "111110", "3210" => "111111"
);
my %algn = (																	# aligning addresses for memory writes comparison
0 => 0, 8 => 8,
1 => 0, 9 => 8,
2 => 0, a => 8,
3 => 0, b => 8,
4 => 0, c => 8,
5 => 0, d => 8,
6 => 0, e => 8,
7 => 0, f => 8,
);

																				# 4 way repl value by the corresponding r(eplace)o(rder)
sub repl {																		# assumed, that correct value is given
	my $ways = length($_[0]);													# $_[0] is the given ro field value
	$_[0]=~/^(.)/;
	return ("0"x($ways-1-$1) ."1". "0"x($1));
};
sub dec2bin	{																	# for converting policy to %03b
	return substr (unpack ("B*", pack("n", shift)), -3);
}
sub bin2dec	{																	# for converting policy from %03b to decimal
	return unpack ("n*", pack ("B*",substr("0" x 16 . shift , -16)));
};
my $fc13 = pack("H8","fc130000");												# constants to compare opcode with index L2 cache instruction:
my $bc03 = pack("H8","bc030000");												# ( opcode & fc130000 ) ^ bc030000 returns zero for index L2 cache

sub gettype {																	# takes log1 line, returns it's type and array of it's elements to compare
	my $l = shift;
	my @l1 = ();
	return ("xz",  \@l1) if (@l1 = ($l=~/$log1{bpss}/));
	return ("inst",\@l1) if (@l1 = ($l=~/$log1{inst}/));
	return ("gprf",\@l1) if (@l1 = ($l=~/$log1{gprf}/));
	return ("dcch",\@l1) if (@l1 = ($l=~/$log1{dcch}/));
	return ("icch",\@l1) if (@l1 = ($l=~/$log1{icch}/));
	return ("l2ch",\@l1) if (@l1 = ($l=~/$log1{l2ch}/));
	return ("mmwr",\@l1) if (@l1 = ($l=~/$log1{mmwr}/));
	return ("mmwb",\@l1) if (@l1 = ($l=~/$log1{mmwb}/));
	return ("disk",\@l1) if (@l1 = ($l=~/$log1{disk}/));
	return ("fprf",\@l1) if (@l1 = ($l=~/$log1{fprf}/));
	return ("c2rf",\@l1) if (@l1 = ($l=~/$log1{c2rf}/));
	return ("c3rf",\@l1) if (@l1 = ($l=~/$log1{c3rf}/));
	return ("xz",\@l1);															# all unrecognized lines, empty array
}

sub gettype2 {																	# takes log2 line, returns it's type and array of it's elements to compare
	my $l = shift;
	my @l2 = ();
	return ("inst",\@l2) if (@l2 = ($l=~/$log2{inst}/));
	return ("gprf",\@l2) if (@l2 = ($l=~/$log2{gprf}/));
	return ("dcch",\@l2) if (@l2 = ($l=~/$log2{dcch}/));
	return ("icch",\@l2) if (@l2 = ($l=~/$log2{icch}/));
	return ("l2ch",\@l2) if (@l2 = ($l=~/$log2{l2ch}/));
	return ("mmwr",\@l2) if (@l2 = ($l=~/$log2{mmwr}/));
	return ("mmwb",\@l2) if (@l2 = ($l=~/$log2{mmwb}/));
	return ("fprf",\@l2) if (@l2 = ($l=~/$log2{fprf}/));
	return ("c2rf",\@l2) if (@l2 = ($l=~/$log2{c2rf}/));
	return ("c3rf",\@l2) if (@l2 = ($l=~/$log2{c3rf}/));
	return ("xz",\@l2);															# all unrecognized lines, empty array
}

################################################################################
##############################   SQUEEZER MODE   ###############################
################################################################################
# 0. Things we want to squeeze are in %sq (see above)
# 1. For them, open logs to write (/dev/null otherwise);
# 2. Read through log1a.txt, recognize lines, put them in their logs.
################################################################################
if (@sq_in) {																	# option -s was given
print "Squeezer mode";
open(ALL,"${path1}log1a.txt") or die "\nCannot open ${path1}log1a.txt to read, closed";

open CMD,($sq{inst} ? (print ", traces" and "> ${path1}log1.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1.txt to write, closed";
open GPR,($sq{gprf} ? (print ", gpr" and "> ${path1}log1_gpr.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_gpr.txt to write, closed";
open FPR,($sq{fprf} ? (print ", fpr" and "> ${path1}log1_fpr.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_fpr.txt to write, closed";
open CP2,($sq{c2rf} ? (print ", cp2" and "> ${path1}log1_cp2.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_cp2.txt to write, closed";
open CP2,($sq{c3rf} ? (print ", cp3 (=cpv)" and "> ${path1}log1_cp2.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_cp2.txt to write, closed";
open CCH,($sq{dcch} ? (print ", dcache, L2cache" and "> ${path1}log1_cache.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_cache.txt to write, closed";
open ICH,($sq{icch} ? (print ", icache" and "> ${path1}log1_icache.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_icache.txt to write, closed";
open MWR,($sq{mmwr} ? (print ", mem_wr" and "> ${path1}log1_mem_wr.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_mem_wr.txt to write, closed";
open ADR,($sq{addr} ? (print ", addr" and "> ${path1}log1_addr.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_addr.txt to write, closed";
open EXC,($sq{exc} ? (print ", exc" and "> ${path1}log1_exc.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_exc.txt to write, closed";
open DSK,($sq{disk} ? (print ", disk" and "> ${path1}log1_disk.txt") : "> /dev/null")
		or die "Cannot open ${path1}log1_disk.txt to write, closed";
open DSKINS,($sq{disk} ? "> ${path1}disk_table.ini" : "> /dev/null")
		or die "Cannot open ${path1}disk_table.ini to write, closed";

print " will be squeezed.\n";

my $diskacc_inum = 0;
my $disk_count = 0;
my ($va, $ins) = (0, 0);
VLINE:	while (<ALL>) {
#	if (/$log1{inst}/) { print CMD $_; print ADR $_; next VLINE; }
	if (/$log1{inst}/) { print CMD $_; $va=$2; $ins=$4; next VLINE; }
#	if (/$log1{gprf}/) { print GPR $_; next VLINE; }
	if (/$log1{gprf}/) { print GPR "$1\tPC=0x$va    $ins\t$2=$3\n"; next VLINE; }	# familiar format, but takes slightly longer
	if (/$log1{fprf}/) { print FPR $_; next VLINE; }
	if (/$log1{c2rf}/) { print CP2 $_; next VLINE; }
	if (/$log1{c3rf}/) { print CP2 $_; next VLINE; }
	if (/$log1{dcch}/) { print CCH $_; next VLINE; }
	if (/$log1{icch}/) { print ICH $_; next VLINE; }
	if (/$log1{l2ch}/) { print CCH $_; next VLINE; }
	if (/$log1{mmwr}/) { print MWR $_; next VLINE; }
	if (/$log1{mmwb}/) { print MWR $_; next VLINE; }
	if (/\[va=/)       { print ADR $_; next VLINE; }
	if (/Exception/)   { print EXC $_; next VLINE; }
	if (/$log1{disk}/) {
		print DSK $_;
		mkdir "${path1}hex" or warn "Can't create directory 'hex' for disk data...";

		if ( $1 != $diskacc_inum ) {											# means new disk entry
			$diskacc_inum = $1;
			$disk_count++;
			printf DSKINS "%08x %s hex/disk%d.bin\n", $1, $2, $disk_count;
			open DSKDAT, "> ${path1}hex/disk${disk_count}.bin"
				or die "Cannot open ${path1}hex/disk${disk_count}.bin to write, closed";
		}
		print DSKDAT pack("H*", $3);
		next VLINE;
	}
}
close ALL;
close CMD;
close GPR;
close FPR;
close CP2;
close CCH;
close ICH;
close MWR;
close ADR;
close EXC;
close DSK;
close DSKINS;
exit 0;
}
################################################################################
##############################   COMPARER MODE   ###############################
################################################################################
# 1. Open logs (depends on log2 mode), name filehandles for them.
# 2. Main loop: read through log1a.txt:
#	2a. Recognize vmips line we want to compare, get its type.
#	2b. Fill buffer with up to 32 RTL lines of the same type, sort them;
#		other buffers may be filled during this step.
#	2c. Take vmips line and the first RTL line from buffer,
#		format their fields if needed, compare them;
#		break loop if mismatch, otherwise shift buffer and go on.
# 3. In case of mismatch, prepare and print report using special traces buffer.
################################################################################
else {																			# option -s was not given
my ($l1,$type);		# current log1 entry and its type;
my %buf = ();		# hash of buffers of LOG2 lines; one buffer for each type;
my %cmp = ();		# hash of subroutines for compare; one sub for each type;
my %fh = ();		# hash of scalars to address needed filehandles;
my @mis = ();		# data for mismatch report: (type, vin, log1 line, log2 line);
my @repo = ();		# special buffer of lines for report;
my $tot = 0;		# total number of instructions compared;
my $res = -1;		# exit code.

foreach (keys %log2) {
	$buf{$_} = [ () ];															# explicitly define empty buffers
}

open(ALL,"${path1}log1a.txt") or die "Cannot open ${path1}log1a.txt, closed";
if ($mode eq 'common') {
	open(LOG2,"${path2}log2_common.txt") or die "Cannot open ${path2}log2_common.txt, closed";
	%fh = (																		# handle log2_common.txt for all line types
		inst => *LOG2,
		gprf => *LOG2,
		fprf => *LOG2,
		c2rf => *LOG2,
		c3rf => *LOG2,
		dcch => *LOG2,
		icch => *LOG2,
		l2ch => *LOG2,
		mmwr => *LOG2,
		mmwb => *LOG2,
	);
} else {																		# don't open file if we skip it with option
	open(LOG2TR,"${path2}log2_uns.txt") or die "Cannot open ${path2}log2_uns.txt, closed";
	$noc{gprf} or open(LOG2GPR,"${path2}log2_gpr_uns.txt") or die "Cannot open ${path2}log2_gpr_uns, closed";
	$noc{fprf} or open(LOG2FPR,"${path2}log2_fpr_uns.txt") or die "Cannot open ${path2}log2_fpr_uns.txt, closed";
	($noc{c2rf} && $noc{c3rf}) or open(LOG2CP2,"${path2}log2_cp2_uns.txt") or die "Cannot open ${path2}log2_cp2_uns.txt, closed";
	($noc{dcch} && $noc{l2ch}) or open(LOG2CCH,"${path2}log2_cache.txt") or die "Cannot open ${path2}log2_cache.txt, closed";
	$noc{icch} or open(LOG2ICH,"${path2}log2_icache.txt") or die "Cannot open ${path2}log2_icache.txt, closed";
	($noc{mmwr} && $noc{mmwb}) or open(LOG2MWR,"${path2}log2_mem_wr.txt") or die "Cannot open ${path2}log2_mem_wr.txt, closed";
	%fh = (																		# specific handle for each line type
		inst => *LOG2TR,
		gprf => *LOG2GPR,
		fprf => *LOG2FPR,
		c2rf => *LOG2CP2,														# same file for cp2 and cp3
		c3rf => *LOG2CP2,
		dcch => *LOG2CCH,														# same file for dcache and L2cache
		l2ch => *LOG2CCH,
		icch => *LOG2ICH,														# same file for dcache and L2cache
		mmwr => *LOG2MWR,														# same file for direct writes and writebacks
		mmwb => *LOG2MWR,
	);
}

##############################   FILL BUFFERS   ################################
sub rtlsort {																	# sort by RTL instruction number (quicker, than perl's sort);
	my $buf = shift;
	for (my $i = $#{$buf}; $i; $i-- )	{										# put only most recent line in order, because other are already sorted
		if ($buf->[$i][0] < $buf->[$i-1][0])	{
			@$buf[$i-1,$i] = @$buf[$i,$i-1];
		} else	{
			last;	# for
		}
	}
}

sub fillbuf {																	# fill buffer of the type, that we want to compare on the current main loop step
	my $type = shift;
FB:	while ( scalar (@{$buf{$type}}) < 99 and									# EXIT 1: buffer has 99 entries;
			defined (my $line2 = readline($fh{$type})) ) {						# EXIT 2: no more lines in log2;
		my ($type2, $l2) = &gettype2($line2);
		if ($noc{$type2}) {
			print "Won't compare this line in $fh{$type}: $line2" if $verbose;
			next FB;
		}
		push @{$buf{$type2}}, $l2;												# fill other buffer
		rtlsort($buf{$type2}) if ($type2 =~ /(inst|gprf|fprf|c2rf|c3rf)/);		# sort buffer for certain types (put new entry in order, see above)
		last FB if ( scalar (@{$buf{$type2}}) > 299 );							# EXIT 3: other buffer has 300 entries;
	}
}

############################   TRACES COMPARISON   #############################
$cmp{inst} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{inst}}[0], both are refs to arrays;
	my $l2 = ( ${$buf{inst}}[0] or [ ("", "-"x 16, "-"x 8) ]);					# fake line if buffer is empty;
	my @mis = ("@{$l1}[1,3]" eq "@{$l2}[1,2]") ?								# splice significant fields;
			() :
			("TRACES", $l1->[0],												# Mismatch found in TRACES at instruction #706:
				"@{$l1}[1,3]",													#		ffffffff80002434 04110169 (vmips64)
				"@{$l2}[1,2]");													#		ffffffff80002438 00000000 (RTL)

	$l1->[1]=~s/^.{8}//;														# next line to report.txt
	$l2->[1]=~s/^.{8}//;														# take only 32 bits of VA to fit to the output format;
	push @repo, (sprintf "%7d %s | PC=0x%s\n",
		$l1->[0], "@$l2[1,2]", "@$l1[1,3,4]");									# action: new line in @repo!
	shift @repo if ( scalar(@repo) > 4 );										# store no more than 4 last lines;
	shift @{$buf{inst}};														# removing matching or mismatching line from buffer
	return @mis;
};

##############################   GPR COMPARISON   ##############################
$cmp{gprf} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{gprf}}[0], both are refs to arrays;
	my $l2 = ( ${$buf{gprf}}[0] or [ ("", "--", "-"x 16) ]);					# fake line if buffer is empty;
	$l2->[1] = $regdef{$l2->[1]};												# format fields: asm register name in RTL log;
	if ("@{$l1}[1,2]" eq "@{$l2}[1,2]") {										# splice significant fields;
		shift @{$buf{gprf}};													# remove matching line from buffer;
		return ();																# data match - nothing to do here;
	}
	return ("GPR", $l1->[0],													# Mismatch found in GPR at instruction #$l1->[0]:
				"$l1->[1]=0x$l1->[2]",											#		r1=ffffffffc0100070 (vmips64)
				"$l2->[1]=0x$l2->[2]");											#		r2=ffffffffc0100070 (RTL)
};

##############################   FPR COMPARISON   ##############################
$cmp{fprf} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{fprf}}[0], both are refs to arrays;
	my $l2 = ( ${$buf{fprf}}[0] or [ ("", "--", "-"x 16) ]);					# fake line if buffer is empty;
	$l1->[1] = sprintf ("%02d",$l1->[1]);										# format fields: 2-symbol register number;
	if ("@{$l1}[1,2]" eq "@{$l2}[1,2]" and										# compare data splice and...
		(not $l2->[3] or ($l2->[3] eq $l1->[3]))) {								# ...FCSR if any;
		shift @{$buf{fprf}};													# remove matching line from buffer;
		return ();																# data match - nothing to do here;
	}
	my @mis = ("FPR", $l1->[0],													# Mismatch found in FPR at instruction #$l1->[0]:
				"fr$l1->[1]=0x$l1->[2]",										#		fr1=ffffffffc0100070 (vmips64)
				"fr$l2->[1]=0x$l2->[2]");										#		fr2=ffffffffc0100070 (RTL)
	$mis[-2] .= " FCSR=$l1->[3]" if $l1->[3];
	$mis[-1] .= " FCSR=$l2->[3]" if $l2->[3];
	return @mis;
};

##############################   CP2 COMPARISON   ##############################
$cmp{c2rf} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{c2rf}}[0], both are refs to arrays;
	my $l2 = ( ${$buf{c2rf}}[0] or [ ("", "-", "--", "-"x 16) ]);				# fake line if buffer is empty;
	if ("@{$l1}[1,2,3]" eq "@{$l2}[1,2,3]" and									# compare data splice and...
		(not $l2->[4] or ($l2->[4] eq $l1->[4]))) {								# ...CCSR if any;
		shift @{$buf{c2rf}};													# remove matching line from buffer;
		return ();																# data match - nothing to do here;
	}
	my @mis = ("CP2", $l1->[0],													# Mismatch found in CP2 at instruction #$l1->[0]:
			"s$l1->[1]c$l1->[2]=0x$l1->[3]",									#		s0c21=0xffffffffc0100070 (vmips64)
			"s$l2->[1]c$l2->[2]=0x$l2->[3]");									#		s0c22=0xffffffffc0100070 (RTL)
	$mis[-2] .= " CCSR=$l1->[4]" if $l1->[4];
	$mis[-1] .= " CCSR=$l2->[4]" if $l2->[4];
	return @mis;
};

##############################   CP3 COMPARISON   ##############################
$cmp{c3rf} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{c3rf}}[0], both are refs to arrays;
	my $l2 = ( ${$buf{c3rf}}[0] or [ ("---------","--","-" x 32) ]);			# fake line if buffer is empty;
	if ("@{$l1}[1,2]" eq "@{$l2}[1,2]" and										# compare data splice and...
		(not $l2->[3] or ($l2->[3] eq $l1->[3]))) {								# ...CCSR if any;
		shift @{$buf{c3rf}};													# remove matching line from buffer;
		return ();																# data match - nothing to do here;
	}
	my @mis = ("CP3", $l1->[0],													# Mismatch found in CP3 at instruction #$l1->[0]:
			"c$l1->[1]=0x$l1->[2]",												#		c02=0x3e9657f23e9657f27fbfffff7fbfffff CCSR=30000000 (vmips64)
			"c$l2->[1]=0x$l2->[2]");											#		c03=0x3e9657f23e9657f27fbfffff7fbfffff CCSR=30000000 (RTL)
	$mis[-2].=" CCSR=$l1->[3]" if $l1->[3];
	$mis[-1].=" CCSR=$l2->[3]" if $l2->[3];
	return @mis;
};

############################   DCACHE COMPARISON   #############################
$cmp{dcch} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{dcch}}[0], both are refs to arrays;
	my $l2 = ( ${$buf{dcch}}[0] or [ ("","-"x8,"--","-","-","-"x9,"-"x4) ]);	# fake line if buffer is empty;
	$l1->[1] = "snooping" if $l1->[7];											# format fields: opcode = "snooping" for lines with "dma" descriptor;
	@{$l1}[8,9] = ($l1->[2]=~/[268]/) ? ("----","------") :						# format fields: add repl & WS fields (derived from ro) unless policy is 2,6 or 8 (no cache);
					(repl($l1->[6]),$ws_tab{$l1->[6]});
	$l2->[4] = ($l2->[3]) ? 8 : bin2dec($l2->[4]);								# format fields: derive decimal policy from "no_cache" & "attr";
	@{$l2}[7,8] = ("----","------") if ($l2->[4]=~/[268]/);						# format fields: don't compare repl & WS when policy is 2,6 or 8 (no cache);
	$l2->[4] = "-" if ($l2->[3] eq "-");										# format fields: "-" instead of digit for fake line;

	if ("@{$l1}[1,4,2,3,5,8,9]" ne "@{$l2}[1,2,4,5,6,7,8]")	{					# compare data splice;
		return ("DCACHE", $l1->[0],												# Mismatch found in DCACHE at instruction #$l1->[0]:
					"opcode line pol      PA hitv repl     WS\n\t".				#        opcode line pol      PA hitv repl     WS
					"@{$l1}[1,4,2,3,5,8,9]",									#        fc001ff8 7f 3 000001ff8 0100 1000 011101 (vmips64)
					"@{$l2}[1,2,4,5,6,7,8]");									#        fc001ff8 7f 3 000101ff8 0100 1000 011101 (RTL)
	}
	shift @{$buf{dcch}};														# remove matching line from buffer;
	return ();																	# data match - nothing to do here;
};

############################   ICACHE COMPARISON   #############################
$cmp{icch} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{dcch}}[0], both are refs to arrays;
	unless ( $l1->[2]=~/index (invalidate|store tag|load tag)/ ) {				# skip pair of lines in these cases (lines from some index CACHE instructions);
		my $l2 = ( ${$buf{icch}}[0] or
			[ ("","-"x16,"-"x9,"--","-"x8,"-"x3,"-"x8, "-"x24, "-"x8) ]);		# fake line if buffer is empty;
		my $way = ($l1->[6]=~/1(0*)/) ? length($1) : substr($l1->[7],0,1);		# format fields: $way is the number of hitted way or the way to be replaced;
		$l1->[20] = substr($l1->[8],-1-$way,1).substr($l1->[9],-1-$way,1)."0";	# format fields: extract certain 'valid' and 'lock' values from the log1 bitfields;
	
		if ("@{$l1}[3,4,5,6,20,7]" ne "@{$l2}[1,2,3,4,5,8]")	{				# compare data splice;
			return ("ICACHE", $l1->[0],											# Mismatch found in ICACHE at instruction #$l1->[0]:
						"              VA        PA line    hit VLW ro\n\t".	#	              VA        PA line    hit VLW ro
						"@{$l1}[3,4,5,6,20,7]",									# 	0000000000004080 000000080 04 00000010 100 02345671 (vmips64)
						"@{$l2}[1,2,3,4,5,8]");									# 	0000000000004080 000000080 04 00000010 000 02345671 (RTL)
		}
	}
	shift @{$buf{icch}};														# remove matching line from buffer;
	return ();																	# data match - nothing to do here;
};

###########################   L2 CACHE COMPARISON   ############################
$cmp{l2ch} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{l2ch}}[0], both are refs to arrays;
	my $l2 = (${$buf{l2ch}}[0] or [ ("","-"x8,"-"x3,"-"x4,"-"x4,"-"x4,"-"x6) ]);# fake line if buffer is empty;
	$l1->[3] = "----"															# format fields: do not compare hitv field...
		if (! unpack ("N*",pack("H8",$l1->[1]) & $fc13 ^ $bc03));				# ...for index L2 cache instructions;
	$l1->[1] = "snooping" if $l1->[6];											# format fields: opcode = "snooping" for lines with "dma" descriptor;
	@{$l1}[7,8] = (length($l1->[4]) == 4) ?										# format fields: add repl & WS fields (derived from ro)...
		(repl($l1->[4]),$ws_tab{$l1->[4]}) : ("","");							# ...for 4-way case;
	@{$l2}[5,6] = ("","") if (not defined $l2->[5]);							# 1-way case
	$l2->[3] = "----"															# format fields: do not compare hitv field...
		if (! unpack ("N*",pack("H8",$l2->[1]) & $fc13 ^ $bc03));				# ...for index L2 cache instructions;

	if ("@{$l1}[1,2,3,5,7,8]" ne "@{$l2}[1,2,3,4,5,6]")	{						# compare data splice;
		if (length $l1->[5] != length $l2->[4])	{
			die "You are comparing 1-way vs 4-way L2 cache, refusing";			# special case: perhaps we are to rerun the test series entirely;
		}
		return ("L2CACHE", $l1->[0],											# Mismatch found in L2CACHE at instruction #$l1->[0]:
					"opcode  line hitv    W repl     WS\n\t".					#        opcode  line hitv    W repl     WS
					"@{$l1}[1,2,3,5,7,8]",										#        d5260000 7fd 0100 1111 1000 011101 (vmips64)
					"@{$l2}[1,2,3,4,5,6]");										#        d5260000 7fd 0100 1011 1000 011101 (RTL)
	}
	shift @{$buf{l2ch}};														# remove matching line from buffer;
	return ();																	# data match - nothing to do here;
};

#########################   MEMORY WRITES COMPARISON   #########################
$cmp{mmwr} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{mmwr}}[0], both are refs to arrays;
	my $l2 = ( ${$buf{mmwr}}[0] or [ ("", "-"x 9, "-"x 16, "-"x 8) ]);			# fake line if buffer is empty;
	$l1->[1] =~ s/(.)$/$algn{"\L$1"}/;											# format fields: align address to 8 bytes in vmips log;

	if ("@{$l1}[1..3]" ne "@{$l2}[1..3]") {										# compare data splice;
		return ("MEMORY WRITE", $l1->[0],										# Mismatch found in MEMORY WRITE at instruction #$l1->[0]:
					"       PA             data       be WB\n\t".				#              PA             data       be WB
					"@{$l1}[1..3] 0",											#		0000c0008 000000000000002e 00001111 0 (vmips64)
					"@{$l2}[1..3] 0");											#		0000c0008 ffffffffc0139b36 11111111 0 (RTL)
	}
	shift @{$buf{mmwr}};														# remove matching line from buffer;
	return ();																	# data match - nothing to do here;
};

#######################   MEMORY WRITEBACKS COMPARISON   #######################
$cmp{mmwb} = sub {																# compare vmips line $l1 and RTL line, first in the buffer, ${$buf{mmwb}}[0], both are refs to arrays;
	my $l2 = ( ${$buf{mmwb}}[0] or [ ("", "-"x 9, "-"x 16, "-"x 8) ]);			# fake line if buffer is empty;
	$l1->[1] =~ s/(.)$/$algn{"\L$1"}/;											# format fields: align address to 8 bytes in vmips log;

	if ("@{$l1}[1..3]" ne "@{$l2}[1..3]") {										# compare data splice;
		return ("MEMORY WRITEBACK", $l1->[0],									# Mismatch found in MEMORY WRITEBACK at instruction #$l1->[0]:
					"       PA             data       be WB\n\t".				#              PA             data       be WB
					"@{$l1}[1..3] 1",											#		0000c0008 000000000000002e 00001111 0 (vmips64)
					"@{$l2}[1..3] 1");											#		0000c0008 ffffffffc0139b36 11111111 0 (RTL)
	}
	shift @{$buf{mmwb}};														# remove matching line from buffer;
	return ();																	# data match - nothing to do here;
};

################################   MAIN LOOP   #################################
################################################################################
VL: while ( defined (my $line1 = <ALL> )) {										# read through log1a.txt
	($type, $l1) = &gettype($line1);
	if ($noc{$type}) {															# we are not comapring this type
		print "Won't compare this line in LOG1: $line1" if $verbose;
		next VL;
	}
	$tot = $l1->[0];															# instructions counter
	fillbuf($type);
	last VL if ( @mis = &{$cmp{$type}} );										# break loop if mismatch found
}

###############################   MAKE REPORT   ################################
if (@mis) {
	while ( scalar(@{$buf{inst}}) < 7 ) {										# in case of premature log2 file end...
		push @{$buf{inst}}, [ ("", "-"x 16, "-"x 8) ];							# ...fill buffer with fake lines
	}
	while ( $#repo < 6 and defined (my $line1 = <ALL>))	{						# report should contain 7 lines (3 before mismatch, 3 after)
		if ( my @l1 = ($line1=~/$log1{inst}/) ) {								# 4 from these 7 are from earlier traces handling, another 3 from buffer;
			my @l2 = @{shift @{$buf{inst}}};
			$l1[1]=~s/^.{8}//;													# take only 32 bits of VA to fit to the output format;
			$l2[1]=~s/^.{8}//;
			push @repo, (sprintf "%7d %s | PC=0x%s\n",							# fill report
				$l1[0], "@l2[1,2]", "@l1[1,3,4]");
		}
	}
	print "Mismatch found in $mis[0] at instruction #$mis[1]:\n";				# $mis[0] is type, $mis[1] is vmips instruction number;
	print "{{{\n          RTL log:        | vmips log:\n";
	print foreach (@repo);
	print "\t$mis[2] (vmips64)\n";												# $mis[2] is vmips data (and format string in some cases);
	print "\t$mis[3] (RTL)\n";													# $mis[2] is RTL data;
	print "}}}\n";																# curly braces are for wiki-format;
	$res = 1;
} else {
	print "No mismatches were found in $tot instructions!\n";					# total number of instructions compared;
	$res = 0;
}

close ALL;
if ($mode eq 'common') {
	close LOG2;
} else {
	close LOG2TR;
	close LOG2GPR;
	close LOG2FPR;
	close LOG2CP2;
	close LOG2CCH;
	close LOG2ICH;
	close LOG2MWR;
}
exit $res;

}	# comparer mode
