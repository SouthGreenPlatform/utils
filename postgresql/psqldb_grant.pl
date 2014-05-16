#!/usr/bin/perl

=pod

=head1 NAME

psqlgrant.pl - PostgreSQL grant tool

=head1 SYNOPSIS

    psqlgrant.pl

=head1 REQUIRES

Perl5.

=head1 DESCRIPTION

This script can be used to set the access rights of tables, views, sequences
and functions of a user (role). By default, full access are given.
Note: any previous access rights are removed.

=cut


use strict;
use Carp qw (cluck confess croak);
use warnings;
use Getopt::Long;
use Pod::Usage;
use Error qw(:try);

use DBI;

# used to hide passwords entered by the user
my $term_readkey_loaded = 0;
eval
{
    require Term::ReadKey;
    import Term::ReadKey;
    $term_readkey_loaded = 1;
};
$| = 1;



# Script global functions
##########################

=pod

=head1 FUNCTIONS

=head2 prompt

B<Description>: query the user for something.

B<ArgsCount>: [1-2]

=over 4

=item $prompt_message: (string) (R)

Query message to display to the user.

=item $parameters: (hash ref) (O)

A reference to a hash containing additional optional parameters as key --> value:
default --> default value to use if the user just hit "Enter"
constraint --> a regular expression used to validate the value entered by the user
no_trim --> if set to non-zero, the string entered by the user is not trimed so leading and ending spaces are kept
no_echo --> if set to non-zero, what the user type is not displayed on screen (usefull for passwords)

=back

B<Return>: (scalar)

the value entered by the user

B<Example>:

    prompt("Where are you?", { default => 'In front of my computer', constraint => '\w{3,}', no_trim = 1 });

=cut

sub prompt
{
    my ($prompt_message, $parameters) = (@_);

    if (not defined $prompt_message)
    {
        confess "Error (prompt()): no message provided!";
    }

    if (not defined $parameters)
    {
        $parameters = {};
    }
    elsif ('HASH' ne ref($parameters))
    {
        confess "Error (prompt()): parameters not passed has a hash reference!";
    }

    my ($default_value, $constraint, $no_trim, $no_echo) = ($parameters->{default}, $parameters->{constraint}, $parameters->{no_trim}, $parameters->{no_echo});

    if (not defined $constraint)
    {
        # if no constraint set, asks the user to provide at least 1 character
        $constraint = '.';
    }

    my $user_value = '';

    if ($no_echo && $term_readkey_loaded)
    {
        ReadMode('noecho');
    }

    do
    {
        if (($constraint ne '') && ($user_value ne ''))
        {
            # an attempt has already been made, let the user know he/she did not give a good answer
            print "Invalid value! Try again...\n";
        }
        # query user
        print "$prompt_message ";
        # display default value if set
        if ((defined $default_value) && ($default_value ne ''))
        {
            print "(default: $default_value) ";
        }
        # get user input
        chomp($user_value = <STDIN>);
        # trim if needed
        if (not $no_trim)
        {
            $user_value =~ s/^[\s\t]*//;
            $user_value =~ s/[\s\t]*$//;
        }
        # check if user wants default value
        if (($user_value eq '') && (defined $default_value))
        {
            $user_value = $default_value;
            print "* $default_value *\n";
        }
        if ($no_echo && $term_readkey_loaded)
        {
            print "\n";
        }
    } while (($user_value !~ m/$constraint/io)
             && ((not defined $default_value) || ($user_value ne $default_value)));

    if ($no_echo && $term_readkey_loaded)
    {
        ReadMode('restore') if $term_readkey_loaded;
    }

    return $user_value;
}




# Script options
#################

=pod

=head1 OPTIONS

psqlgrant.pl [-help | -man] <-r[ole] <role_name> > [-g[rant] <rights>] [-s[eq_grant] <rights>] [-f[unc_grant] <rights>] [-h <host>] [-p <port>] [-d <database>] [-U <login>] [-W <password>]

=head2 Parameters

=over 4

=item B<help> (flag):

Display help.

=item B<man> (flag):

Display manual.

=item B<host> (string):

Specifies the database server name.

=item B<port> (integer):

Specifies the database port number.

=item B<database> (string):

Specifies the database name.

=item B<login> (string):

Specifies the admin login to use.

=item B<password> (string):

Specifies the admin password.

=item B<role> (string):

Role to grant the rights to.
Note: multiple roles can be specified.

=item B<grant> (string):

the rights to grant on tables and views.
Possible values: { SKIP | SELECT | INSERT | UPDATE | DELETE | REFERENCES | TRIGGER } [,...] | ALL [ PRIVILEGES ] }
The 'SKIP' value can be used to leave current rights as is.
Example: "SELECT,TRIGGER"
Default: ALL

=item B<seq_grant> (string):

the rights to grant on sequences.
Possible values: { SKIP | USAGE | SELECT | UPDATE } [,...] | ALL [ PRIVILEGES ] }
The 'SKIP' value can be used to leave current rights as is.
Example: USAGE
Default: ALL

=item B<func_grant> (string):

the rights to grant on functions.
Possible values: { SKIP | EXECUTE | ALL [ PRIVILEGES ] }
The 'SKIP' value can be used to leave current rights as is.
Example: EXECUTE
Default: ALL

=back

=cut


# CODE START
#############

print "\nPostgreSQL Grant Helper v1.0.0\n\n";

# options processing
my ($schema,$man, $help, $debug, $db_server, $db_port, $db_name, $db_login, $db_password, $transaction_id, $role, $grant, $seq_grant, $func_grant) = (0, 0, 0, '', 0, '', '', '', 0, '', '', '', '');
# parse options and print usage if there is a syntax error.
GetOptions("help|?"         => \$help,
           "man"            => \$man,
           "debug"          => \$debug,
           "h|host=s"       => \$db_server,
           "p|port=i"       => \$db_port,
           "d|database=s"   => \$db_name,
           "U|user=s"       => \$db_login,
           "W|password=s"   => \$db_password,
           "r|role=s"       => \$role,
           "f|func_grant=s" => \$func_grant,
           "s|seq_grant=s"  => \$seq_grant,
           "g|grant=s"      => \$grant,
	   "c|schema=s"     => \$schema)
    or pod2usage(2);
if ($help || (!$role)) {pod2usage(1);}
if ($man) {pod2usage(-verbose => 2);}

$db_server  ||= prompt('Enter PostgreSQL server name?', { default => 'localhost'});
$db_port    ||= prompt('What port is used?', { default => '5432'});
$db_name    ||= prompt('What is the name of the database?', { default => 'db'});
$db_login   ||= prompt('What is the admin login to use?', { default => 'postgres'});

if (not $db_password)
{
    $db_password = prompt("Please enter the password to connect to the database (as $db_login):", { no_echo => 1});
}

$func_grant ||= 'ALL';
$seq_grant  ||= 'ALL';
$grant      ||= 'ALL';

my ($dbh, $sth);

$dbh = DBI->connect("dbi:Pg:dbname=$db_name;host=$db_server;port=$db_port;", "$db_login", "$db_password", {AutoCommit => 1, RaiseError => 0, ShowErrorStatement => 1});
if (not $dbh)
{
    confess "Failed to connect to the database!";
}

my ($success_count, $failed_count) = (0, 0);
my $result;

print "Granting access ($grant on tables, $seq_grant on sequences and $func_grant on functions) to $role on tables, sequences and functions of database $db_name...\n\n";

# grant rights on tables and views
my @tables;
print "[TABLES AND VIEWS]\n";

if ($grant !~ m/SKIP/i)
{
    # retrieve public tables
    $sth  = $dbh->prepare("SELECT tablename FROM pg_tables WHERE schemaname = '$schema' AND tablename NOT LIKE 'pg_%';");
    $sth->execute();
    $result = $sth->fetchall_arrayref();
    if ($result && (ref($result) eq 'ARRAY'))
    {
        foreach my $table_data (@$result)
        {
            push @tables, $table_data->[0];
        }
    }
    else
    {
        confess "Failed to fetch list of tables!";
    }
    # retrieve public views
    $sth  = $dbh->prepare("SELECT viewname FROM pg_views WHERE schemaname = 'public';");
    $sth->execute();
    $result = $sth->fetchall_arrayref();
    if ($result && (ref($result) eq 'ARRAY'))
    {
        foreach my $view_data (@$result)
        {
            push @tables, $view_data->[0];
        }
    }
    else
    {
        confess "ERROR: Failed to fetch list of views!";
    }

    if (!@tables)
    {
        warn "WARNING: No tables or views found in public schema of the database!\n";
    }
    # grant
    foreach my $table (@tables)
    {
        # revoke previous rights
        if (!$dbh->do("REVOKE ALL ON $table FROM $role CASCADE;"))
        {
            warn "WARNING: failed to revoke previous rights!\n" . $dbh->errstr;
            ++$failed_count;
        }
        # grant rights
        if ($dbh->do("GRANT $grant ON $table TO $role;"))
        {
            # grant OK
            print " GRANT $grant ON $table TO $role ... OK\n";
            ++$success_count;
        }
        else
        {
            # grant failed
            print " GRANT $grant ON $table TO $role ... FAILED\n";
            warn "WARNING: Failed to grant rights on table or view $table!\n" . $dbh->errstr;
            ++$failed_count;
        }
    }
}
else
{
    print "Skipped!\n";
}

# grant rights on sequences
print "\n[SEQUENCES]\n";

if ($seq_grant !~ m/SKIP/i)
{
    $sth = $dbh->prepare("SELECT pc.relname FROM pg_class pc, pg_namespace pn WHERE pc.relkind = 'S' AND pc.relnamespace = pn.oid AND pn.nspname = 'public';");
    $sth->execute();
    $result = $sth->fetchall_arrayref();
    if ($result && (ref($result) eq 'ARRAY'))
    {
        if (@$result)
        {
            foreach my $seq_data (@$result)
            {
                # revoke previous rights
                if (!$dbh->do("REVOKE ALL ON SEQUENCE " . $seq_data->[0] . " FROM $role CASCADE;"))
                {
                    warn "WARNING: failed to revoke previous rights!\n" . $dbh->errstr;
                    ++$failed_count;
                }
                # grant rights
                if ($dbh->do("GRANT $seq_grant ON SEQUENCE " . $seq_data->[0] . " TO $role;"))
                {
                    # grant OK
                    print " GRANT $seq_grant ON SEQUENCE " . $seq_data->[0] . " TO $role ... OK\n";
                    ++$success_count;
                }
                else
                {
                    # grant failed
                    print " GRANT $seq_grant ON SEQUENCE " . $seq_data->[0] . " TO $role ... FAILED\n";
                    warn "WARNING: Failed to grant rights on sequence " . $seq_data->[0] . "!\n" . $dbh->errstr;
                    ++$failed_count;
                }
            }
        }
        else
        {
            warn "WARNING: No sequence found in public schema of the database!\n";
        }
    }
    else
    {
        confess "ERROR: Failed to fetch list of sequences!";
    }
}
else
{
    print "Skipped!\n";
}


# grant rights on functions
print "\n[PROCEDURES]\n";

if ($func_grant !~ m/SKIP/i)
{
    $sth = $dbh->prepare("SELECT pp.proname, ARRAY(SELECT pt.typname FROM pg_catalog.pg_type pt, (SELECT pp.proargtypes AS types_code_array) AS typenames_array CROSS JOIN generate_series(0, pp.pronargs) AS i WHERE pt.oid = types_code_array[i] ORDER BY i ASC) AS input_types, pp.proargtypes FROM pg_catalog.pg_proc pp, pg_catalog.pg_namespace pn WHERE pp.proisagg = FALSE AND pp.pronamespace = pn.oid AND pn.nspname = 'public';");
    $sth->execute();
    $result = $sth->fetchall_arrayref();
    if ($result && ('ARRAY' eq ref($result)))
    {
        if (@$result)
        {
            foreach my $procedure (@$result)
            {
                # prepare procedure args list
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

                # revoke previous rights
                if (!$dbh->do("REVOKE ALL ON FUNCTION " . $procedure->[0] . "($proc_args) FROM $role CASCADE;"))
                {
                    warn "WARNING: failed to revoke previous rights!\n" . $dbh->errstr;
                    ++$failed_count;
                }
                # grant rights
                if ($dbh->do("GRANT $func_grant ON FUNCTION " . $procedure->[0] . "($proc_args) TO $role;"))
                {
                    print " GRANT $func_grant ON FUNCTION " . $procedure->[0] . "($proc_args) TO $role ... OK\n";
                    ++$success_count;
                }
                else
                {
                    print " GRANT $func_grant ON FUNCTION " . $procedure->[0] . "($proc_args) TO $role ... FAILED\n";
                    warn "WARNING: Failed to grant rights to function " . $procedure->[0] ."!\n" . $dbh->errstr;
                    ++$failed_count;
                }
            }
        }
        else
        {
            warn "WARNING: No function found in public schema of the database!\n";
        }
    }
    else
    {
        confess "ERROR: Failed to fetch list of functions.";
    }
}
else
{
    print "Skipped!\n";
}

#...done, close database
if ($sth)
{
    $sth->finish();
}
if ($dbh)
{
    $dbh->disconnect();
}

# display end message and stats
print "\nDone!\n";
print "Successfull grants: $success_count\nFailed:             $failed_count\n\n";

# CODE END
###########


=pod

=head1 DIAGNOSTICS


=head1 AUTHORS

Valentin GUIGNON (CIRAD), valentin.guignon@cirad.fr

=head1 VERSION

Version 1.3.1

Date 03/02/2010

=head1 SEE ALSO

Chado documentation (GMOD)

=cut
