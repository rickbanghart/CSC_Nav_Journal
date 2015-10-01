#
# $Id: Authenticate.pm,v 1.12 2009/02/01 18:08:36 banghart Exp $
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
package Apache::Authenticate;
# File: Apache/Authenticate.pm
#!/usr/bin/perl 
use CGI;
use Apache::Promse;
use vars qw(%env);
use strict;
use Apache::Constants qw(:common);
use Apache::Design;
use DBI;
# use Net::LDAP;
use Net::HTTP;
sub align_vpd_lessonlab {
    my ($r) = @_;
    $r->print('<a href="admin?token='.$Apache::Promse::env{'token'}.'&amp;target=addvpdrecord">Add VPD Record</a>');
    return 'ok';
    
}
sub save_new_vpd_record {
    my ($r) = @_;
    my %fields;
    my $msg;
    $fields{'PROMSE_ID'} = &Apache::Promse::fix_quotes($r->param('promseid'));
    $fields{'FirstName'} = &Apache::Promse::fix_quotes($r->param('firstname'));
    $fields{'LastName'} = &Apache::Promse::fix_quotes($r->param('lastname'));
    $fields{'Email'} = &Apache::Promse::fix_quotes($r->param('email'));
    $fields{'State'} = &Apache::Promse::fix_quotes($r->param('state'));
    $fields{'Password'} = &Apache::Promse::fix_quotes($r->param('password'));
    $fields{'username'} = &Apache::Promse::fix_quotes($r->param('username'));
    $fields{'subject'} = &Apache::Promse::fix_quotes($r->param('subject'));
    my $user_id = &Apache::Promse::save_record('users',\%fields,'id');
    if ($user_id) {
        if ($r->param('locationid') eq "0") {
            %fields = ("user_id" => $user_id,
                    "loc_id" => $r->param('districtid'));
        } else {
            %fields = ("user_id" => $user_id,
                    "loc_id" => $r->param('locationid'));
        }
        &Apache::Promse::save_record('user_locs',\%fields);
		foreach my $tj_class($r->param('tjclassid')) {
			%fields = ('user_id' => $user_id,
					'class_id' => $tj_class);
			&Apache::Promse::save_record('tj_user_classes',\%fields);
		}
    }
    # $r->print('Save new VPD returned '.$user_id." as userid");
    if ($user_id) {
        &Apache::Promse::update_user_roles($r,$user_id);
    } else {
        $msg = "Duplicate user name";
    }
    return ($msg);
}
sub district_school_select_javascript {
    my ($for_profile_edit) = @_;
    # needs setting for profile editing: don't retrieve javascript in the
    # returned schools pulldown, but include the "None" School
    my $for_profile_request = $for_profile_edit?"includenone=1;nojavascript=1":"";
    my $javascript = qq ~
    <script type="text/javascript">
        var token="$Apache::Promse::env{'token'}";
        
        function ajaxFunction() {
            document.getElementById("locationid").disabled=true;
            var xmlHttp;
            try {
                // Firefox, Opera 8.0+, Safari
                xmlHttp=new XMLHttpRequest();
            }
            catch (e) {
                // Internet Explorer
                try {
                    xmlHttp=new ActiveXObject("Msxml2.XMLHTTP");
                }
                catch (e) {
                    try {
                        xmlHttp=new ActiveXObject("Microsoft.XMLHTTP");
                    }
                    catch (e) {
                        alert("Your browser does not support AJAX!");
                        return false;
                    }
                }
            }
            xmlHttp.onreadystatechange = function() {
                if(xmlHttp.readyState==4) {
                    // Get the data from the server's response
                    var text_out;
                    var display = "";
                    xmlHttp.responseText;
                    display = xmlHttp.responseText;
                    document.getElementById("schoolselectspan").innerHTML=display;
                    document.getElementById("locationid").disabled=false;    
                    // timedMsg();     
                }
            }
            var districtid = document.getElementById("districtid").value;
            xmlHttp.open("GET","/promse/flash?token="+token+";includenone=true;action=getdistrictschools;$for_profile_request;districtid="+districtid,true);
            xmlHttp.send(null);
        }        
        function timedMsg() {
            var t=setTimeout("ajaxFunction()",5000)
        }    

    </script>
    ~;
    return($javascript);
}
sub add_vpd_user_form {
    my ($r) = @_;
    # modify to allow this to be the editing form
    # so have to populate if this is an update request
    my $user_hashref;
    my $user_id = $r->param('userid')?$r->param('userid'):0;
    my $action = "saverecord"; #gets changed if we're editing user record
    my $submenu = "add"; #gets changed if we're editing user record
    my $button_message = "Add user to VPD";
    my $roles;
    if ($r->param('submenu') eq 'edituser') {
        my $dbh = &Apache::Promse::db_connect();
        my $qry = "SELECT * FROM users WHERE id = $user_id";
        my $sth = $dbh->prepare($qry);
        $sth->execute();
        $user_hashref = &Apache::Promse::get_user_profile($user_id);
        $action = "update";
        $submenu = "edituser";
        $button_message = "Edit VPD User";
        $qry = "SELECT userroles.user_id, GROUP_CONCAT(roles.role) as roles FROM roles, userroles
                WHERE userroles.role_id = roles.id
                GROUP BY userroles.user_id 
                HAVING userroles.user_id = $user_id";
        $sth = $dbh->prepare($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        $roles = $$row{'roles'};
    }
	my $tj_user_classes = $$user_hashref{'tj_user_classes'};
	#print STDERR "\n tj_user_classes has " . scalar @$tj_user_classes . " items returned from profile \n";
	#‘‘print STDERR "\n [1] item is @$tj_user_classes[1] \n";
    my $promseid = $$user_hashref{'PROMSE_ID'};
    my $firstname = $$user_hashref{'firstname'};
    my $lastname = $$user_hashref{'lastname'};
    my $email = $$user_hashref{'email'};
    my $state = $$user_hashref{'state'};
    my $username = $$user_hashref{'username'};
    my $subject = $$user_hashref{'subject'};
    my $password = $$user_hashref{'password'};
    my $loc_id = $$user_hashref{'location_id'};
    my $user_district_id = $$user_hashref{'district_id'}?$$user_hashref{'district_id'}:0;
    my %fields;
	my @classes = &Apache::Promse::get_tj_classes();
	my $classes_pulldown = &Apache::Promse::build_select('tjclassid',\@classes,$tj_user_classes,' size="1" multiple="multiple"');
    my @districts = &Apache::Promse::get_districts();
    unshift(@districts,{'None'=>0});
    my $district = $districts[0];
    my @schools = keys(%$district);
    my $district_id = $$district{$schools[0]};
    @schools = &Apache::Promse::get_schools($user_district_id);
    unshift(@schools,{'None'=>0});
    my $schools_pulldown = &Apache::Promse::build_select('locationid',\@schools,$loc_id,"");
    my $javascript ='onchange="ajaxFunction()"';
    my $district_pulldown = &Apache::Promse::build_select('districtid',\@districts,$user_district_id,$javascript);
    $r->print(&district_school_select_javascript());
    my @subjects = ({'Math'=>'Math'},{'Science'=>'Science'});
    my $subject_pulldown = &Apache::Promse::build_select('subject',\@subjects,$subject,"");
	my @roles = &Apache::Promse::get_roles();
	foreach my $role (@roles) {
		my $match = $$role{'role'};
		$$role{'checked'} = ($roles =~ m/$match/?' checked="checked" ':"");
	}
    my $teacher_checked = ($roles =~ m/Teacher/)?' checked="checked" ':"";
    my $reviewer_checked = ($roles =~ m/Reviewer/)?' checked="checked" ':"";
    my $mentor_checked = ($roles =~ m/Mentor/)?' checked="checked" ':"";
    my $tj_checked = ($roles =~ m/TJ/)?' checked="checked" ':"";
    my $editor_checked = ($roles =~ m/Editor/)?' checked="checked" ':"";
    my $admin_checked = ($roles =~ m/Administrator/)?' checked="checked" ':"";
    my $output;
    $output = qq ~
    <div class="vpdRecordForm" style="height:400px">
    <form method="post" action="admin">
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            PROM/SE ID
        </div>
        <div class="vpdRecordInput">
            <input class="vpdRecord" type="text" name="promseid" value="$promseid" />
        </div>
        <div class="vpdRecordTitle">
            District
        </div>
        <div class="vpdRecordInput">
            $district_pulldown
        </div>
        <div class="vpdRecordTitle">
            School
        </div>
        <div class="vpdRecordInput">
            <span id="schoolselectspan">$schools_pulldown</span>
        </div>
    </div>
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            TJ Class
        </div>
        <div class="vpdRecordInput">
            $classes_pulldown
        </div>
    </div>
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            Subject
        </div>
        <div class="vpdRecordInput">
            $subject_pulldown
        </div>
    </div>
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            First Name
        </div>
        <div class="vpdRecordInput">
            <input class="vpdRecord" type="text" name="firstname" value="$firstname" />
        </div>
    </div>
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            Last Name
        </div>
        <div class="vpdRecordInput">
            <input class="vpdRecord" type="text" name="lastname" value="$lastname" />
        </div>
    </div>
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            Email
        </div>
        <div class="vpdRecordInput">
            <input class="vpdRecord" type="text" name="email" value="$email" />
        </div>
    </div>
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            State
        </div>
        <div class="vpdRecordInput">
            <input class="vpdRecord" type="text" name="state" value="$state" />
        </div>
    </div>
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            Password
        </div>
        <div class="vpdRecordInput">
            <input class="vpdRecord" type="text" name="userpassword" value="$password" />
        </div>
    </div>
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            User Name
        </div>
        <div class="vpdRecordInput">
            <input class="vpdRecord" type="text" name="username" value="$username"/>
        </div>
    </div>
<div class="vpdRecordInputRow">
~;
	foreach my $role(@roles) {
		$output .= qq~
			 <div class="vpdRecordTitle">
			 	$$role{'role'}
			</div>
			<div class="vpdRecordInput">
				<input class="vpdRecord" type="checkbox" $$role{'checked'} name="role" value="$$role{'role'}" />
			</div>
		~;
	}
	$output .= qq~
	</div>
    <input class="vpdRecordButton" type="submit" value="$button_message" />
    
    ~;
    $r->print($output);
    %fields = ('menu' => 'users',
                'userid' => $user_id,
               'submenu' => $submenu,
               'action' => $action);
    $r->print(&Apache::Promse::hidden_fields(\%fields));
    $r->print('</form></div>');
    return 'ok';
        
}
sub llab_ldap_connect {
    my $ldap = (Net::LDAP->new( 'st2c2mll0d.connectria.com' ) or die "$@");
    my $mesg = $ldap->bind;
    return($ldap,$mesg);
}
sub llab_ldap_disconnect {
    my ($ldap)= @_;
    $ldap->unbind;
    return ('ok');
}
sub llab_ldap_search {
    my ($fields) = @_;
    my $filter;
    my %hits;
    my ($ldap,$mesg) = &llab_ldap_connect();
    foreach my $field_name (keys(%$fields)) {
        $filter .= '('.$field_name.'='.$$fields{$field_name}.')';
    }
    $mesg = $ldap->search( # perform a search
                        filter => "(&(objectClass=person)$filter)"
                      );
    my $entry_counter;
    foreach my $entry ($mesg->entries) {
        $entry_counter += 1;
        my $common_name = $entry->get_value('cn');
        my $mail = $entry->get_value('mail');
    }
    my $num_hits = $mesg->count();
    &llab_ldap_disconnect($ldap);
    return ($num_hits);
}

sub llab_request_head {
    my $output;
    $output = qq ~
<?xml version="1.0" encoding="UTF-8"?>
<user:WebRequest  xmlns:user="http://www.lessonlab.com/portal/request/manage/user">
    <DataEnvelope>
~;
return ($output)
}
sub llab_request_action {
    my ($action) = @_;
    my $output;
    # <!-- 0=authenticate, 1=register user, 2=update user, 3=disable user, 4=add content key -->
    $output = '<Action>'.$action.'</Action>';
    return ($output);
}
sub llab_request_body {
    my ($body) = @_;
    my $output;
    # <!-- 0=authenticate, 1=register user, 2=update user, 3=disable user, 4=add content key -->
    $output = '<user:Body>'.$body.'</user:Body>';
    return ($output);
}
sub llab_login_disable {
    my ($username, $password) = @_;
    my $output;
    $output = qq ~
    <User>
        <UserName>$username</UserName>
        <Password>$password</Password>
        <CustomerId>MISU001</CustomerId>
    </User>
    ~;
    return ($output);
}
sub llab_add_contentkey {
    my ($username, $password, $contentkey) = @_;
    my $output;
    $output = qq ~
    <User>
        <UserName>$username</UserName>
        <Password>$password</Password>
        <CustomerId>MISU001</CustomerId>
        <ContentKey>$contentkey</ContentKey>
    </User>
    ~;
    return ($output);
}
sub llab_registration {
    my ($username, $password, $firstname, $lastname, $email, $phone, $contentkey) = @_;
    my $output;
    $output = qq ~ 
<User>
    <UserName>$username</UserName>
    <Password>$password</Password>
    <CustomerId>MISU001</CustomerId>
    <FirstName>$firstname</FirstName>
    <LastName>$lastname</LastName>
    <Email>$email</Email>
    <Phone>$phone</Phone>
    <ContentKey>$contentkey</ContentKey>
</User>
    ~;
    return ($output);
}
sub llab_update {
    my ($username, $password, $firstname, $lastname, $email, $phone) = @_;
    my $output;
    $output = qq ~ 
<User>
    <UserName>$username</UserName>
    <Password>$password</Password>
    <CustomerId>MISU001</CustomerId>
    <FirstName>$firstname</FirstName>
    <LastName>$lastname</LastName>
    <Email>$email</Email>
    <Phone>$phone</Phone>
</User>
    ~;
    return ($output);
}
sub llab_response {
    my ($llab_request) = @_;
    my $output;
    my $s = Net::HTTP->new(Host => "zuma.lessonlab.com:8080") || return ("no connect");
    $s->write_request(GET => "/userService", 'User-Agent' => "Mozilla/5.0", $llab_request);
    my($code, $mess, %h) = $s->read_response_headers;
    foreach (keys(%h)) {
        $output .= $_.' == '.$h{$_}."\n";
    }
    while (1) {
        my $buf;
        my $n = $s->read_entity_body($buf, 1024);
        last unless $n;
        $output .=  $buf;
    }    
    return ($output);
}
sub llab_cn_exist {
    my ($cn) = @_;
    my ($ldap,$mesg) = &llab_ldap_connect();
    my %fields;
    $fields{'cn'} = $cn;
    my $status = &llab_ldap_search(%fields);
    return ($status);
}
sub llab_request_foot {
    my $output;
    $output = qq ~
    </DataEnvelope>
</user:WebRequest>
~;
return ($output)
}
sub login {
    my ($username,$password)=@_;
    my $llab_request = &llab_request_head();
    my %return;
    $llab_request .= &llab_request_action(0);
    $llab_request .= &llab_request_body(&llab_login_disable($username, $password));
    $llab_request .= &llab_request_foot();
    my $response = &llab_response($llab_request);
    $response =~ /<Token>(.+)<\/Token>/;
    $return{'token'} = $1;
    $response =~ /<Message>(.+)<\/Message>/;
    $return{'message'} = $1;
    $response =~ /<Status>(.+)<\/Status>/;
    $return{'status'} = $1;
    return (\%return);
}
sub register {
    my ($fields) = @_;
    my $status;
    my $llab_request;
    my $username = $$fields{'username'};
    my $password = $$fields{'password'};
    my $firstname = $$fields{'firstname'};;
    my $lastname = $$fields{'lastname'};;
    my $email = $$fields{'email'};;
    my $phone = '';
    my $contentkey = 'CoursePreview';
    # my $contentkey = 'vdpadminkey';
		# my $contentkey = 'misukey';
    $llab_request = &llab_request_head;
    $llab_request .= &llab_request_action(1);
    $llab_request .= &llab_request_body(&llab_registration($username, $password, 
                             $firstname, $lastname, $email, $phone, $contentkey));
    $llab_request .= &llab_request_foot();
    my $response = &llab_response($llab_request);
    $response =~ /<Status>(.+)<\/Status>/;
    $status = $1;
    $response =~ /<Message>(.+)<\/Message>/;
    my $message = $1;
    return ($status,$message);
}
1;
__END__
