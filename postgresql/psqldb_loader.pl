#!/usr/bin/perl

=pod

=head1 NAME

psqldb_loader.pl - Loads a dump file into a database

=head1 SYNOPSIS

    psqldb_loader.pl my_database_name dump_filename

=head1 REQUIRES

Perl5, DBI, PostreSQL (command pg_dump)

=head1 DESCRIPTION

This script can be used to load a dump file (backup) into a PostgreSQL
database. Given a database name and a dump file, the script clears previous
data and loads the dump.
Full access rights can be auto-granted to the PostgreSQL account names provied.
The first PostgreSQL account specified will also be the owner of every object.

=cut

use strict;
use Carp qw (cluck confess croak);
use warnings;
use Getopt::Long;
use Pod::Usage;
use DBI;
my $term_readkey_loaded = 0;
eval
{
    require Term::ReadKey;
    import Term::ReadKey;
    $term_readkey_loaded = 1;
};




# Script options
#################

=pod

=head1 OPTIONS

    psqldb_dumper.pl [-help | -man]
    psqldb_dumper.pl -db_user <DB_USER> -db_name <DB_NAME> [-db_host <DB_HOST>] [-db_port <DB_PORT>] <DUMP_NAME> [psql_account] [psql_account] ...

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

=item B<DUMP_NAME> (string):

the PosgreSQL file name of the dump to load.

=item B<psql_account> (string):

name of a PostgreSQL account to grant full access to the database.
Several accounts can be provided (separated by spaces).
Note: the first PostgreSQL account provided  will also be the owner
of every object of the database.

=back

=cut


# CODE START
#############

# set auto-flush
$| = 1;

# options processing
my ($man, $help, $database_name, $database_user, $database_host, $database_port, $dump_name, $file_to_remove) = (0, 0, '', '', '', 0, '', '');
my @psql_accounts = ();

# parse options and print usage if there is a syntax error.
GetOptions("help|?"   => \$help,
           "man"      => \$man,
           "d|db_name=s" => \$database_name,
           "U|db_user=s" => \$database_user,
           "h|db_host=s" => \$database_host,
           "p|db_port=s" => \$database_port)
    or pod2usage(2);
    
if ($help) {pod2usage(1);}
if ($man) {pod2usage(-verbose => 2);}
if (!$database_name) {pod2usage(1);}
if (!$database_user) {pod2usage(1);}

$database_host ||= 'localhost';
$database_port ||= 5432;

$dump_name = shift @ARGV;
if (!$dump_name) {pod2usage(1);}

@psql_accounts = @ARGV;
@ARGV = ();

# check if dump file exists
if (-e "$dump_name")
{
    # make sure dump file is not empty
    if (-z "$dump_name")
    {
        confess "Empty dump file!";
    }
    # check for a compressed file
    if ($dump_name =~ m/\.tgz$/i)
    {
        # uncompress
        my $compress_dump_name = $dump_name;
        $dump_name =~ s/\.tgz$/.sql/i;
        $dump_name =~ s/^.*\///; # remove path info as uncompressed into current directory
        print "\nUncompressing dump (this may take a while)...";
        system("tar -zxvf $compress_dump_name") == 0 or confess "Failed to uncompress dump! $!";
        if ((-e "$dump_name") && (not -z "$dump_name"))
        {
            print "done!\n";
            #system("rm -f $compress_dump_name") == 0 or cluck "Failed to remove compressed dump! $!";
            $file_to_remove = $dump_name;
        }
        else
        {
            print "error!\nUncompress FAILED! \"$dump_name\" not found!\n";
        }
    }
    elsif ($dump_name =~ m/\.tbz$/i)
    {
        # uncompress
        my $compress_dump_name = $dump_name;
        $dump_name =~ s/\.tbz$/.sql/i;
        $dump_name =~ s/^.*\///; # remove path info as uncompressed into current directory
        print "\nUncompressing dump (this may take a while)...\n";
        system("tar -jxvf $compress_dump_name") == 0 or confess "Failed to uncompress dump! $!";
        if ((-e "$dump_name") && (not -z "$dump_name"))
        {
            print "done!\n";
            #system("rm -f $compress_dump_name") == 0 or cluck "Failed to remove compressed dump! $!";
            $file_to_remove = $dump_name;
        }
        else
        {
            print "error!\nUncompress FAILED! \"$dump_name\" not found!\n";
        }
    }
    elsif ($dump_name =~ m/\.sql\.bz2$/i)
    {
        # uncompress
        my $compress_dump_name = $dump_name;
        $dump_name =~ s/\.bz2$//i;
        $dump_name =~ s/^.*\///; # remove path info as uncompressed into current directory
        print "\nUncompressing dump (this may take a while)...\n";
        system("bunzip2 -k -c $compress_dump_name > $dump_name") == 0 or confess "Failed to uncompress dump! $!";
        if ((-e "$dump_name") && (not -z "$dump_name"))
        {
            print "done!\n";
            #system("rm -f $compress_dump_name") == 0 or cluck "Failed to remove compressed dump! $!";
            $file_to_remove = $dump_name;
        }
        else
        {
            print "error!\nUncompress FAILED! \"$dump_name\" not found!\n";
        }
    }
    elsif ($dump_name =~ m/\.sql\.gz$/i)
    {
        # uncompress
        my $compress_dump_name = $dump_name;
        $dump_name =~ s/\.gz$//i;
        $dump_name =~ s/^.*\///; # remove path info as uncompressed into current directory
        print "\nUncompressing dump (this may take a while)...\n";
        system("gunzip -c $compress_dump_name > $dump_name") == 0 or confess "Failed to uncompress dump! $!";
        if ((-e "$dump_name") && (not -z "$dump_name"))
        {
            print "done!\n";
            #system("rm -f $compress_dump_name") == 0 or cluck "Failed to remove compressed dump! $!";
            $file_to_remove = $dump_name;
        }
        else
        {
            print "error!\nUncompress FAILED! \"$dump_name\" not found!\n";
        }
    }

    
    my $command_line = "psql -U $database_user -h $database_host -p $database_port $database_name <$dump_name";
    print "\nCommand line:\n    $command_line\n";

    print "\n\nWARNING: all the data currently stored in the database \"$database_name\" will be erased/lost and replaced by the content of the dump file!\nLoad the dump into database? (y/n) [n]? ";
    chomp (my $line = <STDIN>);
    if ($line && ($line =~ /^[yY]/))
    {
        # prepare database...
        # ask database password to connect
        print "\nPlease enter the password to connect to the database (as $database_user):\n";
        ReadMode('noecho') if $term_readkey_loaded;
        chomp(my $psql_password = $term_readkey_loaded? ReadLine(0) : <STDIN>);
        ReadMode('restore') if $term_readkey_loaded;

        print "Preparing database...";
        # connect to the database
        my $dbh = DBI->connect("dbi:Pg:dbname=$database_name;host=$database_host;port=$database_port", $database_user, $psql_password);
        if (not $dbh)
        {
            confess "Failed to connect to the database!";
        }

        # clear database (drop schema except system schema)
        my $sth  = $dbh->prepare("SELECT nspname FROM pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname != 'information_schema';");
        $sth->execute();
        my $result = $sth->fetchall_arrayref();
        if ($result && ('ARRAY' eq ref($result)) && (@$result))
        {
            foreach my $schema (@$result)
            {
                next if ('public' eq $schema->[0]); # keep 'public' for the end
                if (not $dbh->do("DROP SCHEMA " . $schema->[0] ." CASCADE;"))
                {
                    confess "Failed to empty database!\n" . $dbh->errstr;
                }
            }
            # drop public schema
            if (not $dbh->do("DROP SCHEMA public CASCADE;"))
            {
                confess "Failed to empty database!\n" . $dbh->errstr;
            }
        }
        else
        {
            cluck "Warning: database seems already empty!";
        }

        # create a new empty database
        if (not $dbh->do("CREATE SCHEMA public;"))
        {
            confess "Failed to create new database!\n" . $dbh->errstr;
        }
        print "done!\n";

        # load the dump
        print "Loading dump (this may take a while)...\n";
        system($command_line) == 0 or confess "Failed to load dump into database! $!";
        print "done!\n";

        # grant access
        foreach my $account (@psql_accounts)
        {
            print "Granting full access to $account...";
            # tables
            print "...tables";
            $sth  = $dbh->prepare("SELECT t.tablename FROM pg_tables t WHERE t.schemaname = 'public';");
            $sth->execute();
            $result = $sth->fetchall_arrayref();
            if ($result && ('ARRAY' eq ref($result)) && (@$result))
            {
                foreach my $table (@$result)
                {
                    if (not $dbh->do("GRANT ALL ON " . $table->[0] ." TO $account;"))
                    {
                        confess "Failed to grant access to $account on table " . $table->[0] ."!\n" . $dbh->errstr;
                    }
                }
            }
            # views
            print "...views";
            $sth  = $dbh->prepare("SELECT v.viewname FROM pg_views v WHERE v.schemaname = 'public';");
            $sth->execute();
            $result = $sth->fetchall_arrayref();
            if ($result && ('ARRAY' eq ref($result)) && (@$result))
            {
                foreach my $view (@$result)
                {
                    if (not $dbh->do("GRANT ALL ON " . $view->[0] ." TO $account;"))
                    {
                        confess "Failed to grant access to $account on view " . $view->[0] ."!\n" . $dbh->errstr;
                    }
                }
            }
            # sequences
            print "...sequences";
            $sth  = $dbh->prepare("SELECT c.relname AS seqname FROM pg_catalog.pg_class c, pg_catalog.pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = 'S' AND n.nspname = 'public';");
            $sth->execute();
            $result = $sth->fetchall_arrayref();
            if ($result && ('ARRAY' eq ref($result)) && (@$result))
            {
                foreach my $sequence (@$result)
                {
                    if (not $dbh->do("GRANT SELECT, UPDATE, USAGE ON " . $sequence->[0] ." TO $account;"))
                    {
                        confess "Failed to grant access to $account on sequence " . $sequence->[0] ."!\n" . $dbh->errstr;
                    }
                }
            }
            print "...Done!\n";
        }

        # Change owner to the first specified user
        if (@psql_accounts)
        {
            print "Changing owner to $psql_accounts[0]";
            # tables
            print "...tables";
            $sth  = $dbh->prepare("SELECT t.tablename FROM pg_tables t WHERE t.schemaname = 'public';");
            $sth->execute();
            $result = $sth->fetchall_arrayref();
            if ($result && ('ARRAY' eq ref($result)) && (@$result))
            {
                foreach my $table (@$result)
                {
                    if (not $dbh->do("ALTER TABLE " . $table->[0] ." OWNER TO $psql_accounts[0];"))
                    {
                        confess "Failed to change owner of table " . $table->[0] ."!\n" . $dbh->errstr;
                    }
                }
            }
            # views
            print "...views";
            $sth  = $dbh->prepare("SELECT v.viewname FROM pg_views v WHERE v.schemaname = 'public';");
            $sth->execute();
            $result = $sth->fetchall_arrayref();
            if ($result && ('ARRAY' eq ref($result)) && (@$result))
            {
                foreach my $view (@$result)
                {
                    if (not $dbh->do("ALTER TABLE " . $view->[0] ." OWNER TO $psql_accounts[0];"))
                    {
                        confess "Failed to change owner of view " . $view->[0] ."!\n" . $dbh->errstr;
                    }
                }
            }
            # sequences
            print "...sequences";
            $sth  = $dbh->prepare("SELECT c.relname AS seqname FROM pg_catalog.pg_class c, pg_catalog.pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = 'S' AND n.nspname = 'public';");
            $sth->execute();
            $result = $sth->fetchall_arrayref();
            if ($result && ('ARRAY' eq ref($result)) && (@$result))
            {
                foreach my $sequence (@$result)
                {
                    if (not $dbh->do("ALTER TABLE " . $sequence->[0] ." OWNER TO $psql_accounts[0];"))
                    {
                        confess "Failed to change owner of sequence " . $sequence->[0] ."!\n" . $dbh->errstr;
                    }
                }
            }
            # functions
            print "...functions";
            $sth  = $dbh->prepare("SELECT p.proname AS proname, ARRAY(SELECT t.typname FROM pg_catalog.pg_type t, (SELECT p.proargtypes AS types_code_array) AS typenames_array CROSS JOIN generate_series(0, p.pronargs) AS i WHERE t.oid = types_code_array[i] ORDER BY i ASC) AS input_types, p.proargtypes FROM pg_catalog.pg_proc p, pg_catalog.pg_namespace n WHERE p.proisagg = FALSE AND p.pronamespace = n.oid AND n.nspname = 'public';");
            $sth->execute();
            $result = $sth->fetchall_arrayref();
            if ($result && ('ARRAY' eq ref($result)) && (@$result))
            {
                foreach my $procedure (@$result)
                {
                    my $proc_args = $procedure->[1] || '';
                    # check if we got an array ref (DBD::Pg new version)
                    if (ref($proc_args) eq 'ARRAY')
                    {
                        $proc_args = join(', ', @$proc_args);
                    }
                    elsif (length($proc_args) >= 2)
                    {
                        # remove leading '{' and ending '}'
                        $proc_args =~ s/^\s*{//;
                        $proc_args =~ s/}\s*$//;
                    }
                    if (not $dbh->do("ALTER FUNCTION " . $procedure->[0] . "($proc_args) OWNER TO $psql_accounts[0];"))
                    {
                        confess "Failed to change owner of function " . $procedure->[0] ."!\n" . $dbh->errstr;
                    }
                }
            }
            # schema
            if (not $dbh->do("ALTER SCHEMA public OWNER TO $psql_accounts[0];"))
            {
                confess "Failed to change owner of the schema 'public'!\n" . $dbh->errstr;
            }
            print "...Done!\n";
        }

        # disconnect
        $dbh->disconnect();

        # remove uncompressed temporary file
        system("rm -f $file_to_remove") == 0 or cluck "Failed to remove temporary un compressed dump! $!";
    }
    else
    {
        print "\nDump loading canceled!\n";
    }

}
else
{
    confess "Dump file name ('$dump_name') not found!";
}


# CODE END
###########


=pod

=head1 AUTHORS

Valentin GUIGNON (CIRAD), valentin.guignon@cirad.fr

=head1 VERSION

Version 1.3.3

Date 01/06/2010

=head1 SEE ALSO

PostgreSQL, Chado database

=cut
