#!/usr/bin/perl

=pod

=head1 NAME

psqldb_dumper.pl - Dumps a database into a file

=head1 SYNOPSIS

    psqldb_dumper.pl -db_name my_database_name -db_user my_admin_login

=head1 REQUIRES

Perl5, PostreSQL (command pg_dump)

=head1 DESCRIPTION

This script can be used to dump (backup) a PostgreSQL database. Given a
database name, the script generates a dump file name and dumps.
The dump file name is like:
 dump_<db_name>_<YEAR><MONTH><DAY>[DUMP_VERSION].sql

where <db_name> is the database name, <YEAR> the year on 4 digits,
<MONTH> the month on 2 digits, <DAY> the day of the month on 2 digits and
if necessary (ie. in case of several dumps the same day) [DUMP_VERSION] the
letter code of the new dump version (for instance 'a' or 'b'...).

=cut

use strict;
use Carp qw (cluck confess croak);
use warnings;
use Getopt::Long;
use Pod::Usage;


# Script global constants
##########################

=pod

=head1 CONSTANTS

B<$DUMP_PREFIX>: (string)

dump file prefix.

B<$DUMP_SUFFIX>: (string)

dump file suffix.

B<$COMPRESSED_SUFFIX>: (string)

compressed file suffix.

B<$DESCRIPTION_SUFFIX>: (string)

dump description file suffix.

=cut

my $DUMP_PREFIX       = 'dump_';
my $DUMP_SUFFIX       = '.sql';
my $COMPRESSED_SUFFIX = '.tbz';
my $DESCRIPTION_SUFFIX = '.info';




# Script options
#################

=pod

=head1 OPTIONS

    psqldb_dumper.pl [-help | -man]
    psqldb_dumper.pl -db_user <DB_USER> -db_name <DB_NAME> [-db_host <DB_HOST>] [-db_port <DB_PORT>] [-m <DESCRIPTION>] [-q]

=head2 Parameters

=over 4

=item B<-help>:

Prints a brief help message and exits.

=item B<-man>:

Prints the manual page and exits.

=item B<DB_USER> (string):

the PosgreSQL database administrator login.

=item B<DB_NAME> (string):

the PosgreSQL database name.

=item B<DB_HOST> (string):

the PosgreSQL host.

=item B<DB_PORT> (string):

the PosgreSQL port.

=item B<DESCRIPTION> (string):

a descriptive message of the database dump. This message should be informative
for other users and explain why you did a dump and which version of the data
it contains.

=item B<-q>:

non-interactive mode (quiet). The dumper won't ask anything to the user except
database password.

=back

=cut


# CODE START
#############

# options processing
my ($man, $help, $database_name, $database_user, $database_host, $database_port, $description, $non_interactive, $line) = (0, 0, '', '', '', '', '', 0, '');

# parse options and print usage if there is a syntax error.
GetOptions("help|?"   => \$help,
           "man"      => \$man,
           "d|db_name=s" => \$database_name,
           "U|db_user=s" => \$database_user,
           "h|db_host=s" => \$database_host,
           "p|db_port=s" => \$database_port,
           "m|description=s" => \$description,
           "q" => \$non_interactive)
    or pod2usage(2);
    
if ($help) {pod2usage(1);}
if ($man) {pod2usage(-verbose => 2);}
if (!$database_name) {pod2usage(1);}
if (!$database_user) {pod2usage(1);}

$database_host ||= 'localhost';
$database_port ||= 5432;

# get date to generated name
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime time;
++$mon; # month are 0-based
$year += 1900; # computer years start in 1900

my $dump_name = sprintf("%s%s_%d%0.2d%0.2d", $DUMP_PREFIX, $database_name, $year, $mon, $mday);
my $dump_index = 'a';

# check if dump name already exists
if (-e "$dump_name.sql")
{
    # find next free version letter
    while (-e "$dump_name$dump_index.sql")
    {
        ++$dump_index;
    }
    $dump_name .= $dump_index;
}

my $command_line = "pg_dump --no-owner --no-privileges --disable-triggers -U $database_user -h $database_host -p $database_port $database_name -f $dump_name$DUMP_SUFFIX";
print "\nCommand line:\n    $command_line\n";

if (!$non_interactive)
{
    print "\n\nProcess database dumping with the above command line (y/n) [y]? ";
    chomp ($line = <STDIN>);
}
if (!$line || $line =~ /^[yY]/)
{
    # get a description
    if (!$description && !$non_interactive)
    {
        print "\n\nPlease enter a description of the dump (ie. an informative text to let other user know why you did the dump and what version of the data it contains):\n";
        chomp ($description = <STDIN>);
    }

    print "Dumping (this may take a while)...\n";
    system($command_line) == 0 or confess "Failed to dump database! $!";
    if ((-e "$dump_name$DUMP_SUFFIX") && (not -z "$dump_name$DUMP_SUFFIX"))
    {
        print "Done!\n\"$dump_name$DUMP_SUFFIX\" generated successfully!\nCompressing (this may take a while as well)...\n";
        # compress using bzip2 compression
        $command_line = "tar -cjvf $dump_name$COMPRESSED_SUFFIX $dump_name$DUMP_SUFFIX";
        system($command_line) == 0 or confess "Failed to compress dump! $!";
        if ((-e "$dump_name$COMPRESSED_SUFFIX") && (not -z "$dump_name$COMPRESSED_SUFFIX"))
        {
            print "done!\n\"$dump_name$COMPRESSED_SUFFIX\" generated successfully!\n";
        }
        else
        {
            print "error!\nCompression FAILED!\n";
        }
    }
    else
    {
        print "error!\nDump FAILED!\n";
    }
    # save description
    if ($description)
    {
        my $description_fh;
        open $description_fh, ">$dump_name$DESCRIPTION_SUFFIX" or confess "Can't open $dump_name$DESCRIPTION_SUFFIX for writting: $!";
        print $description_fh $description;
        close $description_fh;
    }

}
else
{
    print "\nDump canceled!\n";
}


# CODE END
###########


=pod

=head1 AUTHORS

Valentin GUIGNON (CIRAD), valentin.guignon@cirad.fr

=head1 VERSION

Version 1.3.2

Date 06/05/2010

=head1 SEE ALSO

PostgreSQL, Chado database

=cut
