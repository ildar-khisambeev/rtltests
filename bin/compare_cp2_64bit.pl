#!/usr/bin/perl

# file: compare_cp2.pl,  v3.31tmp
# date: 2012-01-11 /v3.31tmp/
# by:   Chibisov Peter, chibisov@cs.niisi.ras.ru
# aim:  to compare logs with cp2 register dump from vmips64 and from RTL-model;
# run:  try  ./compare_cp2.pl [--save-temps]

# ------------------------------------------------------------------------------- | get options | ------------------

use Getopt::Long;
GetOptions ("save-temps!" => \$save_tmp); #savetemps flags - have format --save-temps or (-nosave-temps or nothing)

$save_tmp=0 unless defined $save_tmp; #no save temps file, if not enable
$f=2;	# result of compare: added in version 3.30 instead of special mini-file

# ------------------------------------------------------------------------------- | compare section |---------------

open(file_uns,"log2_cp2_uns.txt") or die "Cannot open log2_cp2_uns.txt!";
open(file_sort,"> log2_cp2.txt")  or die "Cannot open log2_cp2.txt!";
while(<file_uns>) { push(@sorted,$_); } # copy file to array
@sorted=sort {(split /[ \t]+/, $a)[1] cmp (split /[ \t]+/, $b)[1]} @sorted;	# sort this array, get the right order of instructions
foreach $a (@sorted)	{
	$a=~m/\d{1,8}\s+(c.{1,})/;	# $1 - second column
	print file_sort $1,"\n";
}
close(file_uns);
close(file_sort);


open(file2,"log2_cp2.txt") or die "Cannot open log2_cp2.txt!";
open(file1,"log1_cp2.txt") or die "Cannot open log1_cp2.txt!";
open(PRNTR,"> out_cp2.txt") or die "Something wrong with out_cp2.txt file!";

$advanced=1;						# "advanced" means ability to compare FCSR values
$counter=0;						# line counter in log1_cp2.txt
print "\n";
print "Cp2 registers compared:\n";
print PRNTR "\n";
print PRNTR "Cp2 registers compared:\n";
$match=1;
$line1=" "; $line2=" ";					# to start the following while correctly 
while(($match eq 1) & ($line1 ne "") & ($line2 ne ""))	# search until mismarch or the end of log files
	{
	  $nul="   "; $nul=~m/(.)(.)(.)/;		# destroy the previous values of $1,$2,$3
	  $line1=<file1>;
	  $counter=$counter+1;
	  $line2=<file2>;
	  $_=$line2;
	  if(/([\d]{2})=([\da-fA-F]{16,32})\s+CMCSR=([\da-fA-F]{8})/) 	# select needed part - not to depend of "\n" symbol
	    {
	    	$advanced=1;
		$tmp1=$1; $tmp2=$2; $tmp3=$3;				# $1 - sel field; $2 -reg, $3 - its value, $4 - current CCSR value
		$l2_true=sprintf("c%s=%s  CCSR=%s",$1,$2,$3);	# new format
	    } 
	  else 
	    {
		if(/([\d]{2})=([\da-fA-F]{16,32})/) 	# select needed part - not to depend of "\n" symbol
		  {
		     $advanced=0;					# no CCSR value found /old format/
		     $tmp1=$1; $tmp2=$2; $tmp3=$3;			# $1 - sel field; $2 -reg, $3 - its value
		     $l2_true=sprintf("c%s=%s",$1,$2); 
		  }
	    }
	  $_=$line1;
	  if ($advanced eq 0)
	  {
	     if	 (/(\d{1,7})\s+PC=0x([\da-fA-F]{16})\s+([\da-fA-F]{8})\s+c\[(\d{2})\]=([\da-fA-F]{16,32})/)			# old format
	       {
	       	 # now: $1=instr. number, $2=addr., $3=instr.opcode, $4=regfile sel, $5=reg.num., $6= reg.value;
		 $reg_val=sprintf("c%s=%s",$4,$5); 
		 if ($reg_val ne $l2_true)
		 	{ 
			 print "mismatch found at instruction ",$1; 
			 $str_num=$1;
			 print " (see file log1_cp2.txt, line ",$counter,")\n";
			 print "\t",$reg_val," (vmips 64)\n\t",$l2_true," (sim_mips)\n";
			 print PRNTR "mismatch found at instruction ",$1;
			 print PRNTR " (see file log1_cp2.txt, line ",$counter,")\n";
			 print PRNTR "\t",$reg_val," (vmips 64)\n\t",$l2_true," (sim_mips)\n";
			 $match=0;
#			 system "echo 1 > cp2";  # special file "cp2" for autorun scripts;
			 $f=1;
			 $_=$line2;
			 if (/[xX]/)
			    {  
				print "\nWarning! File \"log2_cp2.txt\" contains \"x\"-values at instruction ",$str_num,"!\n"; 
				print PRNTR "\nWarning! File \"log2_cp2.txt\" contains \"x\"-values at instruction ",$str_num,"!\n"; 
			    }
			 elsif (($line2 eq "") | ($tmp1 eq " ") | ($tmp2 eq " "))
			    { 
				print "\nWarning! File \"log2_cp2.txt\" contains less instructions then \"log1_cp2.txt\"!\n";
				print PRNTR "\nWarning! File \"log2_cp2.txt\" contains less instructions then \"log1_cp2.txt\"!\n"; 
		     	    } 
			}
		 $i=$1;			# backup the number of instructions proceeded
			 
	       }    
	    } 
	    else
	    {   
	      if  (/(\d{1,7})\s+PC=0x([\da-fA-F]{16})\s+([\da-fA-F]{8})\s+c\[(\d{2})\]=([\da-fA-F]{16,32})\s+CMCSR=([\da-fA-F]{8})/)	# new format
	       {
	       	 # now: $1=instr. number, $2=addr., $3=instr.opcode, $4=regfile sel, $5=reg.num., $6= reg.value, $7=CCSR value;
		 $i=$1;			# backup the number of instructions proceeded
		 $reg_val=sprintf("c%s=%s  CCSR=%s",$4,$5,$6); 
		 if ($reg_val ne $l2_true)
		 	{ 
			 print "mismatch found at instruction ",$1;
			 $str_num=$1;
			 print " (see file log1_cp2.txt, line ",$counter,")\n";
			 print "\t",$reg_val," (vmips 64)\n\t",$l2_true," (sim_mips)\n";
			 print PRNTR "mismatch found at instruction ",$1;
			 print PRNTR " (see file log1_cp2.txt, line ",$counter,")\n";
			 print PRNTR "\t",$reg_val," (vmips 64)\n\t",$l2_true," (sim_mips)\n";
			 $match=0;
#			 system "echo 1 > cp2";  # special file "cp2" for autorun scripts;
			 $f=1;
			 $_=$line2;
			 if (/[xX]/)
			    { 
				print "\nWarning! File \"log2_cp2.txt\" contains \"x\"-values at instruction ",$str_num,"!\n"; 
				print PRNTR "\nWarning! File \"log2_cp2.txt\" contains \"x\"-values at instruction ",$str_num,"!\n";  
			    }
			 elsif (($line2 eq "") | ($tmp1 eq " ") | ($tmp2 eq " "))
			    { 
				print "\nWarning! File \"log2_cp2.txt\" contains less instructions then \"log1_cp2.txt\"!\n";
				print PRNTR "\nWarning! File \"log2_cp2.txt\" contains less instructions then \"log1_cp2.txt\"!\n"; 
		     	    } 
			}
		 $i=$1;			# backup the number of instructions proceeded
			 
	       } 
	      }     
	      
	}

if ($match eq 1) 
	{ 
	  print "Great! No mismatch found! "; printf("%d",$i); print " instructions are successfully proceeded!\n\n";
	  print PRNTR "Great! No mismatch found! "; printf PRNTR ("%d",$i); print PRNTR " instructions are successfully proceeded!\n\n";
#	  system "echo 0 > cp2";		# special file "cp2" for autorun scripts;
	  $f=0;
	}

#if ($advanced eq 0) {print "Warning! File \"log2_cp2.txt\" contains no C1_SR values!\n"; print PRNTR "Warning! File \"log2_cp2.txt\" contains no C1_SR values!\n"; }

print PRNTR "\n";

close(file2);
close(file1);
close(PRNTR);

$i=0;
#$i=unlink ("log2_cp2.txt") unless $save_tmp;
#print "Temp files was deleted!\n" if $i==1;
exit ($f);
