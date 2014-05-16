#!/usr/bin/perl

=pod

=head1 NAME

update_cv.pl - Chado CV updater

=head1 SYNOPSIS

    update_cv.pl

=head1 REQUIRES

Perl5, Chado database with admin access

=head1 DESCRIPTION

This script can be used to update one or more CV in a CHADO database.

=cut

use strict;
use warnings;
use Readonly;
use Carp qw (cluck confess croak);
use Pod::Usage;
use Error qw(:try);

use DBI;

# used to hide passwords entered by the user
our $term_readkey_loaded = 0;
eval
{
    require Term::ReadKey;
    import Term::ReadKey;
    $term_readkey_loaded = 1;
};
$| = 1;



# Script global constants
##########################

=pod

=head1 CONSTANTS

B<$DEBUG>: (boolean)

Default debug mode.

B<$UPDATE_CV_LOG>: (string)

filename of the log file for CV update.

B<$UPDATE_CV_ERROR_LOG>: (string)

filename of the error log file for CV update.

B<$AUTOCREATE_MISSING_CV_DEFAULT>: (boolean)

Default value for autocreating missing CV. If set to a true value, missing CV
will be created automatically otherwise the update process will warn the user
for each missing CV.

B<$AUTOCREATE_MISSING_CVTERM_DEFAULT>: (boolean)

Default value for autocreating missing CV terms. If set to a true
value, missing CV term will be created otherwise the update process
will warn the user for each missing CV term.

B<$REMOVE_OBSOLETE_CVTERM_DEFAULT>: (boolean)

Default value for removing obsolete CV terms.

B<@OPTIONS>: (array of strings)

List of configuration arguments that can be specified in command line.

B<$OPTIONS>: (string for regexp)

the same list as @OPTIONS joined to be used in a regular expression.

=cut

Readonly our $DEBUG                    => 0;

Readonly our $UPDATE_CV_LOG            => 'update_cv.log';
Readonly our $UPDATE_CV_ERROR_LOG      => 'update_cv_error.log';

Readonly our $AUTOCREATE_MISSING_CV_DEFAULT        => 1;
Readonly our $AUTOCREATE_MISSING_CVTERM_DEFAULT    => 1;
Readonly our $REMOVE_OBSOLETE_CVTERM_DEFAULT       => 1;

Readonly our @OPTIONS => qw(DB_HOST DB_PORT DB_NAME DB_LOGIN DB_PASSWORD);
Readonly our $OPTIONS => join('|', @OPTIONS);




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
            print STDERR "Invalid value! Try again...\n";
        }
        # query user
        print STDERR "$prompt_message ";
        # display default value if set
        if ((defined $default_value) && ($default_value ne ''))
        {
            print STDERR "(default: $default_value) ";
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
            print STDERR "* $default_value *\n";
        }
        if ($no_echo && $term_readkey_loaded)
        {
            print STDERR "\n";
        }
    } while (($user_value !~ m/$constraint/io)
             && ((not defined $default_value) || ($user_value ne $default_value)));

    if ($no_echo && $term_readkey_loaded)
    {
        ReadMode('restore') if $term_readkey_loaded;
    }

    return $user_value;
}


=pod

=head2 add_missing_cvterm

B<Description>: returns the ID of a newly created CV term using the provided arguments.

B<ArgsCount>: [3-4]

=over 4

=item $dbh: (object) (R)

a valid database handler.

=item $cvterm_name: (string) (R)

The CV term to create.

=item $cv_name: (string) (R)

CV name of the CV the CV term will belong to.

=item $parameters: (hash ref) (O)

A reference to a hash containing additional optional parameters as key --> value:
is_relationshiptype --> the 'is_relationshiptype' value to set in the cvterm table (default = 0)
cvterm_definition --> the definition to use in the cvterm table (default = undef)

=back

B<Return>: (integer)

the cvterm_id of the new CV term just created.

=cut

sub add_missing_cvterm
{
    # get parameters
    my ($dbh, $cvterm_name, $cv_name, $parameters) = @_;
    # parameters check
    if (!$dbh)
    {
        confess "add_missing_cvterm called without providing a database handler as 1st argument!";
    }
    if (!$cvterm_name)
    {
        confess "add_missing_cvterm called without providing a CV term name as 2nd argument!";
    }
    if (!$cv_name || (ref($cv_name)))
    {
        confess "add_missing_cvterm called without providing a valid CV name (group of CV terms) as 3rd argument!";
    }
    if (!$parameters)
    {
        $parameters = {};
    }
    elsif (ref($parameters) ne 'HASH')
    {
        confess "add_missing_cvterm called with an invalid 4th argument! It should be a hash ref for parameters.";
    }
    my $is_relationshiptype = (exists($parameters->{'is_relationshiptype'})) ? $parameters->{'is_relationshiptype'} : 0;
    my $cvterm_definition = (exists($parameters->{'cvterm_definition'})) ? $parameters->{'cvterm_definition'} : '';

    # try to add missing CV term
    $cvterm_name =~ s/'/''/g;
    $cvterm_definition =~ s/'/''/g;
    # -check which source db to use
    my $db_id;
    my $sth  = $dbh->prepare("SELECT db.db_id FROM db db WHERE db.name = ?;");
    $sth->execute($cv_name);
    my $result = $sth->fetchrow_arrayref();
    if (!$result || !($db_id = $result->[0]))
    {
        $sth  = $dbh->prepare("SELECT db.db_id FROM db db WHERE db.name = 'null';");
        $sth->execute();
        $result = $sth->fetchrow_arrayref();
        if (!$result || !($db_id = $result->[0]))
        {
            confess "\nFailed to retrieve a db_id (either '$cv_name' or 'null') to insert dbxref for missing CV term!";
        }
    }
    # -create a db cross-ref
    $sth  = $dbh->do("INSERT INTO dbxref (db_id, accession, version, description) VALUES ($db_id, ?, '', ?);", undef, $cvterm_name, $cvterm_definition);
    # -retrieve the dbxref_id
    $sth  = $dbh->prepare("SELECT dbxref_id FROM dbxref WHERE accession = E'$cvterm_name' AND db_id = $db_id;");
    $sth->execute();
    $result = $sth->fetchrow_arrayref();
    my $dbxref_id;
    if (!$result || !($dbxref_id = $result->[0]))
    {
        confess "\nFailed to insert a database cross-ref for missing CV term '$cvterm_name'!";
    }
    # -add CV term
    my $cv_name_query = "cv.name = '$cv_name'";
    $sth  = $dbh->do("INSERT INTO cvterm (cv_id, name, definition, dbxref_id, is_obsolete, is_relationshiptype) SELECT cv.cv_id, ?, ?, $dbxref_id, 0, $is_relationshiptype FROM cv cv WHERE $cv_name_query ORDER BY cv.cv_id ASC LIMIT 1;", undef, $cvterm_name, $cvterm_definition);

    # -retrieve inserted CV term
    $sth  = $dbh->prepare("SELECT ct.cvterm_id FROM cvterm ct, cv cv WHERE ct.name = E'$cvterm_name' AND cv.cv_id = ct.cv_id AND $cv_name_query;");
    $sth->execute();
    $result = $sth->fetchrow_arrayref();
    if (!$result || (ref($result) ne 'ARRAY') || !@$result)
    {
        confess "Failed to retrieve cvterm_id of CV term '$cvterm_name' ($cv_name)!";
    }
    return $result->[0];
}



=pod

=head2 update_cvterm

B<Description>: update the requested CV term.

B<ArgsCount>: [3-4]

=over 4

=item $dbh: (object) (R)

a valid database handler.

=item $cvterm_name: (string) (R)

The CV term to find.

=item $cv_name: (string) (R)

the CV name of the CV the CV term should belong to.

=item $parameters: (hash ref) (O)

A reference to a hash containing additional optional parameters as key --> value:
is_relationshiptype --> the 'is_relationshiptype' value to set in the cvterm table (default = 0)
cvterm_definition   --> the definition to use in the cvterm table (default = undef)
auto_create_cvterm  --> will only create missing CV term if this value is non-zero

=back

B<Return>: (integer)

1 if the CV term was not found and created.
0 if the CV term was found and updated.
-1 if the CV term was not found and was not created.

=cut

sub update_cvterm
{
    # get parameters
    my ($dbh, $cvterm_name, $cv_name, $parameters) = @_;
    # parameters check
    if (!$dbh)
    {
        confess "update_cvterm called without providing a database handler as 1st argument!";
    }
    if (!$cvterm_name)
    {
        confess "update_cvterm called without providing a cv term name as 2nd argument!";
    }
    if (!$cv_name)
    {
        confess "update_cvterm called without providing a cv name as 3rd argument!";
    }
    if (!$parameters)
    {
        $parameters = {};
    }
    elsif (ref($parameters) ne 'HASH')
    {
        confess "update_cvterm called with an invalid 4th argument! It should be a hash ref for parameters.";
    }
    my $is_relationshiptype = (exists($parameters->{'is_relationshiptype'})) ?  $parameters->{'is_relationshiptype'} : 0;
    my $cvterm_definition   = (exists($parameters->{'cvterm_definition'}))   ?  $parameters->{'cvterm_definition'}   : '';
    my $auto_create_cvterm  = (exists($parameters->{'auto_create_cvterm'}))  ?  $parameters->{'auto_create_cvterm'}  : $AUTOCREATE_MISSING_CVTERM_DEFAULT;

    
    my $cvterm_status = -1;
    my $sth  = $dbh->prepare("SELECT ct.cvterm_id, ct.definition FROM cvterm ct, cv cv WHERE ct.name = ? AND cv.cv_id = ct.cv_id AND cv.name = ?;");
    $sth->execute($cvterm_name, $cv_name);
    my $result = $sth->fetchall_arrayref();
    if ($result && (ref($result) eq 'ARRAY') && @$result)
    {
        if (1 < @$result)
        {
            warn "WARNING: More than one ID found for CVTerm '$cvterm_name' (cv: '$cv_name')!\n";
        }
        if ($result->[0]->[0] && (!defined($result->[0]->[1]) || ($result->[0]->[1] ne $cvterm_definition)))
        {
            # update CV term
            print STDERR "   * CV term '$cvterm_name' updated\n";
            $dbh->do("UPDATE cvterm SET definition = E'$cvterm_definition', is_relationshiptype = '$is_relationshiptype' WHERE cvterm_id = " . $result->[0]->[0] . ";");
        }
        else
        {
            print STDERR "   * CV term '$cvterm_name' unchanged\n";
        }
        $cvterm_status = 0;
    }
    else
    {
        # check if term could be created
        if ($auto_create_cvterm && (add_missing_cvterm($dbh, $cvterm_name, $cv_name, $parameters)))
        {
            # missing CV term added
            print STDERR "   * CV term '$cvterm_name' added\n";
            $cvterm_status = 1;
        }
        else
        {
            # missing CV term not added
            print STDERR "   * Missing CV term '$cvterm_name' not added\n";
            $cvterm_status = -1;
        }
    }
    return $cvterm_status;
}


=pod

=head2 process_cv_file

B<Description>:
Process the ".txt" file associated to a CV and insert or update the CV terms.

B<ArgsCount>: [2-3]

=over 4

=item $dbh: (object) (R)

a valid database handler.

=item $cv_name: (string) (R)

the name of the CV the CV terms will belong to.

=item $parameters: (hash ref) (O)

A reference to a hash containing additional optional parameters as key --> value:
cv_definition --> the definition to use in the cvterm table (default = '')

Called sub-functions that will receive the same parameters:
process_cv_file

=back

B<Return>: (list of 4 elements)

1: the CV id.
2: the number of CV terms added.
3: the number of CV terms updated.
4: the number of CV terms that couldn't be added.

=cut

sub process_cv_file
{
    # get parameters
    my ($dbh, $cv_name, $parameters) = @_;
    # parameters check
    if (!$dbh)
    {
        confess "process_cv_file called without providing a database handler as 1st argument!";
    }
    if (!$cv_name)
    {
        confess "process_cv_file called without providing a cv name as 2nd argument!";
    }
    if (!$parameters)
    {
        $parameters = {};
    }
    elsif (ref($parameters) ne 'HASH')
    {
        confess "process_cv_file called with an invalid 3rd argument! It should be a hash ref for parameters.";
    }
    my $remove_old_cvterm = (exists($parameters->{'remove_old_cvterm'})) ?  $parameters->{'remove_old_cvterm'} : $REMOVE_OBSOLETE_CVTERM_DEFAULT;

    # retrieve CV
    my $sth  = $dbh->prepare("SELECT cv.cv_id FROM cv cv WHERE cv.name = '$cv_name';");
    $sth->execute();
    my $result = $sth->fetchrow_arrayref();
    if (!$result || (ref($result) ne 'ARRAY') || !@$result)
    {
        confess "Failed to retrieve cv_id of CV '$cv_name'!";
    }

    my ($added_cvterms, $updated_cvterms, $not_added_cvterms, $removed_old_cvterms) = (0, 0, 0, 0);
    my %valid_cvterms = (); # hash of CV terms that should be kept
    # add associated CV terms from provided file if one
    # compute CV terms file name (note: the name is also computed by update_cv()!)
    my $terms_filename = $cv_name;
    $terms_filename =~ s/\W/_/g; # replace special characters
    $terms_filename .= '.txt';
    my $cvterms_fh;
    if ((-r $terms_filename) && (open($cvterms_fh, "<$terms_filename")))
    {
        foreach my $line (<$cvterms_fh>)
        {
            # make sure line is not empty
            if ($line =~ m/\w+/)
            {
                # trim term
                $line =~ s/^[\s\t\r\n]*//;
                $line =~ s/[\s\t\r\n]*$//;
                # get CV term data
                my ($cvterm_name, $cvterm_definition) = ($line =~ m/([^\t]+)\t?(.*)/);
                $parameters->{'cvterm_definition'} = $cvterm_definition;
                # try to add missing CV term
                my $update_status = update_cvterm($dbh, $cvterm_name, $cv_name, $parameters);
                if (-1 == $update_status)
                {
                    ++$not_added_cvterms;
                }
                elsif (0 == $update_status)
                {
                    ++$updated_cvterms;
                }
                elsif (1 == $update_status)
                {
                    ++$added_cvterms;
                }
                else
                {
                    cluck "WARNING: unexpected CV term update status '$update_status'!\n";
                }
                $valid_cvterms{$cvterm_name} = 1;
            }
        }
        close($cvterms_fh);
        
        # clean CV if needed
        $sth  = $dbh->prepare("SELECT ct.cvterm_id, ct.name, ct.dbxref_id FROM cvterm ct, cv cv WHERE cv.cv_id = ct.cv_id AND cv.name = '$cv_name';");
        $sth->execute();
        $result = $sth->fetchall_arrayref();
        if ($result && (ref($result) eq 'ARRAY') && @$result)
        {
            foreach my $cv_data (@$result)
            {
                if (!exists($valid_cvterms{$cv_data->[1]}))
                {
                    # remove CV term
                    if ($remove_old_cvterm)
                    {
                        print STDERR "   * Obsolete CV term '" . $cv_data->[1] . "' ";
                        if ($dbh->do("DELETE FROM cvterm WHERE cvterm_id = " . $cv_data->[0] . ";"))
                        {
                            # try to remove associated dbxref
                            $dbh->do("DELETE FROM dbxref WHERE dbxref_id = " . $cv_data->[2] . ";");
                            ++$removed_old_cvterms;
                            print STDERR "deleted\n";
                        }
                        else
                        {
                            cluck "WARNING: failed to remove obsolete CV term '" . $cv_data->[1] . "'!\n";
                        }
                    }
                    else
                    {
                        print STDERR "   * Obsolete CV term '" . $cv_data->[1] . "' kept\n";
                    }
                }
                else
                {
                    if ($DEBUG)
                    {
                        print STDERR "DEBUG: CV " . $cv_data->[1] . " not obsolete\n";
                    }
                }
            }
        }
        else
        {
            print STDERR "No CV term found (for cleaning)!\n";
        }
    }
    else
    {
        warn "WARNING: No CV term added to CV '$cv_name' because file '$terms_filename' was not found (or was not readable)!\n";
    }

    return ($result->[0], $added_cvterms, $updated_cvterms, $not_added_cvterms);
}



=pod

=head2 add_missing_cv

B<Description>:
returns the ID of a newly created CV using the provided arguments and the count
of CV terms added to that CV.
It will auto-add CV terms from an associated text file which name is
created from the CV name by replacing any non-word character by an
underscore and appending '.txt'.

B<ArgsCount>: [2-3]

=over 4

=item $dbh: (object) (R)

a valid database handler.

=item $cv_name: (string) (R)

the name of the CV to create.

=item $parameters: (hash ref) (O)

A reference to a hash containing additional optional parameters as key --> value:
cv_definition --> the definition to use in the cvterm table (default = '')

Called sub-functions that will receive the same parameters:
process_cv_file

=back

B<Return>: (list of 4 elements)

1: the CV id.
2: the number of CV terms added.
3: the number of CV terms updated.
4: the number of CV terms that couldn't be added.

=cut

sub add_missing_cv
{
    # get parameters
    my ($dbh, $cv_name, $parameters) = @_;
    # parameters check
    if (!$dbh)
    {
        confess "add_missing_cv called without providing a database handler as 1st argument!";
    }
    if (!$cv_name)
    {
        confess "add_missing_cv called without providing a cv name as 2nd argument!";
    }
    if (!$parameters)
    {
        $parameters = {};
    }
    elsif (ref($parameters) ne 'HASH')
    {
        confess "add_missing_cv called with an invalid 3rd argument! It should be a hash ref for parameters.";
    }
    my $cv_definition  = (exists($parameters->{'cv_definition'})) ?  $parameters->{'cv_definition'} : '';

    # try to add missing cv
    my $sth  = $dbh->do("INSERT INTO cv (name, definition) VALUES (?, ?);", undef, $cv_name, $cv_definition);

    # insert a db
    $sth  = $dbh->do("INSERT INTO db (name, description) VALUES (?, ?);", undef, $cv_name, $cv_definition);

    print STDERR " * Adding CV terms\n";
    return process_cv_file($dbh, $cv_name, $parameters);

}


=pod

=head2 update_cv

B<Description>:
update the specified CV. If CV is missing, prompt the user before
creating it and adding CV terms from an associated text file which name is
created from the CV name by replacing any non-word character by an
underscore and appending '.txt'.

B<ArgsCount>: [2-3]

=over 4

=item $dbh: (object) (R)

a valid database handler.

=item $cv_name: (string) (R)

the name of the CV to find.

=item $parameters: (hash ref) (O)

A reference to a hash containing additional optional parameters as key --> value:
cv_definition --> the definition to use in the cvterm table (default = '')

Called sub-functions that will receive the same parameters:
add_missing_cv, process_cv_file

=back

B<Return>: (list of 4 elements)

1: the CV id.
2: the number of CV terms added.
3: the number of CV terms updated.
4: the number of CV terms that couldn't be added.

=cut

sub update_cv
{
    # get parameters
    my ($dbh, $cv_name, $parameters) = @_;
    # parameters check
    if (!$dbh)
    {
        confess "update_cv called without providing a database handler as 1st argument!";
    }
    if (!$cv_name)
    {
        confess "update_cv called without providing a CV name as 2nd argument!";
    }
    if (!$parameters)
    {
        $parameters = {};
    }
    elsif (ref($parameters) ne 'HASH')
    {
        confess "update_cv called with an invalid 3rd argument! It should be a hash ref for parameters.";
    }
    my $auto_create_cv = (exists($parameters->{'auto_create_cv'})) ?  $parameters->{'auto_create_cv'} : $AUTOCREATE_MISSING_CV_DEFAULT;
    my $cv_definition  = (exists($parameters->{'cv_definition'})) ?  $parameters->{'cv_definition'} : undef;

    # process update
    my ($added_cvterms, $updated_cvterms, $not_added_cvterms, $removed_old_cvterms) = (0, 0, 0, 0);
    my $cv_id;
    # check if CV already exists
    my $sth = $dbh->prepare("SELECT cv.cv_id FROM cv cv WHERE cv.name = '$cv_name';");
    $sth->execute();
    my $result = $sth->fetchall_arrayref();
    # CV found?
    if ($result && (ref($result) eq 'ARRAY') && @$result)
    {
        if ($DEBUG)
        {
            print STDERR "DEBUG: CV '$cv_name' found.\n";
        }
        # it exists
        if (1 < @$result)
        {
            # more than one CV, there must be an error!
            cluck "More than one ID found for CV '$cv_name'!\n";
        }

        # update definition
        if (defined($cv_definition))
        {
            $dbh->do("UPDATE cv SET definition = E'$cv_definition' WHERE cv_id = " . $result->[0]->[0] . ";");
        }

        # add/remove CV terms
        print STDERR " * Updating CV terms\n";
        ($cv_id, $added_cvterms, $updated_cvterms, $not_added_cvterms, $removed_old_cvterms) = process_cv_file($dbh, $cv_name, $parameters);
    }
    else
    {
        # CV not found!
        if ($DEBUG)
        {
            print STDERR "DEBUG: CV '$cv_name' not found!\n";
        }
        # compute CV terms file name (note: the name is re-compuited by add_missing_cv()!)
        my $terms_filename = $cv_name;
        $terms_filename =~ s/\W/_/g; # replace special characters
        $terms_filename .= '.txt';
        # check for auto-CV
        if ($auto_create_cv
            || (prompt("WARNING: CV '$cv_name' is missing! Do you whish to create it and add associated vocabulary (from '$terms_filename' if available)? [y/n]", { constraint => '^[ynYN]$'}) =~ m/y/i))
        {
            # try to add missing cv
            print STDERR " * Adding CV '$cv_name'\n";
            ($cv_id, $added_cvterms, $updated_cvterms, $not_added_cvterms) = add_missing_cv($dbh, $cv_name, $parameters);
        }
        else
        {
            warn " # Missing CV '$cv_name' not added!\n";
        }
    }
    return ($cv_id, $added_cvterms, $updated_cvterms, $not_added_cvterms);
}




# Script options
#################

=pod

=head1 OPTIONS

    update_cv.pl [--create_cv | --no_create_cv] [--create_cvterm | --no_create_cvterm] [--no_remove_old_cvterm | --remove_old_cvterm]
                 <-cv=CVNAME> [-cv=CVNAME] ...
                 [DB_HOST=host]
                 [DB_PORT=chado_port]
                 [DB_NAME=chado_db_name]
                 [DB_LOGIN=postgres_account]
                 [DB_PASSWORD=postgres_account_password]

=head2 Parameters

=over 4

=item B<--[no_]create_cv>:

if this parameter is used, each missing CV will [or will not] be created.

=item B<--[no_]create_cvterm>:

if this parameter is used, each missing CV term will [or will not] be created.

=item B<--[no_]remove_old_cvterm>:

if this parameter is used, each CV term wich is not in the provided CV text file
will [or will not] be removed.

=item B<-cv=CVNAME>:

Name of the CV to update. A file called "CVNAME.txt" (where "CVNAME" is the CV
name) should be provided in current directory. That file should contain the list
of CV terms of the CV. Each line should begin by a CV term name followed by a
tabulation and the CV term description.
The "-cv" argument can be used more than once.

=item B<DB_HOST> (string):

Server name where the Chado database is installed.

=item B<DB_PORT> (string):

PostgreSQL port used by the Chado database.

=item B<DB_NAME> (string):

Name used by the Chado database.

=item B<DB_LOGIN> (string):

Super-user login to the Chado database.

=item B<DB_PASSWORD> (string):

Super-user password to the Chado database.

=back

=cut


# CODE START
#############

# Init parameters
my %options;
my $auto_create_cv     = $AUTOCREATE_MISSING_CV_DEFAULT;
my $auto_create_cvterm = $AUTOCREATE_MISSING_CVTERM_DEFAULT;
my $remove_old_cvterm  = $REMOVE_OBSOLETE_CVTERM_DEFAULT;
my @cv_to_update       = ();

my @argv = @ARGV;
@ARGV = ();

print STDERR "\n Chado CV Updater \n##################\n\n";

# process script arguments
foreach (@argv)
{
    # check for help
    if (m/^(?:--?(?:h(?:elp)?)|\?)$/i)
    {
        print STDERR <<HELP_END;

You can provide one or more of the options DB_HOST, DB_PORT DB_NAME, DB_LOGIN
or DB_PASSWORD as in "DB_HOST=chado.host.org".

DB_HOST is the server name where the Chado database is hosted.

DB_PORT is the PostgreSQL port used for the database.

DB_NAME is the name of the Chado database.

DB_LOGIN is the Chado administrator account.

DB_PASSWORD is the Chado administrator account password.
                     
HELP_END
        pod2usage(1);
    }
    elsif (/^--?create_cv$/i)
    {
        # no_create_cv
        $auto_create_cv = 1;
    }
    elsif (/^--?no_create_cv$/i)
    {
        # no_create_cv
        $auto_create_cv = 0;
    }
    elsif (/^--?create_cvterm$/i)
    {
        # auto_create_cvterm
        $auto_create_cvterm = 1;
    }
    elsif (/^--?no_create_cvterm$/i)
    {
        # auto_create_cvterm
        $auto_create_cvterm = 0;
    }
    elsif (/^--?remove_old_cvterm$/i)
    {
        # remove_old_cvterm
        $remove_old_cvterm = 1;
    }
    elsif (/^--?no_remove_old_cvterm$/i)
    {
        # remove_old_cvterm
        $remove_old_cvterm = 0;
    }
    elsif (/^-cv=(.*)$/i)
    {
        # add to CV list
        push(@cv_to_update, $1);
    }
    elsif (/^-(.*)/)
    {
        # unrecognized parameter
        warn "\nInvalid parameter: '-$1'!\n\n";
        pod2usage(1);
    }
    elsif (/($OPTIONS)=(.+)/og)
    {
        # extract parameters set from command line
        $options{$1} = $2;
    }
    else
    {
        push @ARGV, $_;
    }
}


if (!@cv_to_update)
{
    pod2usage(1);
    confess "ERROR: no CV to update!";
}

my $dbh;
try
{
    do
    {
        $options{DB_HOST}        ||= prompt('On which server is Chado installed?', { default => 'localhost'});
        $options{DB_PORT}        ||= prompt('What port is used?', { default => '5432'});
        $options{DB_NAME}        ||= prompt('What is the name of the database where Chado is installed?', { default => 'chado'});
        $options{DB_LOGIN}       ||= prompt('What is the admin login for Chado (PostgreSQL account)?', { default => 'postgres'});
        $options{DB_PASSWORD}    ||= prompt("Please enter the password to connect to Chado (as $options{DB_LOGIN}):", { no_echo => 1});

        # connect to Chado database to retrieve the ID of some CV terms and DBXRef
        $dbh = DBI->connect("dbi:Pg:dbname=$options{DB_NAME};host=$options{DB_HOST};port=$options{DB_PORT};", "$options{DB_LOGIN}", "$options{DB_PASSWORD}");
        if (not $dbh)
        {
            print "Failed to connect to Chado Database!\n";
            # clear parameters to retry
            $options{DB_HOST}     = undef;
            $options{DB_PORT}     = undef;
            $options{DB_NAME}     = undef;
            $options{DB_LOGIN}    = undef;
            $options{DB_PASSWORD} = undef;
        }
    } while ((not $dbh) && prompt("Try again? [y/n]", { constraint => '^[ynYN]$'}) =~ m/y/i);
    # check if we got a database handler
    if (not $dbh)
    {
        # no DB handler, abort install
        confess "Unable to connect to database! Installation aborted.";
    }

    # start transaction
    $dbh->begin_work() or confess $dbh->errstr;
    
    print STDERR "Updating " . scalar(@cv_to_update) . " CV:\n";
    my $parameters = {
        'auto_create_cv'     => $auto_create_cv,
        'auto_create_cvterm' => $auto_create_cvterm,
        'remove_old_cvterm'  => $remove_old_cvterm,
    };
    foreach my $cv_name (@cv_to_update)
    {
        # update CV
        print STDERR "-$cv_name\n";
        my ($cv_id, $added_cvterms, $updated_cvterms, $not_added_cvterms, $removed_old_cvterms) = update_cv($dbh, $cv_name, $parameters);
        if ($added_cvterms)
        {
            print STDERR " Added $added_cvterms CV terms\n";
        }
        if ($updated_cvterms)
        {
            print STDERR " Updated $updated_cvterms CV terms\n";
        }
        if ($removed_old_cvterms)
        {
            print STDERR " Removed $removed_old_cvterms old CV terms\n";
        }
        if ($not_added_cvterms)
        {
            print STDERR " WARNING: $added_cvterms CV terms were not added!\n";
        }
        print STDERR "\n";
    }
    print STDERR "Done!\n";

    # close database
    if ($dbh)
    {
        $dbh->commit() or confess $dbh->errstr;
        $dbh->disconnect();
    }

    print "\n";
    exit(0);
}
otherwise
{
    my $e = shift;
    print STDERR "\nAn error occurred:\n" . $e->text() . "\n";
    print "\n";
    if ($dbh)
    {
        $dbh->rollback();
    }
    exit(1);
};




=pod

=head1 AUTHORS

Valentin GUIGNON (CIRAD), valentin.guignon@cirad.fr

=head1 VERSION

Version 1.0.1

Date 11/02/2011

=head1 SEE ALSO

Chado documentation.

=cut
