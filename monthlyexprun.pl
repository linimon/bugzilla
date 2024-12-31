#!/usr/local/bin/perl -w

use strict;
use warnings;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Mailer;
use Bugzilla::Constants;
use Bugzilla::Util;
use Email::MIME;

my $urlbase = Bugzilla->params->{'urlbase'};

my $MAIL_TXT_HEADER = "To view an individual PR, use:
  ${urlbase}show_bug.cgi?id=(Bug Id).
";

my $MAIL_HTML_HEADER = '<pre style="font-family: monospace;">';

my $MAIL_COMMON = "
The following is a list of exp-runs completed during the last month.

Date       |    Bug Id | Description
-----------+-----------+---------------------------------------------------
%s
%d exp-runs completed during the last month
";

my $MAIL_TXT_FOOTER = "";

my $MAIL_HTML_FOOTER = '</pre>';

my $TBLROW = "%-10s | %9s | %-50.49s\n";
my $TBLROW_HTML = "%-10s | <a href=\"%s\">%9s</a> | <a href=\"%s\">%s</a>\n";

# We're a non-interactive user
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
# Get the db conection and query the db directly.
my $dbh = Bugzilla->dbh;

# Report on flags changed in the last month
my $first = $dbh->sql_date_math("date_trunc('month', NOW())", '-', '1', 'MONTH');
my $last = "date_trunc('month', NOW())";

my $query = q{
SELECT DISTINCT
  bugs.bug_id, bugs.short_desc, bugs.bug_status,
  TO_CHAR(flags.modification_date::date, 'YYYY-MM-DD') AS modification_date
FROM
  bugs
  JOIN flags ON (bugs.bug_id = flags.bug_id AND flags.status = '+')
  JOIN flagtypes ON (flags.type_id = flagtypes.id)
WHERE
  flagtypes.name IN (?) AND } . 
  $dbh->sql_to_days("modification_date") . " >= " .
  $dbh->sql_to_days("(".$first.")") . " AND " .
  $dbh->sql_to_days("modification_date") . " < " .
  $dbh->sql_to_days("(".$last.")") .
" ORDER BY modification_date, bugs.bug_id;";

my $bugs = $dbh->selectall_arrayref(
    $query,
    undef,
    'exp-run');

# Prepare report for email
my $tblbugs = "";
my $tblbugs_html = "";
my $bugcount = scalar(@$bugs);
foreach my $bug (@$bugs) {
    my ($id, $desc, $status, $modified) = @$bug;
    $tblbugs .= sprintf($TBLROW, $modified, $id, $desc);
    my $desc_cut = html_quote(substr($desc, 0, 49));
    my $url = "${urlbase}show_bug.cgi?id=$id";
    $tblbugs_html .= sprintf($TBLROW_HTML, $modified, $url, $id, $url, $desc_cut);
    $tblbugs_html =~ s/(<a href=".*?">)(\s+)/$2$1/;
}

my $body_txt = $MAIL_TXT_HEADER;
$body_txt .= sprintf($MAIL_COMMON, $tblbugs, $bugcount);
$body_txt .= $MAIL_TXT_FOOTER;

my $body_html = $MAIL_HTML_HEADER;
$body_html .= sprintf($MAIL_COMMON, $tblbugs_html, $bugcount);
$body_html .= $MAIL_HTML_FOOTER;

# parts should go from least rich to most rich format
my @parts = (
    Email::MIME->create(
        attributes => {
            content_type => "text/plain",
            charset => "UTF-8"
        },
        body => $body_txt
    ),
    Email::MIME->create(
        attributes => {
            content_type => "text/html",
            charset => "UTF-8"
        },
        body => $body_html
    ),
);

my $mailmsg = Email::MIME->create(
    header_str => [
        From => 'bugzilla-noreply@FreeBSD.org',
        To => [ 'portmgr@FreeBSD.org' ],
        Subject => "Exp-runs completed during the last month",
    ],
    attributes => {
        content_type => "multipart/alternative"
    },
    parts      => [ @parts ],
);

# Send the mail via the bugzilla configuration.
#print $mailmsg->as_string;
MessageToMTA($mailmsg, 1);
