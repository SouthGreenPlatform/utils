#!/usr/bin/perl

#  
#  Copyright 2015 INRA
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

=head1 ConcatenateFasta_Alignment


Concatenat Fasta Alignments by sequence identifier

=head1 SYNOPSIS

ConcatenateFasta_Alignment.pl -i fasta_alignment -o output -missing_position missing_character [-id_length id_length_to_use] 

=cut

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Fatal qw/:void open close/;

use Bio::SeqIO;

=pod

=head1 OPTIONS


=head2 Parameters



ConcatenateFasta_Alignment.pl -input fasta_alignment -output output -missing_char missing_character [-del character_to_delete] [-id_length id_length_to_use] 

=over 4

=item B<-input> (file):

The Fasta alignment to concatenate. This option can be provided as many times as needed

=item B<-output> (file):

The output Fasta alignment file containing the concatenation of all input

=item B<-missing_char> (character):

The character to use when a base is missing in one file
Default: ?

=item B<-del> (character):

A character, which will trigger the deletion of all bases at its position. This option can be provided as many times as needed
Default: No position are deleted

=item B<-id_length> (integer above 4):

Limit the sequence name to this number of character. Be careful when using this parameter that you can discriminate all your sequences when you limit the sequence names
Default: Use the whole sequence name


=back


=cut

unless (@ARGV)
{
  pod2usage(0);
  exit();
}

# options processing
my ($man, $help, $debug, @input, $output, $missing_char, @to_delete, $id_length);
$missing_char="?";
$id_length=0;
# parse options and print usage if there is a syntax error.
#--- see doc at http://perldoc.perl.org/Getopt/Long.html
GetOptions("help|?"     => \$help,
           "man"        => \$man,
           "debug:i"    => \$debug,
           "id_length|id=i" =>\$id_length,
           "missing_char|m=s" =>\$missing_char,
           "del|d=s"	=> \@to_delete,
           "input|i=s" =>\@input,
           "output|o=s"  => \$output 
) or pod2usage(2);
if ($help) {pod2usage(0);}
if ($man) {pod2usage(-verbose => 2);}
if(@input<2)
{
	print "You provided no or only one input file";
	exit();
}
foreach my $fasta (@input)
{
	if(!-e $fasta)
	{
		print "Cannot find $fasta";
		exit();
	}
}
if($id_length && $id_length<4)
{
	print "id_length must be above 4";
	exit();
}

my $fasta =shift(@input);
my $seq_io = Bio::SeqIO->new(-file => $fasta,
                             -format => "fasta"
                               );
my %sequences;
my $seq_length;
my $i =0;
while (my $seq = $seq_io->next_seq)
{
	if(!$i)
	{
		$seq_length = length($seq->seq);
		$i++;
	}
	my $sequence=$seq->seq;
	my $id=$seq->display_id;

	if($id_length)
	{
		$id=substr($id,0,$id_length);
	}
	if(exists($sequences{$id}))
	{
		print "$id seems to be a redondant identifier";
		exit();
	}
	$sequences{$id}=$sequence;
}

foreach $fasta (@input)
{
	$seq_io = Bio::SeqIO->new(-file => $fasta,
	                          -format => "fasta"
	                          );
	my %existing_id;
	foreach my $ids (keys(%sequences))
	{
		$existing_id{$ids}++;
	}
	$i=0;
	my $this_length;
	while (my $seq = $seq_io->next_seq)
	{
		if(!$i)
		{
			$seq_length += length($seq->seq);
			$this_length=length($seq->seq);
			$i++;
		}
		my $sequence=$seq->seq;
		my $id=$seq->display_id;
		if($id_length)
		{
			$id=substr($id,0,$id_length);
		}
		if(!exists($sequences{$id}))
		{
			for(my $j=0;$j<($seq_length-$this_length);$j++)
			{
				$sequences{$id}.=$missing_char;
			}
		}
		$sequences{$id}.=$sequence;
		delete($existing_id{$id});
	}
	foreach my $ids (keys(%existing_id))
	{
		for(my $j=0;$j<$this_length;$j++)
		{
			$sequences{$ids}.=$missing_char;
		}
	}
}

if(@to_delete>0)
{
	my %positions_to_delete;
	foreach my $seq (keys(%sequences))
	{
		foreach my $char (@to_delete)
		{
			my $offset = 0;
			do
			{
				
				$offset = index($sequences{$seq}, $char, $offset);
				$positions_to_delete{$offset}++;
				$offset ++;
			}while($offset!=0)
		}
	}
	delete($positions_to_delete{-1});
	if($debug)
	{
		foreach my $pos (sort {$a <=> $b} keys(%positions_to_delete))
		{
			print $pos."\n";
		}
	}
	
	foreach my $seq (keys(%sequences))
	{
		my @splitted = split('',$sequences{$seq});
		foreach my $pos (sort {$a <=> $b} keys(%positions_to_delete))
		{
			$splitted[$pos]='';
			
		}
		$sequences{$seq}= join('',@splitted);
	}
	
}

my $handler;
open($handler,">$output");
foreach my $seq (keys(%sequences))
{
	print $handler ">$seq\n".$sequences{$seq}."\n";
}

=pod
=head1 DEPENDENCIES
BioPerl

=head1 INCOMPATIBILITIES
Fully compatible with any perl version

=head1 BUGS AND LIMITATIONS
<NO BUG FOUND YET>

=head1 AUTHORS
=over 1
=item Gautier SARAH (INRA), gautier.sarah-at-supagro.inra.fr
=back

=head1 VERSION
1.0.0
=head1 DATE
01/07/2015
=head1 LICENSE AND COPYRIGHT
  Copyright 2015 INRA
 
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


