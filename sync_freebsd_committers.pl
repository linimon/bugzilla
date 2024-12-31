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

use lib qw(. lib);

use Net::LDAP;
use Bugzilla;
use Bugzilla::User;

my $quiet = 0;
my $dbh = Bugzilla->dbh;

my %ldap_users;

###
# Get current bugzilla users
###
my %bugzilla_users = %{ $dbh->selectall_hashref(
    'SELECT lower(login_name) AS new_login_name, userid, realname, disabledtext ' .
    'FROM profiles', 'new_login_name') };

foreach my $login_name (keys %bugzilla_users) {
    # remove whitespaces
    $bugzilla_users{($login_name)}{'realname'} =~ s/^\s+|\s+$//g;
}

###
# Get current LDAP users
###
my $LDAPserver = Bugzilla->params->{"LDAPserver"};
if ($LDAPserver =~ ",") {
    $LDAPserver =~ s/,.*//;
}
if ($LDAPserver eq "") {
   print "No LDAP server defined in bugzilla preferences.\n";
   exit;
}

my $LDAPconn;
if($LDAPserver =~ /:\/\//) {
    # if the "LDAPserver" parameter is in uri scheme
    $LDAPconn = Net::LDAP->new($LDAPserver, version => 3);
} else {
    my $LDAPport = "389";  # default LDAP port
    if($LDAPserver =~ /:/) {
        ($LDAPserver, $LDAPport) = split(":",$LDAPserver);
    }
    $LDAPconn = Net::LDAP->new($LDAPserver, port => $LDAPport, version => 3);
}

if(!$LDAPconn) {
   print "Connecting to LDAP server failed. Check LDAPserver setting.\n";
   exit;
}
my $mesg;
if (Bugzilla->params->{"LDAPbinddn"}) {
    my ($LDAPbinddn,$LDAPbindpass) = split(":",Bugzilla->params->{"LDAPbinddn"});
    $mesg = $LDAPconn->bind($LDAPbinddn, password => $LDAPbindpass);
}
else {
    $mesg = $LDAPconn->bind();
}
if($mesg->code) {
   print "Binding to LDAP server failed: " . $mesg->error . "\nCheck LDAPbinddn setting.\n";
   exit;
}

# We've got our anonymous bind;  let's look up the users.
$mesg = $LDAPconn->search( base   => Bugzilla->params->{"LDAPBaseDN"},
                           scope  => "sub",
                           filter => '(&(' . Bugzilla->params->{"LDAPuidattribute"} . "=*)" . Bugzilla->params->{"LDAPfilter"} . '(objectClass=freebsdAccount)(gidNumber=493))',
                         );
                         

if(! $mesg->count) {
   print "LDAP lookup failure. Check LDAPBaseDN setting.\n";
   exit;
}
   
my %val = %{ $mesg->as_struct };

while( my ($key, $value) = each(%val) ) {

   my @login_name = @{ $value->{"uid"} };
   my @realname  = @{ $value->{"cn"} };

   # no mail entered? go to next
   if(! @login_name) { 
      print "$key has no valid mail address\n";
      next; 
   }

   # no cn entered? use uid instead
   if(! @realname) { 
      print "$key has no real name\n";
      next; 
   }
  
   my $login = shift @login_name;
   my $real = shift @realname;
   utf8::decode($real);
   $login .= '@FreeBSD.org';
   $ldap_users{$login} = { realname => $real };
}

my %create_users;

while( my ($key, $value) = each(%ldap_users) ) {
  $key = lc($key);
  if(!defined $bugzilla_users{$key}){
    next if ($value->{realname} =~ m/\s+user\s*$/i);
    $create_users{$key} = $value;
  }
}

while( my ($key, $value) = each(%create_users) ) {
    $key =~ s/freebsd.org/FreeBSD.org/ig;
    my $realname = $value->{'realname'};
    print "New committer: $realname <$key>\n";
    Bugzilla::User->create({
        login_name => $key, 
        realname   => $value->{'realname'},
        cryptpassword   => '*'});
}
