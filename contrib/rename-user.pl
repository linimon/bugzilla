#!/usr/local/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

=head1 NAME

rename-user.pl - Merge two user accounts.

=head1 SYNOPSIS

 This script moves activity from one user account to another.
 Specify the two accounts on the command line, e.g.:

 ./rename-user.pl old_account@foo.com new_account@bar.com
 or:

 Notes: - the new account should not exist

=cut

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::User;

use Getopt::Long;
use Pod::Usage;

my $dbh = Bugzilla->dbh;

# Display the help if called with --help or -?.
my $help  = 0;
my $result = GetOptions("help|?" => \$help);
pod2usage(0) if $help;


# Make sure accounts were specified on the command line and exist.
my $old = $ARGV[0] || die "You must specify an old user account.\n";
my $old_id;
trick_taint($old);
$old_id = $dbh->selectrow_array('SELECT userid FROM profiles
                                  WHERE login_name = ?',
                                  undef, $old);

if ($old_id) {
    print "OK, old user account $old found; user ID: $old_id.\n";
}
else {
    die "The old user account $old does not exist.\n";
}

my $new = $ARGV[1] || die "You must specify a new user account.\n";
my $new_id;
trick_taint($new);
$new_id = $dbh->selectrow_array('SELECT userid FROM profiles
                                  WHERE login_name = ?',
                                  undef, $new);

if ($new_id) {
    die "The new user account $new exists; user ID: $new_id.\n";
}

$dbh->do('UPDATE profiles SET login_name = ?
           WHERE userid = ?',
          undef, ($new, $old_id));

# It's complex to determine which items now need to be flushed from memcached.
# As user merge is expected to be a rare event, we just flush the entire cache
# when users are merged.
Bugzilla->memcached->clear_all();

print "Done.\n";
