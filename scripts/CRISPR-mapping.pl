#!/usr/bin/perl
use strict;
use warnings;

#vars

my $decision;
my $comparebowtie;
my $readfastq;
my $filename;
my $pattern;
my $inputline;
my $fasta;
my $fastqout;
my $count;
my $targetid;
my $patternlength;
my $matchpattern;

my $target;
my %reads;

my @matchstring=();
my @matches=();
my $matchalign;



my $targetdesigns;
my $samlibrary;
my $samgenome;
my $seqdesign;
my $seqgene;
my $match;
my $lastinput;


my @libinputline=();

my %libID;
my @geneid;
my %stats;
my %totalreads;
my @blastline=();

my $sequenceline;

my @fastq=();




#######
#	Second part
#	Reading SAM file after exported fastq file was mapped to the genome
#	Reading SAM file after mapping to reference library to get to know which design is what
#	extraction of:
#	Mismatches/matches
#	Mapped gene name
#	mapped Designs to the gene name

# First:
#	Extract data from each SAM file
# Second:
#	Compare by the information of the read id, which mapped design of the library mapped to what gene in the genome the best
# Third:
#	Combine the output as before using the design ID, gene symbol (mapped by genome) and mapped by the library refence




# Open files
#	FASTA Library as reference
$filename = $ARGV[0];

open ($targetdesigns, "<", $filename) or die "cannot open library reference";

print "Initialising Library Reference\n";

# go through both target list and blastoutput to parse it for matching sequences or slight /hard mismatches
	while ($inputline = <$targetdesigns>){
		if ($inputline=~/^>(.+)$/)	# get the design ID and initialize the hash
		{
			$targetid = $1;
			$libID{$targetid}{"match"} = 0;	# perfect match
			$libID{$targetid}{"total"} = 0;	# total reads for a given design
			$libID{$targetid}{"sequence"} = "";

			@geneid = split("_", $targetid);
			$reads{$geneid[0]}{"genematch"} = 0;
			$reads{$geneid[0]}{"genetotal"} = 0;

			# for counting the target design present per gene
			$reads{$geneid[0]}{$targetid} = 0;	#only perfect matches
			$reads{$geneid[0]}{"targettotal"} = 0;	# only perfect matches
			$reads{$geneid[0]}{"targetmatched"} = 0;
			$reads{$geneid[0]}{"targetnone"} = 0;
			
		}				
	}

close($targetdesigns);	

#	SAM Output from bowtie2 against the library
$filename = $ARGV[1];
open ($samlibrary, "<", $filename) or die "cannot open bowtie2 SAM file";


if ($ARGV[1]=~m/^(.+)\.sam$/)
{$filename = $1;	}
else
{die "No SAM file provided";}
	

open $seqdesign, ">", $filename."-designs.txt";
open $seqgene, ">", $filename."-genes.txt";

#	Parse blast output file
$lastinput=0;

@blastline=();

# define totalreads
$totalreads{"match"}=0;
$totalreads{"total"}=0;



#	Reading the SAM Library output

my $mismatchstring;
my $pos;
my @stringarray=();

my $direction;
my $aligned;


print "Reading Bowtie2 aligment to the reference library\n";

# Define the stringency of mapping results
		# predefined settings of quality:
		# perfect -> only 20bp fullmatch
		# high -> 18 bp out of 20
		# seed -> 14 bp match
		# otherwise user can define its own regular expression
		
		if($ARGV[2] eq "perfect")
		{
			$matchpattern = qr/M{20}$/ ;
		}
		elsif($ARGV[2] eq "high")
		{
			$matchpattern = qr/[M,X]+M{18}$/ ;
		}
		elsif($ARGV[2] eq "seed")
		{
			$matchpattern = qr/[M,X]+M{14}$/ ;
		}
		else
		{
			$matchpattern = qr/^M{20}$/ ;
		}
		
print("Match Setting: ".$matchpattern."\n");

while ($inputline = <$samlibrary>){
	@libinputline=split("\t",$inputline);		# Split line after each tab into array @libinputline to access SAM output
	
# SAM Output format
#	Col Field Type Regexp/Range Brief description
#	1 QNAME String [!-?A-~]{1,255} Query template NAME
#	2 FLAG Int [0,216-1] bitwise FLAG
#	3 RNAME String \*|[!-()+-<>-~][!-~]* Reference sequence NAME
#	4 POS Int [0,231-1] 1-based leftmost mapping POSition
#	5 MAPQ Int [0,28-1] MAPping Quality
#	6 CIGAR String \*|([0-9]+[MIDNSHPX=])+ CIGAR string
#	7 RNEXT String \*|=|[!-()+-<>-~][!-~]* Ref. name of the mate/next read
#	8 PNEXT Int [0,231-1] Position of the mate/next read
#	9 TLEN Int [-231+1,231-1] observed Template LENgth
#	10 SEQ String \*|[A-Za-z=.]+ segment SEQuence
#	11 QUAL String [!-~]+ ASCII of Phred-scaled base QUALity+33

# idea:
#	1.	First read in ALL the reads aligned to the library
#	2.	Store each read and its information about the mapped reference in Hash, count them as before for overall statistics
#	3.	Then verify for those that do have mismatches, what kind of mismatches they have (Flo Script?)
#	4.	Read in the mapped vs genome file
#	5.	Compare for each read whether the mapped gene symbol does match!
#		Especially unmapped reads might show off-targets!
#		Store the Genesymbol for each target in a hash and count the amount of reads for this off-target
	
	if($libinputline[0] =~m/^@.+$/)
	{
		# do nothing
	}
	
	# only count the mapped read if
	#	is a new line and not the old read
	#	First parameter is a Illumina Sequencing ID
	#	Second Parameter, the FLAG, indicates an alignment that is neither rev-complementary, nor unmapped, nor a mutliple alignment (FLAG = 0)
	elsif($libinputline[0] ne $lastinput && $libinputline[0] =~m/^(.+)$/ && $libinputline[1] == 0)
	
	{
		$lastinput=$libinputline[0];			# set last line to the recent one for next iteration
		 
		# get single information from SAM output for this read
		@geneid = split("_", $libinputline[2]);	# Extract the GeneSymbol

		# get aligment from SAM
		#	Script by Florian, adapted from make_mismatch_string()
		
			$mismatchstring     = "";
			$aligned			="";
			$pos                = 0;
      		@stringarray=split("\t",$inputline);
      		if($inputline=~m/MD:Z:(\S+)\s/){
       	 		$mismatchstring=$1;
      		}
      		@matchstring=split("",$stringarray[9]);
      		@matches=$stringarray[5]=~m/[0-9]+[MID]/g;
      		foreach $matchalign (@matches){
            	$matchalign=~/([0-9]+)([MID])/;
            	foreach (1..$1){
            		$matchstring[$pos]=$2;
                  	$pos++;
            	}
      		}
      		@matches    = $mismatchstring =~m/[0-9]+|[\^A-Z]+|[0-9]+$/g;
      		$pos        = 0;
      		foreach my $matchalign (@matches){
           		if($matchalign=~/([0-9]+)/){
                  	$pos += $1;
            	}elsif($matchalign=~/^[A-Z]$/){
                 	$matchstring[$pos]="X";
                  	$pos++;
            	}else{
                  	$pos++
            	}
      		}
      
      	foreach my $outalign (@matchstring)
      	{
      		$aligned.= $outalign;
      	} 
      	# releasing vars/arrays
      	@matchstring=();
      	@stringarray=();
      	@matches=();    		
	
		# define by sequence matchstring whether a mutation is present in read
		# 	match = all M
		
		
		
		if( $aligned =~m/$matchpattern/g )	# If identity is as set by ARGV2
		{	
		
			$libID{$libinputline[2]}{"match"}++;	# increase amount of reads for the perfect match
			$libID{$libinputline[2]}{"total"}++;
			$reads{$geneid[0]}{"genematch"}++;
			$reads{$geneid[0]}{"genetotal"}++;	# counts total reads for each gene
			$totalreads{"match"}++;
			$totalreads{"total"}++;
			$match++;
		}
		
		
	}

	
}
close($samlibrary);


	
####	Final Output Generation

print "Generating Output\n";



# MEAN reads per target
my %numbergenes; #used to have the number genes that were actually present!
$numbergenes{"total"}=0;
$numbergenes{"match"}=0;
$numbergenes{"none"}=0;



my %mean;
my %exclude;

my $numbertargets=0;

my $numbertargetstotal=0;
	
#Sort hash and put it into file

print $seqdesign "sgRNA\tCount\n";
print $seqgene "Gene\tCount\tdesigns-present\n";


foreach $target (sort keys %libID) {
	@geneid = split("_", $target);
	#calculate the number of targets per gene present in the run
	#and exclude any target of the gene that was already counted
	if (!defined $exclude{$target})
	{ 	
		$exclude{$target}=1;
		#get the number of genes that were not covered
		
		# get the number of genes that showed some read
		if ($libID{$target}{"match"} > 0)
		{ 	
	
			$reads{$geneid[0]}{"targetmatched"}++;  }
	
		
	}
	
	print $seqdesign "".$target."\t".$libID{$target}{"match"}."\n";
	
	
	# calculate mean reads per gene
	
	# median reads per gene (matching)
		
	}

foreach $target ( sort keys %reads) {
	
	print $seqgene "".$target."\t".$reads{$target}{"genematch"}."\t".$reads{$target}{"targetmatched"}."\n";

}	

close($seqdesign);
close($seqgene);


	
	