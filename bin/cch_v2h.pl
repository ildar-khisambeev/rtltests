#!/usr/bin/perl -w

# by:		convert dump cache from vmips format to ncsim format
# version:	1.37.1, 2013-11-15
# Author:	Anna Krasnyuk, Ildar Khisambeev, Igor Melentyev
# run:		./cch_v2h.pl [--null] [--file=cachefile] [--cp2memfile=cp2memfile]

#version history
#1.1, 2005-09-20, added Way Selection files
#1.2, 2005-10-19, first icache, then dcache dump; 8 icache data files
#1.4, 2006-03-09, now L2 cache dump can be restored
#1.4i, 2006-03-24, patched line 78;
#1.5, 2006-05-16, added usege options;
#1.6, 2009-05-20, new format for icache hex files added (68 bit icache memories for v3);
#1.7, 2010-01-27, 8 new L2 tag files added;
#1.8, 2010-03-16, 8 new dcache files added;
#1.9, 2010-07-15, 5 parity files for dcache & icache added;
#1.10, 2010-07-29, compatibility with 4way L2 cache added;
#1.11, 2010-09-01, ws field order fixed for 4way L2;
#1.12, 2010-09-06, 20-bit tag now supported for 4way L2;
#1.13, 2010-09-07, fixed regexp for scache string recognition;
#1.14, 2010-09-13, added parity bits for icache tags;
#1.15, 2010-09-14, added parity bits for dcache tags, modify parity data icache file,
#1.16, 2010-09-15, added parity bit for 4/8 way all VL bit icache;	<===================================== USE FOR V3.1 OR EARLIER
#1.17, 2010-10-29, hex files renamed (for 4 4 1 ways only);
#1.171, 2010-11-03, updated for 4 4 4 compatibility;
#1.18, 2010-11-08, full 4/8 4 1/4 cache ways compatibility (for 256K L2);
#1.181, 2010-11-27, preparing another tag files for 4way L2;
#1.19, 2010-11-29, full compatibility for 256KB/512KB/1MB L2; routines optimized in L2 section;
#1.19a, 2010-11-30, patch number lines L2 (line 475);
#1.19b, 2010-12-01, solved case of empty dump_cache lines before EOF;
#1.20, 2010-12-02, added generation hamming files (union hamm_cache.pl);
#1.21, 2010-12-03, format of indices in the names for L2 data/tags changed;
#1.22, 2010-12-03, format of indices in the names for L2 hammings files changed;
#1.23, 2010-12-03, format of indices in the names for L2 data    files for 1 way changed; 512K L2 by default instead of 1024K;
#1.24, 2010-12-03, ------------//----------------------- hamming ---------//------------;
#1.25, 2011-02-08, size of tag field for L2 now fits all L2 sizes;
#1.26, 2011-02-22, added calculation of parity bit for dcache vlw file (which was equal zero before);
#1.27, 2011-02-24, corrections L2 tag hamming bits in mode L2=128Kb (4way);
#1.28, 2011-02-24, added generation of dma_h_mem{1..16}.hex files;
#1.29, 2011-09-26, hamming bits computing optimized;
#1.30, 2011-09-29, overall script optimization;						<===================================== USE FOR THE OLD CACHEFILE FORMAT
#1.31, 2011-11-07, compatible for the new cachefile format, makes 4-way hexes in 1-way cachefile case;
#1.32, 2011-11-10, converts cachefile and cp2memfile separately;
#1.33, 2011-11-10, additional optimization of the null files case;
#1.34, 2011-11-10, fixed bug in sub add_pb_ich: workaround for 32-bit hosts;
#1.35, 2013-01-11, new L2 cache data files for v3.3 new hex format: l2_mem3_XXX.hex;
#1.36, 2013-09-10, usage() added; additional option --null for generating null hex files;
#1.37, 2013-10-31, new file names and paths (Tkachenko format);
#1.37.1, 2013-11-15, fix typo in legacy file names (l2_tag_XXX.hex -> l2_tag_512x24_XXX.hex);


use Data::Dumper;
use Getopt::Long;
$|=1;   # forces a buffer flush after every write or print; see 'perldoc perlvar';

sub usage	{
	print STDERR "Usage: $0 [--null|--0] [--[cache]file=CACHEFILE] [--cp2memfile=CP2MEMFILE]\n";
	print STDERR "       no options\t\t- look for 'dump_cache' as CACHEFILE and/or 'dump_cp2mem' as CP2MEMFILE;\n";
	print STDERR "       --null|--0\t\t- generate null hex files (suppresses other options);\n";
	print STDERR "       --[cache]file=CACHEFILE\t- generate cache hex files from CACHEFILE vmips file;\n";
	print STDERR "       --cp2memfile=CP2MEMFILE\t- generate cp2 memory hex files from CP2MEMFILE vmips file;\n";
#	print STDERR "Note: use with vmips64 rev.4321 or later!\n";
}

GetOptions	(
	"null|0" => \$null,
	"cp2memfile=s" => \$cp2memfile,
	"file|cachefile=s" => \$cachefile,
);

if (@ARGV) { &usage(); print "Wrong options: @ARGV\n"; exit 2; }

if ( not defined $cachefile and not defined $cp2memfile and not $null)	{
	print "No input file. ";
	if (-f "dump_cache")	{
		print "Trying cachefile 'dump_cache'. ";
		$cachefile = "dump_cache";
	}
	if (-f "dump_cp2mem")	{
		print "Trying cp2memfile 'dump_cp2mem'. ";
		$cp2memfile = "dump_cp2mem";
	}
	print "\n";
}

##########################   HAMMING COEFFICIENTS AND OTHER CONSTANTS   #############################

$h18c9 = pack("B20","00110110100000000000");
$h18c8 = pack("B20","00101101010000000000");
$h18c7 = pack("B20","00011011001000000000");
$h18c6 = pack("B20","00111000111000000000");
$h18c5 = pack("B20","00000111111000000000");
$h18c4 = pack("B20","00000000000110110100");
$h18c3 = pack("B20","00000000000101101010");
$h18c2 = pack("B20","00000000000011011001");
$h18c1 = pack("B20","00000000000111000111");
$h18c0 = pack("B20","00000000000000111111");

$h24c5 = pack("B24","000011101101001101001000");
$h24c4 = pack("B24","000111011010101010100100");
$h24c3 = pack("B24","000110110110010110010010");
$h24c2 = pack("B24","000101110001110001110001");
$h24c1 = pack("B24","000100001111110000001111");
$h24c0 = pack("B24","000100000000001111111111");

$h64c7 = pack("B64","1111111111111111111111111111110000000000000000000000000000000000");
$h64c6 = pack("B64","1111111111110000000000000000001111111111111111110000000000000000");
$h64c5 = pack("B64","1111110000001111110000000000001111111100000000001111111111000000");
$h64c4 = pack("B64","1111001100001100001111110000001100000011110000001111000000111111");
$h64c3 = pack("B64","1000101010001010001111001111001011100010001110001000111000111100");
$h64c2 = pack("B64","0100010101000101001100101100100111011001001101100100110110110010");
$h64c1 = pack("B64","0010010100100100101010101010010110110100101011010010101101101001");
$h64c0 = pack("B64","0001101000011000010110111001111001110000011000110001100011100111");

%taglen = (		# used in &tagL2 as substr argument
	"512"  => -22,
	"1024" => -21,
	"2048" => -20,
	"4096" => -19,
	"8192" => -18,
);

%ws_tab = (                                                                                                                                                                                   
	"0123" => "00", "1023" => "04", "2013" => "22", "3012" => "19",                                                                                                               
	"0132" => "01", "1032" => "05", "2031" => "32", "3021" => "1b",                                                                                                               
	"0213" => "02", "1203" => "24", "2103" => "26", "3102" => "1d",                                                                                                               
	"0231" => "12", "1230" => "2c", "2130" => "2e", "3120" => "3d",                                                                                                               
	"0312" => "11", "1302" => "0d", "2301" => "3a", "3201" => "3b",                                                                                                               
	"0321" => "13", "1320" => "2d", "2310" => "3e", "3210" => "3f"                                                                                                                
);

##########################   NULL FILE   ############################################################

if ($null)	{
print "Creating null hex files.\n";
my $shm_path = "/dev/shm/" if (-d "/dev/shm");
open (NULCCH, "> ${shm_path}nullcache.$$") or die "Can't open file ${shm_path}nullcache.$$ for write, closed";
print NULCCH "icache sets=8 lines=128\n";
for (1..128) {
	for (1..8) {
		print NULCCH "0000000000000 0 0 0 0000000000000000 0000000000000000 0000000000000000 0000000000000000   ";
	}
	print NULCCH "01234567\n";
}
print NULCCH "dcache sets=4 lines=128\n";
for (1..128) {
	for (1..4) {
		print NULCCH "0000000000000 0 0 0 0000000000000000 0000000000000000 0000000000000000 0000000000000000   ";
	}
	print NULCCH "0123\n";
}
print NULCCH "scache sets=4 lines=4096\n";
for (1..4096) {
	for (1..4) {
		print NULCCH "0000000000000 0 0 0 0000000000000000 0000000000000000 0000000000000000 0000000000000000   ";
	}
	print NULCCH "0123\n";
}
close NULCCH;

$cachefile = "${shm_path}nullcache.$$";
}

##########################   CACHEFILE   ############################################################

if ($cachefile)	{
open (LCH, "$cachefile") or die "Can't open file $cachefile for read, closed";
mkdir "hex";

	######################   INSTRUCTIONS CACHE   ###################################################
print "Converting icache...";
mkdir "hex/ICH_4";
mkdir "hex/ICH_8";

#open (IDC1,  "> ic_dat_n1_256_68.hex")  or die "Cannot open ic_dat_n1_256_68.hex file";
open (IDC1,  "> hex/ICH_8/ic8_dat_w1_m1.hex") or die "Cannot open hex/ICH_8/ic8_dat_w1_m1.hex file";
open (IDC2,  "> hex/ICH_8/ic8_dat_w1_m2.hex") or die "Cannot open hex/ICH_8/ic8_dat_w1_m2.hex file";
open (IDC3,  "> hex/ICH_8/ic8_dat_w2_m1.hex") or die "Cannot open hex/ICH_8/ic8_dat_w2_m1.hex file";
open (IDC4,  "> hex/ICH_8/ic8_dat_w2_m2.hex") or die "Cannot open hex/ICH_8/ic8_dat_w2_m2.hex file";
open (IDC5,  "> hex/ICH_8/ic8_dat_w3_m1.hex") or die "Cannot open hex/ICH_8/ic8_dat_w3_m1.hex file";
open (IDC6,  "> hex/ICH_8/ic8_dat_w3_m2.hex") or die "Cannot open hex/ICH_8/ic8_dat_w3_m2.hex file";
open (IDC7,  "> hex/ICH_8/ic8_dat_w4_m1.hex") or die "Cannot open hex/ICH_8/ic8_dat_w4_m1.hex file";
open (IDC8,  "> hex/ICH_8/ic8_dat_w4_m2.hex") or die "Cannot open hex/ICH_8/ic8_dat_w4_m2.hex file";
open (IDC9,  "> hex/ICH_8/ic8_dat_w5_m1.hex") or die "Cannot open hex/ICH_8/ic8_dat_w5_m1.hex file";
open (IDC10, "> hex/ICH_8/ic8_dat_w5_m2.hex") or die "Cannot open hex/ICH_8/ic8_dat_w5_m2.hex file";
open (IDC11, "> hex/ICH_8/ic8_dat_w6_m1.hex") or die "Cannot open hex/ICH_8/ic8_dat_w6_m1.hex file";
open (IDC12, "> hex/ICH_8/ic8_dat_w6_m2.hex") or die "Cannot open hex/ICH_8/ic8_dat_w6_m2.hex file";
open (IDC13, "> hex/ICH_8/ic8_dat_w7_m1.hex") or die "Cannot open hex/ICH_8/ic8_dat_w7_m1.hex file";
open (IDC14, "> hex/ICH_8/ic8_dat_w7_m2.hex") or die "Cannot open hex/ICH_8/ic8_dat_w7_m2.hex file";
open (IDC15, "> hex/ICH_8/ic8_dat_w8_m1.hex") or die "Cannot open hex/ICH_8/ic8_dat_w8_m1.hex file";
open (IDC16, "> hex/ICH_8/ic8_dat_w8_m2.hex") or die "Cannot open hex/ICH_8/ic8_dat_w8_m2.hex file";

open (IPAR1, "> hex/ICH_8/ic8_dat_par_m1.hex") or die "Cannot open hex/ICH_8/ic8_dat_par_m1.hex file";
open (IPAR2, "> hex/ICH_8/ic8_dat_par_m2.hex") or die "Cannot open hex/ICH_8/ic8_dat_par_m2.hex file";

open (ITAG1, "> hex/ICH_8/ic8_tag_w1_m1.hex") or die "Cannot open hex/ICH_8/ic8_tag_w1_m1.hex file";
open (ITAG2, "> hex/ICH_8/ic8_tag_w2_m1.hex") or die "Cannot open hex/ICH_8/ic8_tag_w1_m2.hex file";
open (ITAG3, "> hex/ICH_8/ic8_tag_w3_m1.hex") or die "Cannot open hex/ICH_8/ic8_tag_w1_m3.hex file";
open (ITAG4, "> hex/ICH_8/ic8_tag_w4_m1.hex") or die "Cannot open hex/ICH_8/ic8_tag_w1_m4.hex file";
open (ITAG5, "> hex/ICH_8/ic8_tag_w5_m1.hex") or die "Cannot open hex/ICH_8/ic8_tag_w1_m5.hex file";
open (ITAG6, "> hex/ICH_8/ic8_tag_w6_m1.hex") or die "Cannot open hex/ICH_8/ic8_tag_w1_m6.hex file";
open (ITAG7, "> hex/ICH_8/ic8_tag_w7_m1.hex") or die "Cannot open hex/ICH_8/ic8_tag_w1_m7.hex file";
open (ITAG8, "> hex/ICH_8/ic8_tag_w8_m1.hex") or die "Cannot open hex/ICH_8/ic8_tag_w1_m8.hex file";

open (IVL, "> hex/ICH_8/ic8_vlw_m1.hex") or die "Cannot open hex/ICH_8/ic8_vlw_m1.hex file";
open (IWS, "> hex/ICH_4/ic4_ws_m1.hex") or die "Cannot open hex/ICH_4/ic4_ws_m1.hex file";
open (IWS8, "> hex/ICH_8/ic8_ws_m1.hex") or die "Cannot open hex/ICH_8/ic8_ws_m1.hex file";

$line=<LCH>;
$line=~/icache sets=(\d+) lines=(\d+)/ or die "Can't recognize icache id line, closed";
$ic_ways=$1;	die "Unsupported number of icache ways declared ($ic_ways), closed" unless ($ic_ways==4 || $ic_ways==8);
$ic_lines=$2;	die "Unsupported number of icache lines declared ($ic_lines), closed" unless ($ic_lines==128);
print "${ic_ways}way...";

for (1..$ic_lines)	{
	my $line=<LCH>;
	my @cl=expand_ic($line);

	print IDC1 &add_pb_ich($cl[4]),"\n",&add_pb_ich($cl[6]),"\n";
	print IDC2 &add_pb_ich($cl[5]),"\n",&add_pb_ich($cl[7]),"\n";
	print IDC3 &add_pb_ich($cl[12]),"\n",&add_pb_ich($cl[14]),"\n";
	print IDC4 &add_pb_ich($cl[13]),"\n",&add_pb_ich($cl[15]),"\n";
	print IDC5 &add_pb_ich($cl[20]),"\n",&add_pb_ich($cl[22]),"\n";
	print IDC6 &add_pb_ich($cl[21]),"\n",&add_pb_ich($cl[23]),"\n";
	print IDC7 &add_pb_ich($cl[28]),"\n",&add_pb_ich($cl[30]),"\n";
	print IDC8 &add_pb_ich($cl[29]),"\n",&add_pb_ich($cl[31]),"\n";
	print IDC9 &add_pb_ich($cl[36]),"\n",&add_pb_ich($cl[38]),"\n";
	print IDC10 &add_pb_ich($cl[37]),"\n",&add_pb_ich($cl[39]),"\n";
	print IDC11 &add_pb_ich($cl[44]),"\n",&add_pb_ich($cl[46]),"\n";
	print IDC12 &add_pb_ich($cl[45]),"\n",&add_pb_ich($cl[47]),"\n";
	print IDC13 &add_pb_ich($cl[52]),"\n",&add_pb_ich($cl[54]),"\n";
	print IDC14 &add_pb_ich($cl[53]),"\n",&add_pb_ich($cl[55]),"\n";
	print IDC15 &add_pb_ich($cl[60]),"\n",&add_pb_ich($cl[62]),"\n";
	print IDC16 &add_pb_ich($cl[61]),"\n",&add_pb_ich($cl[63]),"\n";

	print IPAR1 par_64_8($cl[29]),par_64_8($cl[28]),par_64_8($cl[21]),par_64_8($cl[20]),par_64_8($cl[13]),par_64_8($cl[12]),par_64_8($cl[5]),par_64_8($cl[4]),"\n";
	print IPAR1 par_64_8($cl[31]),par_64_8($cl[30]),par_64_8($cl[23]),par_64_8($cl[22]),par_64_8($cl[15]),par_64_8($cl[14]),par_64_8($cl[7]),par_64_8($cl[6]),"\n";
	print IPAR2 par_64_8($cl[61]),par_64_8($cl[60]),par_64_8($cl[53]),par_64_8($cl[52]),par_64_8($cl[45]),par_64_8($cl[44]),par_64_8($cl[37]),par_64_8($cl[36]),"\n";
	print IPAR2 par_64_8($cl[63]),par_64_8($cl[62]),par_64_8($cl[55]),par_64_8($cl[54]),par_64_8($cl[47]),par_64_8($cl[46]),par_64_8($cl[39]),par_64_8($cl[38]),"\n";

	my $tag1=substr($cl[0],-6);
	my $tag2=substr($cl[8],-6);
	my $tag3=substr($cl[16],-6);
	my $tag4=substr($cl[24],-6);
	my $tag5=substr($cl[32],-6);
	my $tag6=substr($cl[40],-6);
	my $tag7=substr($cl[48],-6);
	my $tag8=substr($cl[56],-6);
	print ITAG1 &pb($tag1),$tag1,"\n";
	print ITAG2 &pb($tag2),$tag2,"\n";
	print ITAG3 &pb($tag3),$tag3,"\n";
	print ITAG4 &pb($tag4),$tag4,"\n";
	print ITAG5 &pb($tag5),$tag5,"\n";
	print ITAG6 &pb($tag6),$tag6,"\n";
	print ITAG7 &pb($tag7),$tag7,"\n";
	print ITAG8 &pb($tag8),$tag8,"\n";

	my ($l0,$l1,$v0,$v1,$v2,$v3,$v4,$v5,$v6,$v7) = @cl[ 2,10,1,9,17,25,33,41,49,57 ];
	my $xor_vwl = $v0^$v1^$v2^$v3^$v4^$v5^$v6^$v7^$l0^$l1;
	my $ivl = "00000".$v4.$v0.$v5.$v1.$v6.$v2.$v7.$v3.$l0.$l1.$xor_vwl;
	print IVL substr(bin2hex($ivl),-3),"\n";
	print IWS "$cl[65]\n";
	print IWS8 "$cl[64]\n";
}

close IDC1; close IDC9;  close ITAG1; close IPAR1;
close IDC2; close IDC10; close ITAG2; close IPAR2;
close IDC3; close IDC11; close ITAG3; close IVL;
close IDC4; close IDC12; close ITAG4; close IWS;
close IDC5; close IDC13; close ITAG5; close IWS8;
close IDC6; close IDC14; close ITAG6;
close IDC7; close IDC15; close ITAG7;
close IDC8; close IDC16; close ITAG8;

symlink "../ICH_8/ic8_dat_w1_m1.hex","hex/ICH_4/ic4_dat_w1_m1.hex";
symlink "../ICH_8/ic8_dat_w1_m2.hex","hex/ICH_4/ic4_dat_w1_m2.hex";
symlink "../ICH_8/ic8_dat_w2_m1.hex","hex/ICH_4/ic4_dat_w2_m1.hex";
symlink "../ICH_8/ic8_dat_w2_m2.hex","hex/ICH_4/ic4_dat_w2_m2.hex";
symlink "../ICH_8/ic8_dat_w3_m1.hex","hex/ICH_4/ic4_dat_w3_m1.hex";
symlink "../ICH_8/ic8_dat_w3_m2.hex","hex/ICH_4/ic4_dat_w3_m2.hex";
symlink "../ICH_8/ic8_dat_w4_m1.hex","hex/ICH_4/ic4_dat_w4_m1.hex";
symlink "../ICH_8/ic8_dat_w4_m2.hex","hex/ICH_4/ic4_dat_w4_m2.hex";
symlink "../ICH_8/ic8_dat_par_m1.hex","hex/ICH_4/ic4_dat_par_m1.hex";
symlink "../ICH_8/ic8_tag_w1_m1.hex","hex/ICH_4/ic4_tag_w1_m1.hex";
symlink "../ICH_8/ic8_tag_w2_m1.hex","hex/ICH_4/ic4_tag_w2_m1.hex";
symlink "../ICH_8/ic8_tag_w3_m1.hex","hex/ICH_4/ic4_tag_w3_m1.hex";
symlink "../ICH_8/ic8_tag_w4_m1.hex","hex/ICH_4/ic4_tag_w4_m1.hex";
symlink "../ICH_8/ic8_vlw_m1.hex","hex/ICH_4/ic4_vlw_m1.hex";

symlink sprintf("ICH_8/ic8_dat_w%d_m%d.hex",($_-1)/2+1,($_-1)%2+1), "hex/ic_dat_n${_}_256_68.hex" for (1..16);
symlink "ICH_8/ic8_tag_w${_}_m1.hex", "hex/ic_tag_n${_}_128_32.hex" for (1..8);
symlink "ICH_8/ic8_dat_par_m1.hex", "hex/ic_par_n1_256_64.hex";
symlink "ICH_8/ic8_dat_par_m2.hex", "hex/ic_par_n2_256_64.hex";
symlink "ICH_8/ic8_vlw_m1.hex", "hex/ic_vlw_128_11.hex";
symlink "ICH_8/ic8_ws_m1.hex", "hex/ic_ws_128_24.hex";
symlink "ICH_4/ic4_ws_m1.hex", "hex/ic_ws_128_6.hex";

	######################   DATA CACHE   ###################################################
print "done!\nConverting data cache....";
mkdir "hex/DCH";

open (DDC1, "> hex/DCH/dc_dat_w1_m1.hex") or die "Cannot open hex/DCH/dc_dat_w1_m1.hex file";
open (DDC2, "> hex/DCH/dc_dat_w1_m2.hex") or die "Cannot open hex/DCH/dc_dat_w1_m2.hex file";
open (DDC3, "> hex/DCH/dc_dat_w2_m1.hex") or die "Cannot open hex/DCH/dc_dat_w2_m1.hex file";
open (DDC4, "> hex/DCH/dc_dat_w2_m2.hex") or die "Cannot open hex/DCH/dc_dat_w2_m2.hex file";
open (DDC5, "> hex/DCH/dc_dat_w3_m1.hex") or die "Cannot open hex/DCH/dc_dat_w3_m1.hex file";
open (DDC6, "> hex/DCH/dc_dat_w3_m2.hex") or die "Cannot open hex/DCH/dc_dat_w3_m2.hex file";
open (DDC7, "> hex/DCH/dc_dat_w4_m1.hex") or die "Cannot open hex/DCH/dc_dat_w4_m1.hex file";
open (DDC8, "> hex/DCH/dc_dat_w4_m2.hex") or die "Cannot open hex/DCH/dc_dat_w4_m2.hex file";

open (DPAR1, "> hex/DCH/dc_dat_par_m1.hex") or die "Cannot open hex/DCH/dc_dat_par_m1.hex file";
open (DPAR2, "> hex/DCH/dc_dat_par_m2.hex") or die "Cannot open hex/DCH/dc_dat_par_m2.hex file";
open (DPAR3, "> hex/DCH/dc_dat_par_m3.hex") or die "Cannot open hex/DCH/dc_dat_par_m3.hex file";
open (DPAR4, "> hex/DCH/dc_dat_par_m4.hex") or die "Cannot open hex/DCH/dc_dat_par_m4.hex file";

open (DTAG1, "> hex/DCH/dc_tag_w1_m1.hex") or die "Cannot open hex/DCH/dc_tag_w1_m1.hex file";
open (DTAG2, "> hex/DCH/dc_tag_w2_m1.hex") or die "Cannot open hex/DCH/dc_tag_w2_m1.hex file";
open (DTAG3, "> hex/DCH/dc_tag_w3_m1.hex") or die "Cannot open hex/DCH/dc_tag_w3_m1.hex file";
open (DTAG4, "> hex/DCH/dc_tag_w4_m1.hex") or die "Cannot open hex/DCH/dc_tag_w4_m1.hex file";

open (DVL, "> hex/DCH/dc_vlw_m1.hex") or die "Cannot open hex/DCH/dc_vlw_m1.hex file";
open (DWS, "> hex/DCH/dc_ws_m1.hex") or die "Cannot open hex/DCH/dc_ws_m1.hex file";

$line=<LCH>;
$line=~/dcache sets=(\d+) lines=(\d+)/;
$dc_ways=$1;	die "Unsupported number of dcache ways declared ($dc_ways), closed" unless ($dc_ways==4);
$dc_lines=$2;	die "Unsupported number of dcache lines declared ($dc_lines), closed" unless ($dc_lines==128);
#print "${dc_ways}way...";


for (1..$dc_lines)	{
	my $line=<LCH>;
	my @cl=split (" ", $line);

	print DDC1 "$cl[4]\n$cl[6]\n";
	print DDC2 "$cl[5]\n$cl[7]\n";
	print DDC3 "$cl[12]\n$cl[14]\n";
	print DDC4 "$cl[13]\n$cl[15]\n";
	print DDC5 "$cl[20]\n$cl[22]\n";
	print DDC6 "$cl[21]\n$cl[23]\n";
	print DDC7 "$cl[28]\n$cl[30]\n";
	print DDC8 "$cl[29]\n$cl[31]\n";

	print DPAR1 par_64_8($cl[4]),par_64_8($cl[5]),"\n",par_64_8($cl[6]),par_64_8($cl[7]),"\n";
	print DPAR2 par_64_8($cl[12]),par_64_8($cl[13]),"\n",par_64_8($cl[14]),par_64_8($cl[15]),"\n";
	print DPAR3 par_64_8($cl[20]),par_64_8($cl[21]),"\n",par_64_8($cl[22]),par_64_8($cl[23]),"\n";
	print DPAR4 par_64_8($cl[28]),par_64_8($cl[29]),"\n",par_64_8($cl[30]),par_64_8($cl[31]),"\n";

	my $tag1=substr($cl[0],-6);
	my $tag2=substr($cl[8],-6);
	my $tag3=substr($cl[16],-6);
	my $tag4=substr($cl[24],-6);
	print DTAG1 &pb($tag1),$tag1,"\n";
	print DTAG2 &pb($tag2),$tag2,"\n";
	print DTAG3 &pb($tag3),$tag3,"\n";
	print DTAG4 &pb($tag4),$tag4,"\n";

	my ($l0,$l1,$v0,$v1,$v2,$v3) = @cl[ 2,10,1,9,17,25 ];
	my $xor_vwl = $v0^$v1^$v2^$v3^$l0^$l1;
	my $dvl = "00".$v0."0".$v1."0".$v2."0".$v3."0000".$l0.$l1.$xor_vwl;
	print DVL bin2hex($dvl),"\n";
	print DWS "$ws_tab{$cl[32]}\n";
}
close DDC1; close DPAR1;
close DDC2; close DPAR2;
close DDC3; close DPAR3;
close DDC4; close DPAR4;
close DDC5; close DTAG1;
close DDC6; close DTAG2;
close DDC7; close DTAG3;
close DDC8; close DTAG4;
close DVL;
close DWS;

symlink sprintf("DCH/dc_dat_w%d_m%d.hex",($_-1)/2+1,($_-1)%2+1), "hex/dc_dat_n${_}_256_64.hex" for (1..8);
symlink "DCH/dc_tag_w${_}_m1.hex", "hex/dc_tag_n${_}_128_32.hex" for (1..4);
symlink "DCH/dc_dat_par_m${_}.hex", "hex/dc_par_n${_}_256_16.hex" for (1..4);
symlink "DCH/dc_vlw_m1.hex", "hex/dc_vlw_128_15.hex";
symlink "DCH/dc_ws_m1.hex", "hex/dc_ws_128_6.hex";

	######################   L2 CACHE   ###################################################
print "done!\nConverting L2 cache...";
mkdir "hex/L2_128K";
mkdir "hex/L2_256K";
mkdir "hex/L2_512K";
mkdir "hex/L2_64K";
mkdir "hex/L2_256K_1WAY";

$line=<LCH>;
$line=~/scache sets=(\d+) lines=(\d+)/;
$sc_ways=$1;	die "Unsupported number of scache ways declared ($sc_ways), closed" unless ($sc_ways==4 || $sc_ways==1);
$sc_lines=$2;	die "Unsupported number of scache lines declared ($sc_lines), closed" unless ($sc_lines =~ /(512|1024|2048|4096|8192)/);
#print "${sc_ways}way...";

$l2size=0;
$pos=tell(LCH);
$line=<LCH>;		# fetching first line to recognize scache format;
seek(LCH,$pos,0);
while (<LCH>) { $l2size++ if /\S/ };
seek(LCH,$pos,0);
die "Data format is inconsistent, closed" unless ( $sc_lines == $l2size );
my $sz = $l2size/8;

if ($line=~/^([\da-fA-F]+( [01]){3}( [\da-fA-F]{16}){4}\s+){4}([0123]{4})\s+/)	{	################# 4 WAY CASE
	die "Data format is inconsistent, closed" unless ( $sc_ways==4 );
	printf "${sc_ways}way, %dKB...",$sz;
	for ($i=0;$i<$l2size;$i++)  {
#	for ($i=0;$i<4096;$i++)  {		# make hex files (maybe zero filled) for up to 512KB L2 cache
		if ($i % 512 == 0) {	# new data and tag filenames
			open (SD1, sprintf("> hex/L2_%dK/l2_%d_dat_w1_m%d.hex", $sz, $sz, $i/512+1 )) or die "Cannot open SD1 file, closed";	# the next way 1 data file
			open (SD2, sprintf("> hex/L2_%dK/l2_%d_dat_w2_m%d.hex", $sz, $sz, $i/512+1 )) or die "Cannot open SD2 file, closed";	# the next way 2 data file
			open (SD3, sprintf("> hex/L2_%dK/l2_%d_dat_w3_m%d.hex", $sz, $sz, $i/512+1 )) or die "Cannot open SD3 file, closed";	# the next way 3 data file
			open (SD4, sprintf("> hex/L2_%dK/l2_%d_dat_w4_m%d.hex", $sz, $sz, $i/512+1 )) or die "Cannot open SD4 file, closed";	# the next way 4 data file
			open (ST1, sprintf("> hex/L2_%dK/l2_%d_tag_w1_m%d.hex", $sz, $sz, $i/512+1 )) or die "Cannot open ST1 file, closed";	 # the next way 1 tag file
			open (ST2, sprintf("> hex/L2_%dK/l2_%d_tag_w2_m%d.hex", $sz, $sz, $i/512+1 )) or die "Cannot open ST2 file, closed";	 # the next way 2 tag file
			open (ST3, sprintf("> hex/L2_%dK/l2_%d_tag_w3_m%d.hex", $sz, $sz, $i/512+1 )) or die "Cannot open ST3 file, closed";	 # the next way 3 tag file
			open (ST4, sprintf("> hex/L2_%dK/l2_%d_tag_w4_m%d.hex", $sz, $sz, $i/512+1 )) or die "Cannot open ST4 file, closed";	 # the next way 4 tag file
			open (SH1, sprintf("> hex/L2_%dK/l2_%d_dat_ham_m%d0.hex", $sz, $sz, $i/512+1 )) or die "Cannot open SH1 file, closed"; # the next data hamming file
			open (SH2, sprintf("> hex/L2_%dK/l2_%d_dat_ham_m%d1.hex", $sz, $sz, $i/512+1 )) or die "Cannot open SH2 file, closed"; # the next data hamming file
			open (SHT, sprintf("> hex/L2_%dK/l2_%d_tag_ham_m%d.hex", $sz, $sz, $i/512+1 )) or die "Cannot open SHT file, closed"; # the next tag hamming file
		}
		if ($i % 1024 == 0) {	# data files for v3.3 new hex format
			open (S3D1O, sprintf("> hex/l2_mem3_1%02d.hex", $i/512+1 )) or die "Cannot open S3D1O file, closed";  # the next way 1 data file
			open (S3D2O, sprintf("> hex/l2_mem3_2%02d.hex", $i/512+1 )) or die "Cannot open S3D2O file, closed";  # the next way 2 data file
			open (S3D3O, sprintf("> hex/l2_mem3_3%02d.hex", $i/512+1 )) or die "Cannot open S3D3O file, closed";  # the next way 3 data file
			open (S3D4O, sprintf("> hex/l2_mem3_4%02d.hex", $i/512+1 )) or die "Cannot open S3D4O file, closed";  # the next way 4 data file
			open (S3D1E, sprintf("> hex/l2_mem3_1%02d.hex", $i/512+2 )) or die "Cannot open S3D1E file, closed";  # the next way 1 data file
			open (S3D2E, sprintf("> hex/l2_mem3_2%02d.hex", $i/512+2 )) or die "Cannot open S3D2E file, closed";  # the next way 2 data file
			open (S3D3E, sprintf("> hex/l2_mem3_3%02d.hex", $i/512+2 )) or die "Cannot open S3D3E file, closed";  # the next way 3 data file
			open (S3D4E, sprintf("> hex/l2_mem3_4%02d.hex", $i/512+2 )) or die "Cannot open S3D4E file, closed";  # the next way 4 data file
		}
		if ($i % 2048 == 0) {	# new way select filename
			open (SWS, sprintf("> hex/L2_%dK/l2_%d_ws_m%d.hex", $sz, $sz, $i/2048+1 )) or die "Cannot open SWS file, closed";	# the next way select file
			$sws = "";
		}
		$_ = <LCH>;
#		$_ = ($i < $l2size) ?
#			<LCH> : 
#			"00000 0 0 0 0000000000000000 0000000000000000 0000000000000000 0000000000000000  " x 4 ."0123\n";	# zero string
		@_ = split;

		($t,$v,$w,$d00,$d01,$d02,$d03) = @_[ 0,1,3,4,5,6,7 ];
		my $tag0 = tagL2($t,$v,$w);
		my $ht0 = ham24_6(substr("0".$t, -6));
		print SD1 "$d00$d01\n$d02$d03\n";
		print S3D1O "$d00$d01\n";
		print S3D1E "$d02$d03\n";
		print ST1 "$tag0\n";

		($t,$v,$w,$d10,$d11,$d12,$d13) = @_[ 8,9,11,12,13,14,15 ];
		my $tag1 = tagL2($t,$v,$w);
		my $ht1 = ham24_6(substr("0".$t, -6));
		print SD2 "$d10$d11\n$d12$d13\n";
		print S3D2O "$d10$d11\n";
		print S3D2E "$d12$d13\n";
		print ST2 "$tag1\n";

		($t,$v,$w,$d20,$d21,$d22,$d23) = @_[ 16,17,19,20,21,22,23 ];
		my $tag2 = tagL2($t,$v,$w);
		my $ht2 = ham24_6(substr("0".$t, -6));
		print SD3 "$d20$d21\n$d22$d23\n";
		print S3D3O "$d20$d21\n";
		print S3D3E "$d22$d23\n";
		print ST3 "$tag2\n";

		($t,$v,$w,$d30,$d31,$d32,$d33) = @_[ 24,25,27,28,29,30,31 ];
		my $tag3 = tagL2($t,$v,$w);
		my $ht3 = ham24_6(substr("0".$t, -6));
		print SD4 "$d30$d31\n$d32$d33\n";
		print S3D4O "$d30$d31\n";
		print S3D4E "$d32$d33\n";
		print ST4 "$tag3\n";

		foreach (qw/ d00 d01 d02 d03 d10 d11 d12 d13 d20 d21 d22 d23 d30 d31 d32 d33 /)	{
			$$_ = ham64_8($$_);			# do hamming!
		}
#		print DMAH1 "$d00$d01\n$d02$d03\n";
#		print DMAH2 "$d10$d11\n$d12$d13\n";
#		print DMAH3 "$d20$d21\n$d22$d23\n";
#		print DMAH4 "$d30$d31\n$d32$d33\n";
		print SH1 $d10,$d11,$d00,$d01,"\n",$d12,$d13,$d02,$d03,"\n";
		print SH2 $d30,$d31,$d20,$d21,"\n",$d32,$d33,$d22,$d23,"\n";
		print SHT bin2hex($ht3.$ht2.$ht1.$ht0),"\n";

		$sws = substr(unpack ("B*", pack("H*", $ws_tab{$_[32]})),-6) . $sws;
		if (length($sws) == 24) {
			$sws = bin2hex($sws);
			print SWS "$sws\n";
			$sws = "";
		}
	}
	close SD1; close ST1; close SH1; # close DMAH1;
	close SD2; close ST2; close SH2; # close DMAH2;
	close SD3; close ST3; close SHT; # close DMAH3;
	close SD4; close ST4; close SWS; # close DMAH4;
	if ($null) { for my $s (64,128,256) { for (1..$s/64) {
		symlink "../L2_512K/l2_512_dat_ham_m${_}0.hex","hex/L2_${s}K/l2_${s}_dat_ham_m${_}0.hex";
		symlink "../L2_512K/l2_512_dat_ham_m${_}1.hex","hex/L2_${s}K/l2_${s}_dat_ham_m${_}1.hex";
		symlink "../L2_512K/l2_512_dat_w1_m${_}.hex","hex/L2_${s}K/l2_${s}_dat_w1_m${_}.hex";
		symlink "../L2_512K/l2_512_dat_w2_m${_}.hex","hex/L2_${s}K/l2_${s}_dat_w2_m${_}.hex";
		symlink "../L2_512K/l2_512_dat_w3_m${_}.hex","hex/L2_${s}K/l2_${s}_dat_w3_m${_}.hex";
		symlink "../L2_512K/l2_512_dat_w4_m${_}.hex","hex/L2_${s}K/l2_${s}_dat_w4_m${_}.hex";
		symlink "../L2_512K/l2_512_tag_ham_m${_}.hex","hex/L2_${s}K/l2_${s}_tag_ham_m${_}.hex";
		symlink "../L2_512K/l2_512_tag_w1_m${_}.hex","hex/L2_${s}K/l2_${s}_tag_w1_m${_}.hex";
		symlink "../L2_512K/l2_512_tag_w2_m${_}.hex","hex/L2_${s}K/l2_${s}_tag_w2_m${_}.hex";
		symlink "../L2_512K/l2_512_tag_w3_m${_}.hex","hex/L2_${s}K/l2_${s}_tag_w3_m${_}.hex";
		symlink "../L2_512K/l2_512_tag_w4_m${_}.hex","hex/L2_${s}K/l2_${s}_tag_w4_m${_}.hex";
		}
		system sprintf ("head -%d hex/L2_512K/l2_512_ws_m1.hex > hex/L2_${s}K/l2_${s}_ws_m1.hex",$s*2);
	} }
	for (1..$sz/64) {
		symlink "L2_${sz}K/l2_${sz}_dat_ham_m${_}0.hex", "hex/l2_data_H_1Kx32_0${_}0.hex";
		symlink "L2_${sz}K/l2_${sz}_dat_ham_m${_}1.hex", "hex/l2_data_H_1Kx32_0${_}1.hex";
		symlink "L2_${sz}K/l2_${sz}_dat_w1_m${_}.hex", "hex/l2_mem_10${_}.hex";
		symlink "L2_${sz}K/l2_${sz}_dat_w2_m${_}.hex", "hex/l2_mem_20${_}.hex";
		symlink "L2_${sz}K/l2_${sz}_dat_w3_m${_}.hex", "hex/l2_mem_30${_}.hex";
		symlink "L2_${sz}K/l2_${sz}_dat_w4_m${_}.hex", "hex/l2_mem_40${_}.hex";
		symlink "L2_${sz}K/l2_${sz}_tag_ham_m${_}.hex", "hex/l2_tag_H_512x24_0${_}.hex";
		symlink "L2_${sz}K/l2_${sz}_tag_w1_m${_}.hex", "hex/l2_tag_512x24_10${_}.hex";
		symlink "L2_${sz}K/l2_${sz}_tag_w2_m${_}.hex", "hex/l2_tag_512x24_20${_}.hex";
		symlink "L2_${sz}K/l2_${sz}_tag_w3_m${_}.hex", "hex/l2_tag_512x24_30${_}.hex";
		symlink "L2_${sz}K/l2_${sz}_tag_w4_m${_}.hex", "hex/l2_tag_512x24_40${_}.hex";
	}
		symlink "L2_${sz}K/l2_${sz}_ws_m${_}.hex", "hex/l2_ws_n${_}_512_24.hex" for (1..$sz/512+1);

} elsif ($line=~/^[\da-fA-F]+( [01]){3}( [\da-fA-F]{16}){4}\s+/)	{	############################### 1 WAY CASE
	die "Data format is inconsistent, closed" unless ( $sc_ways==1 );
	printf "${sc_ways}way, %dKB...",$l2size/32;
	my @h01 = ();	# let's put all hamming codes into the arrays, so we can fill hex files in any order;
	my @h23 = ();
	my @ht = (); $ht[$_] = "" foreach (0..2047);
#	for ($i=0;$i<$l2size;$i++)	{
	for ($i=0;$i<16384;$i++)	{	# for all hex files up to 512KB
		if ($i % 512 == 0) {	# new data filename
			open (SD, sprintf("> l2_mem_%d%02d.hex", $i/2048+1, ($i%2048)/512+1 )) or die "Cannot open SD file, closed ";	# the next data file
			open (ST4W, sprintf("> l2_tag_512x24_%d%02d.hex", $i/2048+1, ($i%2048)/512+1 )) or die "Cannot open ST4W file, closed ";	# the next data file
		}
		if ($i % 1024 == 0) {	# new tag filename
			open (ST, sprintf("> l2_tag_%d%d.hex", $i/2048+1, ($i%2048)/1024+1 )) or die "Cannot open ST file, closed ";	# the next tag file
		}
		$_ = ($i < $l2size) ?
			<LCH> : 
			"00000 0 0 0 0000000000000000 0000000000000000 0000000000000000 0000000000000000  0\n";	# zero string
		@_ = split;

		my ($t,$v,$w,$d0,$d1,$d2,$d3) = @_[ 0,1,3,4,5,6,7 ];
		my $tag = bin2hex(ham18_10(substr($t,-5)).$w.$v.$w.$v.substr(hex2bin(substr("0".$t,-6,2)),-2)).substr($t,-4);
		my $t4 = sprintf "%06x",(hex($t)<<2)+($i>>11);	# converting tag to 4-way compatible value;
		my $tag4w = tagL2($t4,$v,$w);
		print SD "$d0$d1\n$d2$d3\n";
		print ST "$tag\n";
		print ST4W "$tag4w\n";
		push @h01, ham64_8($d0).ham64_8($d1);
		push @h23, ham64_8($d2).ham64_8($d3);
		$ht[$i%2048] = ham24_6($t4) . $ht[$i%2048];
	}
	close SD;
	close ST;
	close ST4W;

	open (SH1, "> l2_ham_1.hex") or die "Cannot open SH1 file, closed"; # the next data hamming file
	open (SH2, "> l2_ham_2.hex") or die "Cannot open SH2 file, closed"; # the next data hamming file
	open (SH3, "> l2_ham_3.hex") or die "Cannot open SH3 file, closed"; # the next data hamming file
	open (SH4, "> l2_ham_4.hex") or die "Cannot open SH4 file, closed"; # the next data hamming file
	open (SH10,"> l2_data_H_1Kx32_010.hex") or die "Cannot open SH10 file, closed"; # the next data hamming file
	open (SH11,"> l2_data_H_1Kx32_011.hex") or die "Cannot open SH11 file, closed"; # the next data hamming file
	open (SH20,"> l2_data_H_1Kx32_020.hex") or die "Cannot open SH10 file, closed"; # the next data hamming file
	open (SH21,"> l2_data_H_1Kx32_021.hex") or die "Cannot open SH11 file, closed"; # the next data hamming file
	open (SH30,"> l2_data_H_1Kx32_030.hex") or die "Cannot open SH10 file, closed"; # the next data hamming file
	open (SH31,"> l2_data_H_1Kx32_031.hex") or die "Cannot open SH11 file, closed"; # the next data hamming file
	open (SH40,"> l2_data_H_1Kx32_040.hex") or die "Cannot open SH10 file, closed"; # the next data hamming file
	open (SH41,"> l2_data_H_1Kx32_041.hex") or die "Cannot open SH11 file, closed"; # the next data hamming file
	open (SHT1,"> l2_tag_H_512x24_01.hex") or die "Cannot open SHT1 file, closed"; # the next tag hamming file
	open (SHT2,"> l2_tag_H_512x24_02.hex") or die "Cannot open SHT2 file, closed"; # the next tag hamming file
	open (SHT3,"> l2_tag_H_512x24_03.hex") or die "Cannot open SHT3 file, closed"; # the next tag hamming file
	open (SHT4,"> l2_tag_H_512x24_04.hex") or die "Cannot open SHT4 file, closed"; # the next tag hamming file
	open (SWS, "> l2_ws_n1_512_24.hex") or die "Cannot open SWS file, closed";	# the next way select file
	for $i (0..511)	{
		print SH1 $h01[6*512+$i],$h01[4*512+$i],$h01[2*512+$i],$h01[$i],"\n";
		print SH1 $h23[6*512+$i],$h23[4*512+$i],$h23[2*512+$i],$h23[$i],"\n";
		print SH2 $h01[7*512+$i],$h01[5*512+$i],$h01[3*512+$i],$h01[1*512+$i],"\n";
		print SH2 $h23[7*512+$i],$h23[5*512+$i],$h23[3*512+$i],$h23[1*512+$i],"\n";
		print SH3 $h01[14*512+$i],$h01[12*512+$i],$h01[10*512+$i],$h01[8*512+$i],"\n";
		print SH3 $h23[14*512+$i],$h23[12*512+$i],$h23[10*512+$i],$h23[8*512+$i],"\n";
		print SH4 $h01[15*512+$i],$h01[13*512+$i],$h01[11*512+$i],$h01[9*512+$i],"\n";
		print SH4 $h23[15*512+$i],$h23[13*512+$i],$h23[11*512+$i],$h23[9*512+$i],"\n";

		print SH10 $h01[1*2048+$i],$h01[0*2048+$i],"\n",$h23[1*2048+$i],$h23[0*2048+$i],"\n";	# print SH1 $d10,$d11,$d00,$d01,"\n",$d12,$d13,$d02,$d03,"\n";
		print SH11 $h01[3*2048+$i],$h01[2*2048+$i],"\n",$h23[3*2048+$i],$h23[2*2048+$i],"\n";	# print SH2 $d30,$d31,$d20,$d21,"\n",$d32,$d33,$d22,$d23,"\n";
		print SH20 $h01[1*2048+1*512+$i],$h01[0*2048+1*512+$i],"\n",$h23[1*2048+1*512+$i],$h23[0*2048+1*512+$i],"\n";
		print SH21 $h01[3*2048+1*512+$i],$h01[2*2048+1*512+$i],"\n",$h23[3*2048+1*512+$i],$h23[2*2048+1*512+$i],"\n";
		print SH30 $h01[1*2048+2*512+$i],$h01[0*2048+2*512+$i],"\n",$h23[1*2048+2*512+$i],$h23[0*2048+2*512+$i],"\n";
		print SH31 $h01[3*2048+2*512+$i],$h01[2*2048+2*512+$i],"\n",$h23[3*2048+2*512+$i],$h23[2*2048+2*512+$i],"\n";
		print SH40 $h01[1*2048+3*512+$i],$h01[0*2048+3*512+$i],"\n",$h23[1*2048+3*512+$i],$h23[0*2048+3*512+$i],"\n";
		print SH41 $h01[3*2048+3*512+$i],$h01[2*2048+3*512+$i],"\n",$h23[3*2048+3*512+$i],$h23[2*2048+3*512+$i],"\n";

		print SHT1 bin2hex($ht[$i+0*512]),"\n";
		print SHT2 bin2hex($ht[$i+1*512]),"\n";
		print SHT3 bin2hex($ht[$i+2*512]),"\n";
		print SHT4 bin2hex($ht[$i+3*512]),"\n";
		
		print SWS "000000\n";
	}
	close SH1; close SH10; close SH11; close SHT1;
	close SH2; close SH20; close SH21; close SHT2;
	close SH3; close SH30; close SH31; close SHT3;
	close SH4; close SH40; close SH41; close SHT4;
	close SWS;

} else {
	die "Can't recognize scache format";
}

print "done!\n";
close LCH;
}

##########################   CP2MEMFILE   ############################################################

if ($cp2memfile)	{
open (LCH, "$cp2memfile") or die "Can't open file '$cp2memfile', closed";
print "Converting cp2mem...";

$line=<LCH>;
$line=~/cp2memory (\d+) dwords/;
$cp2_dwords=$1;	die "Unsupported cp2 memory size ($cp2_dwords dwords), closed" unless ($cp2_dwords == 32768);

	for ($i=0;$i<$cp2_dwords/4;$i++)  {
		if ($i % 512 == 0) {	# new data filename
			open (CP2D, sprintf("> l2_mem_%d%02d.hex", $i/2048+1, ($i%2048)/512+1 )) or die "Cannot open CP2D file, closed ";	# the next data file
			open (CP2H, sprintf("> dma_h_mem%d.hex", $i/512+1 )) or die "Cannot open CP2H file, closed ";	# the next cp2mem hamming file
		}
		$d0 = <LCH>; $d1 = <LCH>; $d2 = <LCH>; $d3 = <LCH>;
		chomp ( $d0, $d1, $d2, $d3 );
		print CP2D "$d0$d1\n$d2$d3\n";
		print CP2H ham64_8($d0),ham64_8($d1),"\n",ham64_8($d2),ham64_8($d3),"\n";
	}
close CP2D;
close CP2H;
print "done!\n";
close LCH;
}

unlink $cachefile if $null;
exit 0;

##########################   SUBROUTINES   ###########################################################




sub hex2bin	{
	return unpack ("B*", pack("H*", shift));
}

sub bin2hex	{
	return unpack ("H*", pack("B*", shift));
}

sub add_pb_ich	# takes   16-digit hexadecimal string of data;
{				# returns 17-digit string (prolonged by two pairs of parity bits); fake by now;
	my ($a1,$a2) = ( $_[0] =~ /(.{8})(.{8})/ ) ;
#	my $b = sprintf ("%09x%08x",hex($a1)<<2,hex($a2));
	my $b = sprintf ("%s%08x",unpack(H9,pack("B*","00".unpack(B32,pack(H8,$a1))."00")),hex($a2));		# workaround for 32-bit hosts

	return $b;
#	my $d1=hex2bin($a1);
#	my $d2=hex2bin($a2);
#	my $d="000000${d1}00${d2}";		# exactly 8 zeroes longer, for correct pack execution in the next bin2hex
#	return substr("000000000".&bin2hex($d),-17);	# returns 17-character string (prolonged by two pairs of parity bits)
}

sub pb {		#  returns parity bit for the given hex string;
	return unpack("%1B*",pack("H*",shift));
}

sub par_64_8	# takes   16-digit hexadecimal string of data;
{				# returns 2-digit string of parity bits;
	my $b = "";
	my @a = ( $_[0] =~ /(..)(..)(..)(..)(..)(..)(..)(..)/) ;
	foreach (@a) {
 		$b .= pb($_);
	}
	return bin2hex($b);
}

sub expand_ic	# takes icache line (in either 4 or 8 way format);
{				# returns unified list of values (for both formats);
	my @cl=split (" ", $_[0]);
	if ( $ic_ways == 4 ) {
		$cl[64] = sprintf ("%06x",oct scalar reverse "4567".$cl[32] );
		$cl[65] = $ws_tab{$cl[32]};
		$cl[32] = $cl[40] = $cl[48] = $cl[56] = "000000";
		$cl[33] = $cl[41] = $cl[49] = $cl[57] = "0";
		$cl[34] = $cl[42] = $cl[50] = $cl[58] = "0";
		$cl[35] = $cl[43] = $cl[51] = $cl[59] = "0";
		$cl[36] = $cl[44] = $cl[52] = $cl[60] = "0000000000000000";
		$cl[37] = $cl[45] = $cl[53] = $cl[61] = "0000000000000000";
		$cl[38] = $cl[46] = $cl[54] = $cl[62] = "0000000000000000";
		$cl[39] = $cl[47] = $cl[55] = $cl[63] = "0000000000000000";
	} elsif ( $ic_ways == 8 ) {
		($cl[65] = $cl[64]) =~ s/[4567]//g;
		$cl[65] = $ws_tab{$cl[65]};
		$cl[64] = sprintf ("%06x",oct scalar reverse $cl[64] );
	}
	return @cl;
}

sub tagL2		#
{				#
	my ($t,$v,$w) = @_[ 0,1,2 ];
	my $taglen = ( $sc_ways==1 ) ? -20 : $taglen{$l2size};		# in the 1-way case creates additional 4-way tags;
	return bin2hex (substr ("000".$w.$v.$w.$v.substr (unpack ("B*", pack("H*", substr("0".$t, -6))), $taglen), -24));
}

sub ham18_10	# takes 5-digit hexadecimal string of data (20 bits);
{				# returns 10-digit binary string of hamming code;
	my $data = shift;
	if ( $data eq "00000" ) {
		return "0000000000";
	} else {
	my $data = pack('H5',$data);
	return	unpack("%1B*",$data & $h18c9) . # hamming bit 9
			unpack("%1B*",$data & $h18c8) .
			unpack("%1B*",$data & $h18c7) .
			unpack("%1B*",$data & $h18c6) .
			unpack("%1B*",$data & $h18c5) .
			unpack("%1B*",$data & $h18c4) .
			unpack("%1B*",$data & $h18c3) .
			unpack("%1B*",$data & $h18c2) .
			unpack("%1B*",$data & $h18c1) .
			unpack("%1B*",$data & $h18c0) ; # hamming bit 0
	}
}

sub ham24_6		# takes 6-digit hexadecimal string of data (24 bits);
{				# returns 6-digit binary string of hamming code;
	my $data = shift;
	if ( $data eq "000000" ) {
		return "000000";
	} else {
	my $data = pack('H6',$data);
	return	unpack("%1B*",$data & $h24c5) . # hamming bit 5
			unpack("%1B*",$data & $h24c4) .
			unpack("%1B*",$data & $h24c3) .
			unpack("%1B*",$data & $h24c2) .
			unpack("%1B*",$data & $h24c1) .
			unpack("%1B*",$data & $h24c0) ; # hamming bit 0
	}
}

sub ham64_8		# takes  16-digit hexadecimal string of data,
{				# returns 2-digit hexadecimal string of hamming code;
	my $data = shift;
	if ( $data eq "0000000000000000" ) {
		return "00";
	} else {
	$data = pack('H16',$data);
#	let's bitwise-AND data with mask, then count parity bit, then glue parity bits together;
	my $h =	unpack("%1B*",$data & $h64c7) . # hamming bit 7
			unpack("%1B*",$data & $h64c6) .
			unpack("%1B*",$data & $h64c5) .
			unpack("%1B*",$data & $h64c4) .
			unpack("%1B*",$data & $h64c3) .
			unpack("%1B*",$data & $h64c2) .
			unpack("%1B*",$data & $h64c1) .
			unpack("%1B*",$data & $h64c0) ; # hamming bit 0
	return unpack ("H*", pack("B*", $h));
	}
}
