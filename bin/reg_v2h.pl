#!/usr/bin/perl -w
use strict;

# aim:		convert vmips initstate file to RTL hex files to restore data
# version:	1.2, 2015-02-19
# author:	Ildar Khisambeev <ildar@cs.niisi.ras.ru>
# run:		./reg_v2h.pl <dumpfile>

#version history
#1.0, 2013-07-23	- release; restore TLB data only; create files RAM_64x59_jtlb_answ.hex and RAM_64x46_jtlb_acc.hex;
#1.1, 2013-09-25	- restore 4 hex files: alu.hex, fpu.hex, cp0.hex and tlb.hex
#1.2, 2015-02-19	- restore cpv.hex

$|=1;   # forces a buffer flush after every write or print;

my $file;

if ( not defined $ARGV[0])	{
	print "No input file. ";
	if (-f "dump_0001reg")	{
		print "Trying file 'dump_0001reg'.";
		$file = "dump_0001reg";
	} elsif (-f "vmips_initstate")	{
		print "Trying file 'vmips_initstate'.";
		$file = "vmips_initstate";
	} else {
		print "Exit.\n";
		exit -1;
	}
	print "\n";
} else {
	$file = $ARGV[0];
}

open (REG, "$file") or die "Can't open file '$file', closed";

my @cmgr = ();
my $cmcr31;
my @gpr = ();
my ($hi,$lo,$pc);
my @fpr = ();
my ($fir,$fcsr);
my @c00 = ();
my @c01 = ();
my @c02 = ();
my @c03 = ();
my @tlb = ();
while (<REG>) {
	if (/^\s*r(\d{2})=0x([\da-fA-F]{16})/) { $gpr[$1] = $2; next; }
	if (/^\s*pc=0x([\da-fA-F]{16})/) { $pc = $1; next; }
	if (/^\s*hi=0x([\da-fA-F]{16})/) { $hi = $1; next; }
	if (/^\s*lo=0x([\da-fA-F]{16})/) { $lo = $1; next; }
	if (/^\s*cr(\d{2})=0x([\da-fA-F]{16})/) { $c00[$1] = $2; next; }
	if (/^\s*ecr(\d{2})=0x([\da-fA-F]{16})/) { $c01[$1] = $2; next; }
	if (/^\s*e2cr(\d{2})=0x([\da-fA-F]{16})/) { $c02[$1] = $2; next; }
	if (/^\s*e3cr(\d{2})=0x([\da-fA-F]{16})/) { $c03[$1] = $2; next; }
	if (/^\s*tlb(\d{2})=0x([\da-fA-F]{16}) 0x([\da-fA-F]{16}) 0x([\da-fA-F]{16}) 0x([\da-fA-F]{16}) 0x0{15}([01])/)
		{ $tlb[$1] = "$2 $3 $4 $5 $6"; next; }
	if (/^\s*f(\d{2})=0x([\da-fA-F]{16})/) { $fpr[$1] = $2; next; }
	if (/^\s*fcr00=0x([\da-fA-F]{16})/) { $fir = $1; next; }
	if (/^\s*fcr31=0x([\da-fA-F]{16})/) { $fcsr = $1; next; }
	if (/^\s*cmgr(\d{2})=0x([\da-fA-F]{32})/) { $cmgr[$1] = $2; next; }
	if (/^\s*cmcr31=0x([\da-fA-F]{8})/) { $cmcr31 = $1; next; }
}



print "Converting ALU...";
open (ALU, "> alu.hex")  or die "Cannot open alu.hex for write, closed";
for (0..31) {
	not defined $gpr[$_] and die "gpr $_ not found" or print ALU $gpr[$_],"\n";
}
not defined $hi and die "HI not found" or print ALU $hi,"\n";
not defined $lo and die "LO not found" or print ALU $lo,"\n";
not defined $pc and die "PC not found" or print ALU $pc,"\n";
close ALU;
print "done!\n";

print "Converting FPU...";
open (FPU, "> fpu.hex")  or die "Cannot open fpu.hex for write, closed";
for (0..31) {
	not defined $fpr[$_] and die "fpr $_ not found" or print FPU $fpr[$_],"\n";
}
not defined $fir and die "FIR not found" or print FPU $fir,"\n";
not defined $fcsr and die "FCSR not found" or print FPU $fcsr,"\n";
close FPU;
print "done!\n";

print "Converting CPV...";
open (CPV, "> cpv.hex")  or die "Cannot open cpv.hex for write, closed";
for (0..63) {
	not defined $cmgr[$_] and die "cpv reg $_ not found" or print CPV $cmgr[$_],"\n";
}
not defined $cmcr31 and die "CPV ctrl reg not found" or print CPV "0"x24,$cmcr31,"\n";
close CPV;
print "done!\n";

print "Converting CP0...";
open (CP0, "> cp0.hex")  or die "Cannot open cp0.hex for write, closed";
for (0..31) {
	my $c0 = '';
	not defined $c00[$_] and die "cp0 sel 0 reg $_ not found" or $c0 .= $c00[$_]." ";
	not defined $c01[$_] and die "cp0 sel 1 reg $_ not found" or $c0 .= $c01[$_]." ";
	not defined $c02[$_] and die "cp0 sel 2 reg $_ not found" or $c0 .= $c02[$_]." ";
	not defined $c03[$_] and die "cp0 sel 3 reg $_ not found" or $c0 .= $c03[$_];
	print CP0 $c0,"\n";
}
close CP0;
print "done!\n";

print "Converting TLB...";
open (TLB, "> tlb.hex")  or die "Cannot open tlb.hex for write, closed";
for (0..63) {
	not defined $tlb[$_] and die "tlb entry $_ not found" or print TLB $tlb[$_],"\n";
}
close TLB;
print "done!\n";

close REG;
exit 0;
