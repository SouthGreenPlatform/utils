#!/usr/bin/perl

#  
#  Copyright 2014 INRA
#  
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#  
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, see <http://www.gnu.org/licenses/> or 
#  write to the Free Software Foundation, Inc., 
#  51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#  
#  

=pod

=head1 VCF to Fasta

Transpose annotation from a previous genome version to a new one using the same scaffold

=head1 SYNOPSIS

transpose_annotation -og gff_file -ng gff_file -a file -o file 

=cut

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;

use Bio::Tools::GFF;

use Data::Dumper;

=pod

=head1 OPTIONS


=head2 Parameters

=over 5

=item B<[-og]> ([a gff file]): 

A GFF file containing the scaffold position on the old genome version

=item B<[-ng]> ([a gff file]): 

A GFF file containing the scaffold position on the new genome version

=item B<[-a]> ([a gff or vcf file]): 

The annotation to transpose

=item B<[-o]> ([a file]): 

The transposed annotation on the new genome. It will be in the same formatas the input

=cut

my $BEDTOOLS = 'intersectBed';

unless (@ARGV)
{
  pod2usage(0);
}

#options processing
my ($man, $help, $debug, $old_gen, $new_gen, $to_transpose, $output, $not_transposable);
# parse options and print usage if there is a syntax error.
#--- see doc at http://perldoc.perl.org/Getopt/Long.html
GetOptions("help|?"     => \$help,
           "man"        => \$man,
           "debug:i"    => \$debug,
           "old|og=s" =>	\$old_gen,
           "new|ng=s" =>	\$new_gen,
           "annot|a=s" => \$to_transpose, 
           "output|o=s"  => \$output,
) or pod2usage(2);
if ($help) {pod2usage(0);}
if ($man) {pod2usage(-verbose => 2);}

if(! -e $old_gen) 
{
  print("Cannot find $old_gen");
  pod2usage(0);
}

if(! -e $new_gen) 
{
  print("Cannot find $new_gen");
  pod2usage(0);
}

if(! -e $to_transpose) 
{
  print("Cannot find $to_transpose");
  pod2usage(0);
}

if(!defined($output))
{
  print("You did not precise an output file");
  pod2usage(0);
}

system($BEDTOOLS."  -a $to_transpose -b $old_gen -f 1.0 -wo >$output.tmp");


#Parse scaffold position on new genome
my %new_gen;

my $gff_handle = new Bio::Tools::GFF(-gff_version => 3,
                                     -file => $new_gen);

while(my $feature = $gff_handle->next_feature())
{
	my @name = $feature->get_tag_values('ID');
	$new_gen{$name[0]}=$feature;
}

my $output_handle;
if(open($output_handle, ">".$output))
{                            
	my $intersect_handle;
	if(open($intersect_handle, $output.".tmp"))
	{
		if($to_transpose =~ m/\.gff/)
		{
			while(my $line=<$intersect_handle>)
			{
				my @splitted = split('\t', $line);
			
				my $start_on_scaffold = 0;
				my $end_on_scaffold = 0;
				my $strand_on_scaffold = 1;
				
				my $feature_start = $splitted[3];
				my $feature_end = $splitted[4];
				
				my $scaffold_start = $splitted[12];
				my $scaffold_end = $splitted[13];
				
				my $scaffold_strand = 1;
				if($splitted[15] eq "-" )
				{
					$scaffold_strand = -1;
				}
				my $feature_strand = 1;
				if($splitted[5] eq "-" )
				{
					$feature_strand = -1;
				}
				
				$splitted[17] =~ m/ID=([^;]*)/;
				my $scaffold_id = $1;
				
				#First recover position of the feature on the scaffold
				
				#if scaffold is on positive strand
				if($scaffold_strand == 1)
				{
					$start_on_scaffold = $feature_start - $scaffold_start +1 ;
					$end_on_scaffold = $feature_end - $scaffold_start + 1;
				}
				else
				{
					$start_on_scaffold = ($scaffold_end - $scaffold_start)  - ($feature_end - $scaffold_start)+1;
					$end_on_scaffold = ($scaffold_end - $scaffold_start)  - ($feature_start - $scaffold_start)+1;
				}
				
				if( $feature_strand ne $scaffold_strand)
				{
					$strand_on_scaffold = -1;
				}  	
				
				#Transpose annotation on the new genome version
				
				#Create a new generic feature                             

	#			my $transposed_feature = new Bio::SeqFeature::Generic ( -start => 1, -end => 1,
	#									-strand => 1, -primary => $splitted[2],
	#									-source_tag   => $splitted[1],
	#									-seq_id => "chr",
	#									-score  => $splitted[5],
	#									 );
										 
			   
				
				#Recover the corresponding scaffold on the new genome
				if(exists($new_gen{$scaffold_id}))
				{
					 my $scaffold_on_new = $new_gen{$scaffold_id};
				
					#Change coordinate, strand and seq of this feature
					
					my ($start, $end, $strand, $seq);
					
					$seq = $scaffold_on_new->seq_id();
					
					if($strand_on_scaffold == $scaffold_on_new->strand())
					{
						$strand = 1;
					}
					else
					{
						$strand = -1;
					}
					
					if($scaffold_on_new->strand() == 1)
					{
						$start = $start_on_scaffold + $scaffold_on_new->start() - 1;
						$end = $end_on_scaffold + $scaffold_on_new->start() - 1;
					}
					else
					{
						$end =  $scaffold_on_new->end() - $start_on_scaffold  + 1;
						$start  = $scaffold_on_new->end() - $end_on_scaffold  + 1;
					}
					
	#				$transposed_feature->start($start);
	#				$transposed_feature->end($end);
	#				$transposed_feature->strand($strand);
	#				$transposed_feature->seq_id($seq);
					
	#				$output_handle->write_feature($transposed_feature);
					my $str='+';
					if($strand==-1)
					{
						$str='-';
					}
					my $toprint = join("\t",
										$seq,
										$splitted[1],
										$splitted[2],
										$start,
										$end,
										$splitted[5],
										$str,
										$splitted[7],
										$splitted[8]);
					print $output_handle $toprint."\n";
				}
				else
				{
					print "No ".$scaffold_id." found in the new genome version\n";
				}
			   
			}
		}
		elsif($to_transpose =~ m/\.vcf/)
		{
			#We need to determine the number of fields in the VCF
			my $to_transpose_handle;
			my $field_number;
			if(open($to_transpose_handle, $to_transpose))
			{
				while(my $line=<$to_transpose_handle>)
				{
					if($line =~ m/^##/)
					{
						print $output_handle $line;
					}
					else
					{
						print $output_handle $line;
						my @splitted = split('\t', $line);
						$field_number = scalar(@splitted);
						last;
					}
				}
			}
			else
			{
				print("Cannot open $to_transpose");
				exit(0);
			}
			while(my $line=<$intersect_handle>)
			{
				my @splitted = split('\t', $line);
				#Recover the Variant positions
				my $pos_on_scaffold = 0;
				
				my $feature_pos = $splitted[1];
				
				my $scaffold_start = $splitted[$field_number+3];
				my $scaffold_end = $splitted[$field_number+4];
				
				my $scaffold_strand = 1;
				if($splitted[$field_number+6] eq "-" )
				{
					$scaffold_strand = -1;
				}
				
				$splitted[$field_number+8] =~ m/ID=([^;]*)/;
				my $scaffold_id = $1;
				
				if($scaffold_strand == 1)
				{
					$pos_on_scaffold = $feature_pos - $scaffold_start +1 ;
				}
				else
				{
					$pos_on_scaffold = ($scaffold_end - $scaffold_start)  - ($feature_pos - $scaffold_start)+1;
				}
				
				#Recover the corresponding scaffold on the new genome
				if(exists($new_gen{$scaffold_id}))
				{
					my $scaffold_on_new = $new_gen{$scaffold_id};
				
					#Change coordinate, strand and seq of this feature
					
					my ($pos, $strand, $seq);
					
					$seq = $scaffold_on_new->seq_id();
					
					if($scaffold_strand == $scaffold_on_new->strand())
					{
						$strand = 1;
					}
					else
					{
						$strand = -1;
					}
					
					if($scaffold_on_new->strand() == 1)
					{
						$pos = $pos_on_scaffold + $scaffold_on_new->start() - 1;
					}
					else
					{
						$pos =  $scaffold_on_new->end() - $pos_on_scaffold  + 1;
					}
					$splitted[1] = $pos;
					#if scaffold in both version are not on the same strand, then get the allele reverse/complement
					if($strand == -1)
					{
						$splitted[3] = reverse($splitted[3]);
						$splitted[3] =~ tr/ACGT/TGCA/ ;
						$splitted[4] = reverse($splitted[4]);
						$splitted[4] =~ tr/ACGT/TGCA/ ;
					}
					my $to_print= $splitted[0];
					for(my $i=1;$i<$field_number;$i++)
					{
						$to_print .= "\t".$splitted[$i];
					}
					
					print $output_handle $to_print."\n";
				}
			}
			
			#CAVEAT for indels it is not the exact reverse/complement that should be given
			
		}
		 $output_handle -> close();
	}
	else
	{
		print("Cannot open bedtools output");
		exit(0);
	}
}
else
{
	print "Cannot write $output";
}
                                     
=head1 DEPENDENCIES

BioPerl, BedTools

=head1 INCOMPATIBILITIES

Fully compatible with any perl version

=head1 BUGS AND LIMITATIONS

<NO BUG FOUND YET>

=head1 AUTHORS

=over 2

=item Gautier SARAH (INRA), gautier.sarah-at-supagro.inra.fr

=back

=head1 VERSION

1.0.0

=head1 DATE

10/09/2014

=head1 LICENSE AND COPYRIGHT

  Copyright 2014 INRA
 
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3 of the License, or
  (at your option) any later version.
  
  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
  
  You should have received a copy of the GNU General Public License
  along with this program; if not, if not, see <http://www.gnu.org/licenses/> 
  or write to the Free Software Foundation, Inc.,
  51 Franklin Street, Fifth Floor, Boston,
  MA 02110-1301, USA.

=cut
