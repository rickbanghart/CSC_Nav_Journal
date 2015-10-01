package Apache::Logout;
# File: Apache/Logout.pm

use CGI;
use Apache::Promse;
use strict;
sub handler {
my $r = new CGI;
&Apache::Promse::validate_user($r);
&Apache::Promse::logout($r);
$Apache::Promse::env{'token'} = "";
&Apache::Promse::top_of_page_menus($r);
# Could enter with fields set or to start setting fields

$r->print('<p class="content" align = left><font size ="+1"><strong>You have now logged out of VPD.</strong></font></p>'."\n");
$r->print('<p class="content" align = left><font size ="+1">If you wish to login again, please click <a href="/promse/login">here</a></font></p>'."\n");
$r->print('<p class="content" align = left><font size ="+1"><strong>Have a wonderful day!</strong></font></p>'."\n");
$r->print('<p class="content"><br/>'."\n");
$r->print('<br/><br/><br/><br/><br/><br/><br/><br/>'."\n");
$r->print('<br/></p>'."\n");
&Apache::Promse::footer;
}
1;
