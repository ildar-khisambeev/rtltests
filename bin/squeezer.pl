#!/usr/bin/perl

# file: squeezer.pl, v2.14
# date: /2015-02-18/
# by:   chibisov@cs.niisi.ras.ru, ildar@cs.niisi.ras.ru
# aim:  to look through log with all data from vmips64 and to keep all neccessary info down to registers in separate files;
# run:  try (just an example): ./squeezer.pl

# version 2.2i: log1_addr.txt output added;
# version 2.3: log1_cp2.txt output added;
# version 2.4: log1_ic.txt output added;
# version 2.5: log1_l2_dsp.txt  output added;
# version 2.6: fixed inaccurate regexp, that allowed icache log entries to get into L2 cache log;
# version 2.7: regexps for L2 cache log specified to omit 'dumpcacheinstr' info;
# version 2.8tmp: temporary version for new vmips logs format;
# version 2.9tmp: icache log;
# version 2.10tmp: disk log with convert to hex;
# version 2.11tmp: disk log with convert to hex (2 sets with & w/o The Dog);
# version 2.12tmp: removing 'disk' entries from cache log;
# version 2.13tmp: regexps for cache log specified to omit 'convert' info;
# version 2.14: CPV log added (instead of CP2); 

$instr_number=0;
$instr_address="0000000000000000";
$instr="00000000";
my $diskacc_inum=0;
my $disk_count=-1;


open(ALL,"log1a.txt") or die "Cannot open log1a.txt, closed";
# Create output files
open(CMD,"> log1.txt")     or die "Something wrong with log1.txt file, closed";
open(GPR,"> log1_gpr.txt") or die "Something wrong with log1_gpr.txt file, closed";
open(FPR,"> log1_fpr.txt") or die "Something wrong with log1_fpr.txt file, closed";
open(CCH,"> log1_cache.txt") or die "Something wrong with log1_cache.txt file, closed";
open(MWR,"> log1_mem_wr.txt") or die "Something wrong with log1_mem_wr.txt file, closed";
open(EXC,"> log1_exc.txt") or die "Something wrong with log1_exc.txt file, closed";
open(DSK,"> log1_disk.txt") or die "Something wrong with log1_disk.txt file, closed";
open(ADR,"> log1_addr.txt") or die "Something wrong with log1_addr.txt file, closed";
open(CP2,"> log1_cp2.txt") or die "Something wrong with log1_cp2.txt file, closed";
open(ICC,"> log1_ic.txt") or die "Something wrong with log1_ic.txt file, closed";
open(DMA,"> log1_l2_dsp.txt") or die "Something wrong with log1_l2_dsp.txt file, closed";
open(ICH,"> log1_icache.txt") or die "Something wrong with log1_icache.txt file, closed";
open DSKINS, "> disk_instr.hex";


while(<ALL>) {
	if (/PC=0x([\da-fA-F]{16}).{20}([\da-fA-F]{8})(.*$)/) {		# instruction log line
		$instr_number=$instr_number+1;
		$instr_address=$1;
		$instr=$2;
		print CMD $_;
		print ADR $_;
	}
	if (/Reg write (\w{2})=([\da-fA-F]{16})/) {			#  ALU register writes log line
		print GPR $instr_number,"\tPC=0x",$instr_address,"    ",$instr,"\t",$1,"=",$2,"\n" unless ($1 eq "r0");
	}
	if (/Reg write f.(\d{1,2}).=([\da-fA-F]{16})..FCSR.fcr31.=([\da-fA-F]{8})/) {	# FPU register writes log line
		print  FPR $instr_number,"\tPC=0x",$instr_address,"    ",$instr,"\tfr";
		printf FPR "%02d", $1;
		print  FPR "=",$2;
		print FPR "  C1_SR=",$3,"\n";
	} elsif (/Reg write f.(\d{1,2}).=([\da-fA-F]{16})/) {	# for downward compatibility with v1.2
		print  FPR $instr_number,"\tPC=0x",$instr_address,"    ",$instr,"\tfr";
		printf FPR "%02d", $1;
		print  FPR "=",$2,"\n";
	}
	if (/DPA=/) {				# icache operation log line
	    print ICC $_;
	}	 
	if (/^(?:\d+\s+)?\bdcache/ and not /disk/) {	# dcache log line
		print CCH $_;
	}
	if (/^(?:\d+\s+)?\bscache/and not /disk/) {		# L2 cache log line
		print CCH $_;
	}
	if (/^(?:\d+\s+)?\bicache/) {		# icache log line
		print ICH $_;
	}
	if (/dmemacc:.store/ and not /disk/ and not /L2/ and not /dma/ and not /CP2/) {		# writings to memory log line
		print MWR $_;
	}
	if (/Exception/)	{		# exception log line
		print EXC $_;
	}
	if (/^(\d+)\s+dmemacc: store\s+\d+\s+addr=([\da-fA-F]{9})\s+data=([\da-fA-F]{16})\s+mask=[01]{8}\s+disk/) {			# disk log line
		print DSK $_;
		if ($1 != $diskacc_inum) {	# new disk access
			next if ( $disk_count > 1023);
			$diskacc_inum = $1;
			$disk_count++;
			printf DSKINS "%08x\n", $diskacc_inum;
			$name = sprintf "disk%04d.hex",$disk_count;
			$name2 = sprintf "diskd%04d.hex",$disk_count;
			open DSKDAT, "> $name" or die "filename is \' $name \', WHY???!!!";
			open DSKDAT2, "> $name2" or die "filename is \' $name \', WHY???!!!";
			printf DSKDAT "\@%016s\n",$2;
			printf DSKDAT2 "%016s\n",$2;
		}
		print DSKDAT $3,"\n";
		print DSKDAT2 $3,"\n";
	}
	if (/\[va=/) {				# l/s addresses log line
		print ADR $_;
	}
#	if (/Reg write s.([01]).\s+c.(\d\d).=([\da-fA-F]{16})\s+CMCSR\(cmcr31\)=([\da-fA-F]{8})/) {	# CP2 register writes log line
#		print  CP2 $instr_number,"\tPC=0x",$instr_address,"    ",$instr,"\ts[",$1,"] c[";
#		printf CP2 "%02d", $2;
#		print  CP2 "]=",$3;
#		print CP2 "  CMCSR=",$4,"\n";
	if (/Reg write cmgr.(\d\d).=([\da-fA-F]{32})\s+CMCSR\(cmcr31\)=([\da-fA-F]{8})/) {	# CP2 register writes log line
	# Reg write cmgr[02]=be100bafffcfab4d3e0d1a4292e7f7f2 CMCSR(cmcr31)=00000000
		print  CP2 $instr_number,"\tPC=0x",$instr_address,"    ",$instr,"\tc[";
		printf CP2 "%02d", $1;
		print  CP2 "]=",$2;
		print CP2 "  CMCSR=",$3,"\n";

	}
	if (/(l2adr|memadr)/) {			# DMA transactions log line
		print DMA $_;
	}
}
while ($disk_count < 1023) {
print DSKINS "ffffffff\n";
$disk_count++;
}

#Close'em all
close ALL;
close CMD;
close GPR;
close FPR;
close CCH;
close MWR;
close EXC;
close DSK;
close ADR;
close CP2;
close ICC;
close DMA;
close ICH;
close DSKINS;
close DSKDAT;
close DSKDAT2;

exit 0;
