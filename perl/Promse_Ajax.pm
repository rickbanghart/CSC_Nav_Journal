package Apache::Promse_Ajax;
# File: Apache/Promse_Ajax.pm

use CGI;
use Apache::Promse;
use strict;
sub start_page {
    my ($r) = @_;
    print $r->header(-type=>'text/xml');
    # print $r->start_html(-title=>'ajax testing');
    return 'ok';
}
sub end_page {
    my ($r) = @_;
    print $r->end_html();
    return 'ok';
}

sub handler {
    my $r = new CGI;
    my $dbh = &Apache::Promse::db_connect();
    &Apache::Promse::validate_user($r);
    &Apache::Promse::logout($r);
    &start_page($r);
    $r->print('<?xml version="1.0" ?>'."\n");
    if ($r->param('graphswap')) {
        if ($r->param('graphswap') eq 2) {
            $r->print('<imagename>');
            $r->print('images/Tools.gif');
            $r->print('</imagename>');
        } else {
            $r->print('<imagename>');
            $r->print('images/star.gif');
            $r->print('</imagename>');
        }
    } else {
        $r->print('<comment>'."\n");
        $r->print('<content>'."\n");
        $r->print('COMPLETELY DIFFERENT '.$r->param('counter')."\n");
        $r->print('</content>'."\n");
        $r->print('<content>'."\n");
        $r->print('something new'."\n");
        $r->print('</content>'."\n");
        $r->print('</comment>'."\n");
    }
}
1;
