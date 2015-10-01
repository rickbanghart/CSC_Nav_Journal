# $Id: Login.pm,v 1.14 2009/02/01 18:04:38 banghart Exp $
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


package Apache::Login;
# File: Apache/Login.pm
use strict;
use Apache::Constants qw(:common);
#!/usr/bin/perl 
use CGI;
use Apache::Promse;
sub enter_new_password {
    my ($r) = @_;
	my $username = $r->param('username');
	my %fields;
	my $output;
	%fields  = ('action' => 'updatepassword',
			'username' => $username);
    $output = qq~
	<form action="login" method="post">
    <div style="font-size:18px;color:#004400:margin-bottom:10px;">
		Resetting password - Please enter your new password and confirmation.
	</div>
	<div style="font-size:14px;margin-top:10px">
		Your new password:
    </div>
	<div>
	
		<input type=password name=password1 />
	</div>
	<div style="font-size:14px">
		And again:
	</div> 
	<div>
		<input type=password name=password2 />
	</div>
	<div style="margin-top:10px">
        <input type="submit" style="background-color:#88ff88;padding:5px;" value="Update Password" />
    </div>
~;
	$output .= &Apache::Promse::hidden_fields(\%fields);
	$output .= '';
    $r->print($output);
    my %fields = ('action' => 'emailresetpassword');
    $r->print(&Apache::Promse::hidden_fields(\%fields));
    $r->print('</form>'."\n");
    
}
sub footer {
    my ($r) = @_;
    $r->print('</div>'."\n"); # close interiorContent
    # $r->print("</div>"); # close  mainColumn 
          
    my $output = q~
        <div id="wrapperFooter">
            <hr />
            
            <p>
                        </p>
         </div>
         </div>
         
~;
    $r->print($output);
    $r->print('</div>'."\n"); # close wrapperColumn
    $r->print('</body>'."\n");
    $r->print('</html>'."\n");      
    return ();
}
sub login_form {
    my ($r) = @_;
    $r->print('<div id="interiorHeader">'."\n");
    $r->print('<h2 align = left>Professional Development: Virtual Professional Development</h2>'."\n");
    $r->print('<h3 align = left>PROM/SE Login</h3>'."\n");
    $r->print('</div>'."\n");
    $r->print('<form name="form1" method="post" action="home">'."\n");
    $r->print('<fieldset>'."\n");
    $r->print('<label>User Name</label>'."\n");
#   $r->print('<h6 align =right><a href="/webpages/llab_intro_Dec_05.html">Info for LessonLab users</a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</h6>'."\n");
    $r->print('<input name="username" type="text" id="username" value="" size="25" />'."\n");
    $r->print('<label>Password</label>'."\n");
    $r->print('<input name="password" type="password" id="password2" value="" size="25" />'."\n");
    $r->print('<label><a href="/promse/login?action=resetpassword">Forgot your user name or password?</a></label><br />'."\n");
    $r->print('<label>New to user? Please click to <a href="/promse/register?target=new">register</a></label>'."\n");
    $r->print('<label>Please login</label>');
    $r->print('<p><input class="redButton" name="login" type="submit" id="login"  value="  LOG IN  " size ="25" />'."\n");
    $r->print('</fieldset>'."\n");
    $r->print('<input type="hidden" name="menu" value="home" />');
    $r->print('</form>');
    $r->print('<br /><br />'."\n");
}    
sub password_reset_form {
    my ($r) = @_;
    my $output = qq~
    <div id="interiorHeader" style="padding-top:10px;margin-top:10px;font-size:36px">
    Center for the Study of Curriculum<br />at Michigan State University
    </div>
    <div style="font-size:18px;color:#004400:margin-bottom:10px;">
    <strong>Reset your password</strong>    </div><br/>
    <div style="font-size:18px">
    <form action="login" method="post">
    <p>Please enter your email address: <br />
    <input type="text" name="email" /><br /><br />
    <input type="submit" style="background-color:#88ff88;padding:5px;" value="Send Password Reset Email" />
    </div><br/>
    <div style="font-size:18px">
    </div>

~;
    $r->print($output);
    my %fields = ('action' => 'emailresetpassword');
    $r->print(&Apache::Promse::hidden_fields(\%fields));
    $r->print('</form>'."\n");
    $r->print('<p><a href="http://csc.educ.msu.edu/Nav" style="font-size:18px;color:#005500;">Return to Nav/J.</a>');
    
    return 'ok';
}
sub top_of_page {
    my ($r) = @_;
    print $r->header(-type => 'text/html');
    my $output = q~
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
    <html lang="en" xml:lang="en">
    <!-- Above is the Doctype for strict xhtml -->
    <head>
    <!-- Unicode encoding -->
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <title>CSC at MSU COE</title>
    <meta name="description" content="PROM/SE - Promoting rigorous outcomes in K-12 mathematics and science education" />
    <meta name="keywords" content="prom/se, PROM/SE, promse, PROMSE, K-12, K-12 mathematics, K-12 science, K-12 education, math, science" />
    <!-- Use the import to use more sophisticated css. Lower browsers (less then 5.0) do not process the import instruction, will default to structural markup -->
    <style type="text/css" media="all">@import "../_stylesheets/advanced.css";</style>
    <script src="../_scripts/general.js" type="text/javascript" charset="utf-8"></script>
    <script src="http://ajax.googleapis.com/ajax/libs/jquery/1.6.4/jquery.min.js" type="text/javascript" charset="utf-8"></script>
    <SCRIPT type="text/javascript">
    //Redirect if Mac IE
    if (navigator.appVersion.indexOf("Mac")!=-1 && navigator.appName.substring(0,9) == "Microsoft") {
    	window.location="mac_ie_note.html";
    }
     </SCRIPT>
    </head>
    ~;
    $r->print($output);
    $output = q~
    <body id="M" onload="onloadFunctions('Home','NULL');">
    ~;
    $r->print ($output);
    $r->print('<div id="wrapperColumn">'); 

    my $screen = 'home';
    
    $r->print('<div id="noShiftWrapper">'."\n");
    $r->print("&nbsp;");
    $r->print('<div id ="navcolumn">'."\n");
    $r->print('<br /><br /><br /><br /><br /><br /><br /><br /><br /><br />&nbsp;');
    $r->print('</div>'."\n");
    $r->print('<div id="interiorContent">'."\n");
    return ();
}    

sub handler {
    my $r = new CGI;
    &Apache::Promse::validate_user($r);
    my $jscript;
	my $output;
	my %fields;
    &top_of_page($r,$jscript);
    if ($Apache::Promse::env{'action'} eq 'resetpassword' || $r->param('target') eq 'password') {
        &password_reset_form($r);
	} elsif ($r->param('action') eq 'emailresetpassword') {
		# this action is set in the form that submits email address
		&Apache::Promse::email_password_reset($r);
	} elsif ($r->param('action') eq 'requestpasswordform') {
		# The action is set in the email message link
		$output = qq~
		    <div id="interiorHeader" style="padding-top:10px;margin-top:10px;font-size:36px">
            Center for the Study of Curriculum<br />at Michigan State University
            </div>
        ~;
        $r->print($output);
		&enter_new_password($r);
	} elsif ($r->param('action') eq 'updatepassword'){
		my $p1 = $r->param('password1');
		my $p2 = $r->param('password2');
		my $username = $r->param('username');
        $output = qq~
        <div id="interiorHeader" style="padding-top:10px;margin-top:10px;font-size:36px">
        Center for the Study of Curriculum<br />at Michigan State University
        </div>
        ~;
        $r->print($output);
		if ($p1) { # must have an entry
			if ($p1 eq $p2 ) { #the two must match
				my $qry = "UPDATE users SET password = md5('$p1') WHERE username = '$username'";
				my $result = $env{'dbh'}->do($qry);
				if ($result) {
					$r->print('<div style="padding-top:10px;margin-top:10px;font-size:18px">Your password has been reset. </div>');
				    $r->print('<div style="font-size:18px;"><a href="/Nav">Try Logging in Again</a></div>'."\n");
				}
			} else {
			    
				$r->print('<div style="font-size:18px;color:#dd0000;margin-bottom:20px;">The passwords did not match. Please try again.</div>');
				&enter_new_password($r);

			}
		} else {
			$r->print('Please enter a password in both fields.');
			&enter_new_password($r);
		}
    } else {
        &login_form($r);
        $r->print('<div class="loginContent">

    This system is in development. Over the coming months, new features will be added 
    so that teachers will have access to cutting-edge PD anytime, any place they 
    need it through the new PROM/SE VPD. Features in development include:
    <ul>
    <li>Opportunities for dialogue with other teachers and university faculty</li>
    <li>Discussions by mathematicians, scientists and educators</li>
    <li>Video of discussions of topics between mathematicians, scientist and teachers</li>

    <li>A data collection system for districts and teachers about 
    curriculum coverage with data driven feedback</li>
    <li>A case study of how to interpret the PROM/SE data</li>
    <li>Examples of student work</li>
    </ul></div>'); 
    }
    &footer($r);
    $r->delete_all();
}

1;
__END__

