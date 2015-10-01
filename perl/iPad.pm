#
# $Id: Home.pm,v 1.38 2009/02/01 18:07:59 banghart Exp $
#
# Copyright Michigan State University Board of Trustees
#
# This file is part of the PROM/SE Virtual Professional Development (VPD
# system.
#
# VPD is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# VPD is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with VPD; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# /home/httpd/html/adm/gpl.txt
#
#
# package Apache::Promse;
package Apache::iPad;
# File: Apache/Home.pm
use CGI;
use CGI::Cookie;

$CGI::POST_MAX = 900000;
use Apache::Flash;
use Apache::Promse;
use Apache::Chat;
# use vars(%env);
use strict;
use Apache::Constants qw(:common);

sub handler {
    my $r = new CGI;
    if ($r->cgi_error) {
        &Apache::Promse::top_of_page($r);
        print $r->cgi_error;
        &Apache::Promse::footer($r)
    }
    my $warning = &Apache::Promse::validate_user($r); #sets environment variables.
    print STDERR "***** \n message two \n ***** \n";
    if ($env{'target'} eq 'redirect') {
        &Apache::Promse::redirect($r);
    }
    if (($env{'username'} ne 'not_found') || ($env{'token'}=~/[^\s]/)){
        my $prefs = &Apache::Promse::get_preferences($r);
        #my $cookie_time = gmtime(time() + 600)." GMT";
        my $cookie1 = $r->cookie(-name=>'token',
                                 -value=>$env{'token'});
        #print $r->header(-cookie=>$cookie1);
        print $r->header(-type => 'text/json');
        $r->print('{"success":"logOk", "token":"'.$env{'token'}.'"}');
        #print $r->header(-type => 'text/html', -expires => 'now');
        #print $r->header(-location =>q[http://vpddev.educ.msu.edu/senchatouch/iPad/content/content.html]);
        #$r->print(&top_of_page());
    } else {
            print $r->header(-type => 'text/json');
            $r->print('{"success":"logNo"}');
            #&Apache::Promse::top_of_page($r);
            #&Apache::Promse::user_not_valid($r);

    }
    #print STDERR "\n*****  Check Point   *****\n";
    return();
}
sub top_of_page {
    my $r = @_;
    my $output = '';
    $output = <<'ENDHTML';
    <!DOCTYPE HTML>
    <html>
    <head>
    <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.6.4/jquery.min.js"></script>
    <script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.16/jquery-ui.min.js"></script>
    <script type="text/javascript" src="../_scripts/hierarchicalSelector.js"></script>
    <style type="text/css" media="all">@import "../_stylesheets/teacherJournal.css";</style>
    <script type="text/javascript">
ENDHTML
    $output .= 'var token = "' . $env{'token'} . '";' . "\n";
    $output .= 'var frameworkid = 1;' . "\n";
    $output .= <<'ENDHTML';
        var ajaxData = {token: token,
                        action: "getframework",
                        frameworkid: frameworkid
        };

    var frameworkXML;
    var frameworkSelector;
    $(document).ready(function(){
        var ajaxData = {token: token,
                        action: "getframework",
                        frameworkid: frameworkid
        };
        var pageOutput = '';
        var strandArray = {};
        var counter = 0;
        var rowClass = 'rowAltLight';
        var jqxhr = $.ajax({
            url: "http://vpddev.educ.msu.edu/promse/flash",
            data: ajaxData,
            dataType: "xml",
            success: function(xml) {
                frameworkXML = $(xml);
				frameworkSelector = new hierarchicalSelector(frameworkXML);
                //$(xml).find('node').filter('[title=Domain]').each(function(){
                $(xml).find('grade').each(function(){
                    var thisID = $(this).attr('gradelevel');
                    if (! (thisID in strandArray)) {
                        rowClass = rowClass=='rowAltLight'?'rowAltDark':'rowAltLight';
                    }
                })
            }
        })
 });
</script>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<title>Teacher's Journal</title>
</head>

<body>
<div id="hsContainer">
    <div id="headerContainer">
    </div>
    <div id="scrollContainer">
        <div id="scrollingRows">
			<!--- listItems go here -->
        </div>
    </div>
	<div id="animationLayer">
	</div>
</div>
</body>
</html>
ENDHTML
#return ($output);
}
1;