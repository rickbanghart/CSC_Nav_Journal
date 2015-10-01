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
package Apache::Home;
# File: Apache/Home.pm
use CGI;
$CGI::POST_MAX = 900000;
use Apache::Flash;
use Apache::Promse;
use Apache::Chat;
# use vars(%env);
use strict;
use Apache::Constants qw(:common);
sub profile_display_edit {
    my ($r) = @_;
    my $profile_hashref = &Apache::Promse::get_user_profile($env{'user_id'});
    my $user_id = $env{'user_id'};
    my $url;
    # set common fields for all actions
    my %fields = ('menu'=>'preferences',
                  'submenu'=>'profile');
    my @options;
    if ($env{'action'} eq 'editbio') {
        $fields{'action'} = 'savebio';
        $r->print('<form method="post" action="">');
        $r->print('<textarea name="bio" rows="20" cols="60">');
        $r->print($$profile_hashref{'bio'});
        $r->print('</textarea>');
        $r->print('<input type="submit" value="Save Bio" />');
        $r->print(&Apache::Promse::hidden_fields(\%fields));
        $r->print('</form>');
    } elsif ($env{'action'} eq 'editpassword') {
        $fields{'action'} = 'savepassword';
        $r->print('Change your password. Enter your new password twice.');
        $r->print('<form method="post" action="">');
        $r->print('<input type="password" name="password1" /><br />');
        $r->print('<input type="password" name="password2" /><br />');
        $r->print('<input type="submit" value="Save new password" />');
        $r->print(&Apache::Promse::hidden_fields(\%fields));
        $r->print('</form>');
    } elsif ($env{'action'} eq 'editphoto') {
        $fields{'action'} = 'savephoto';
        $r->print('Upload a photo. Photos should be 100x100 pixels');
        $r->print('<form method="post" action="" enctype="multipart/form-data">');
        $r->print('<input type="file" value="Browse . . ." name="photo" /><br />');
        $r->print('<input type="submit" value="Upload New Photo" />');
        $r->print(&Apache::Promse::hidden_fields(\%fields));
        $r->print('</form>');
    } elsif ($env{'action'} eq 'editname') { 
        $fields{'action'} = 'savename';   
        $r->print('<form method="post" action="">');
        $r->print('<input type="text" value="'.$$profile_hashref{'firstname'}.'" name="firstname" /><br />');
        $r->print('<input type="text" value="'.$$profile_hashref{'lastname'}.'" name="lastname" /><br />');
        $r->print('<input type="submit" value="Save Name" />');
        $r->print(&Apache::Promse::hidden_fields(\%fields));
        $r->print('</form>');
    } elsif ($env{'action'} eq 'editemail') {
        $fields{'action'} = 'saveemail';
        $r->print('<form method="post" action="">');
        $r->print('<input type="text" value="'.$$profile_hashref{'email'}.'" name="email" /><br />');
        $r->print('<input type="submit" value="Save Email" />');
        $r->print(&Apache::Promse::hidden_fields(\%fields));
        $r->print('</form>');
        
    } elsif ($env{'action'} eq 'editsubject') {
        $fields{'action'} = 'savesubject';
        $r->print('<form method="post" action="">');
        $r->print('<select name="subject">');
        my $checked;
        $r->print('<option value="" '.$checked.'>Select Subject</option>');
        if ($$profile_hashref{'subject'} eq 'Math') {
            $checked = ' selected ';
        }
        $r->print('<option value="Math" '.$checked.'>Math</option>');
        if ($$profile_hashref{'subject'} eq 'Science') {
            $checked = ' selected ';
        } else {$checked='';}
        $r->print('<option value="Science"'.$checked.'>Science</option>');
        $r->print('</select>');
        @options = ({'Select Grade Level'=>"Select Grade Level"},
                    {'Elementary'=>"ES"},
                    {'Middle School'=>"MS"},
                    {'High School'=>"HS"});
        $r->print(&Apache::Promse::build_select('level',\@options,$$profile_hashref{'level'}));
        $r->print('<input type="submit" value="Save Subject" />');
        $r->print(&Apache::Promse::hidden_fields(\%fields));
        $r->print('</form>');
    } elsif ($env{'action'} eq 'editlocation') {
        my @districts = &Apache::Promse::get_districts();
        unshift(@districts,{'None'=>0});
        my $district = $districts[0];
        my @schools = keys(%$district);
        my $district_id = $$district{$schools[0]};
        @schools = &Apache::Promse::get_schools($$profile_hashref{'district_id'});
        unshift(@schools,{'None'=>0});
        my $schools_pulldown = &Apache::Promse::build_select('locationid',\@schools,$$profile_hashref{'location_id'},"");
        my $selected = $$profile_hashref{'district_id'};
        my $javascript ='onchange="ajaxFunction()"';
        my $district_pulldown = &Apache::Promse::build_select('districtid',\@districts,$selected,$javascript);
        $r->print(&Apache::Authenticate::district_school_select_javascript(1));
        my $output = qq ~
        <div class="vpdRecordForm">
        <form method="post" action="">
        <div class="vpdRecordInputRow">
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
        <input class="vpdRecordButton" type="submit" value="Update Location" />
        ~;
        $r->print($output);
        $fields{'target'} = 'preferences';
        $fields{'action'} = 'savelocation';
        $r->print(&Apache::Promse::hidden_fields(\%fields));
        $r->print('</form></div>');
    } else {
        if ($env{'action'} eq 'savebio') {
            my $bio = &Apache::Promse::fix_quotes($r->param('bio'));
            %fields = ('bio'=>$bio);
            my %id = ('id'=>$user_id);
            &Apache::Promse::update_record('users',\%id,\%fields);
        }
        if ($env{'action'} eq 'savepassword') {
            my $password1 = &Apache::Promse::fix_quotes($r->param('password1'));
            my $password2 = &Apache::Promse::fix_quotes($r->param('password2'));
            if ($password1 && ($password1 eq $password2)) {
                %fields = ('password'=>$password1);
                my %id = ('id'=>$user_id);
                &Apache::Promse::update_record('users',\%id,\%fields);
            } else {
                $r->print('Passwords did not match. Password was not changed.');
            }
        }
        if ($env{'action'} eq 'savesubject') {
            my $subject = &Apache::Promse::fix_quotes($r->param('subject'));
            my $level = &Apache::Promse::fix_quotes($r->param('level'));
            %fields = ('subject'=>$subject,
                        'level'=>$level);
            my %id = ('id'=>$user_id);
            &Apache::Promse::update_record('users',\%id,\%fields);
        }
        if ($env{'action'} eq 'savelocation') {
            my $location;
            if (!$r->param('locationid')) {
                $location = $r->param('districtid');
            } else {
                $location = $r->param('locationid');
            }
            %fields = ('user_id'=>$env{'user_id'},
                        'loc_id'=>$location);
            my $qry = "delete from user_locs where user_id = $env{'user_id'}";
            $env{'dbh'}->do($qry);
            &Apache::Promse::save_record('user_locs',\%fields);
        }
        if ($env{'action'} eq 'savephoto') {
            my $upload_filehandle = $r->upload('photo');
            my $orig_filename = $r->param('photo');
            $orig_filename =~ /.*(\..+$)/;
            my $file_ext = $1;
            if ($file_ext =~ m/(\.gif|\.jpg|\.jpeg)/i) {
                my $file_name = $user_id.$file_ext;
                my $upload_dir = "/var/www/html/images/userpics";
                $file_name = &Apache::Promse::fix_filename($file_name);
                # now handle the picture upload
                if ($file_name=~/[^\s]/) {
                    if (open UPLOADFILE, ">$upload_dir/$file_name") {
                        binmode UPLOADFILE;
                        while ( <$upload_filehandle> ) { 
                            print UPLOADFILE; 
                        } 
                        close UPLOADFILE;
                    } else {
                        &Apache::Promse::logthis("unable to open photo file");
                    }
                }
                %fields = ('photo'=>&Apache::Promse::fix_quotes($file_name));
                my %id = ('id'=>$user_id);
                &Apache::Promse::update_record('users',\%id,\%fields);
            } else {
                $r->print('Photo must be .gif or .jpg');
            }
        }
        if ($env{'action'} eq 'savename') {
            my $firstname = &Apache::Promse::fix_quotes($r->param('firstname'));
            my $lastname = &Apache::Promse::fix_quotes($r->param('lastname'));
            my %id = ('id'=>$user_id);
            %fields = ('lastname'=>$lastname,
                       'firstname'=>$firstname);
            &Apache::Promse::update_record('users',\%id,\%fields);           
        }
        if ($env{'action'} eq 'saveemail') {
            my $email = &Apache::Promse::fix_quotes($r->param('email'));
            my %id = ('id'=>$user_id);
            %fields = ('email'=>$email);
            &Apache::Promse::update_record('users',\%id,\%fields);           
        }
        
        $profile_hashref = &Apache::Promse::get_user_profile($env{'user_id'});
        my $token = $r->param('token');
        # prepare for all edit link URLs
        %fields = ('token' => $token,
                   'menu' => 'preferences',
                   'submenu' => 'profile',
                  'target' => 'preferences');
        # container for photo
        $r->print('<div class="profileItemContainer">'."\n");
        $r->print('  <div class="profileLink">'."\n");
        $fields{'action'} = 'editpassword';
        $url = &Apache::Promse::build_url('home',\%fields);
        
        if ( !($env{'user_roles'} =~ /Reviewer/) ) {
            $r->print('<a href="'.$url.'">[Edit Password]</a>');
            $r->print('  </div>'."\n");
            $r->print('</div>'."\n");
            $r->print('<div class="profileItemContainer">'."\n");
            $r->print('  <div class="profileLink">'."\n");
            $fields{'action'} = 'editphoto';
            $url = &Apache::Promse::build_url('home',\%fields);
        }
        $r->print('<a href="'.$url.'">[Edit Photo]</a>');
        $r->print('  </div>'."\n");
        $r->print('  <div class="profileContent">'."\n");
        if ($$profile_hashref{'photo'}) {
            $r->print('<img height="100" width="100" align="left" src="'.$config{'image_url'}.'userpics/'.$$profile_hashref{'photo'}.'" alt="" /><br />');
        }
        $r->print('  </div>'."\n");
        $r->print('</div>'."\n");
        # container for name
        $r->print('<div class="profileItemContainer">'."\n");
        $r->print('  <div class="profileLink">'."\n");
        $fields{'action'} = 'editname';
        $url = &Apache::Promse::build_url('home',\%fields);
        $r->print('<a href="'.$url.'">[Edit Name]</a>');
        $r->print('  </div>'."\n");
        $r->print('  <div class="profileContent">'."\n");
        $r->print($$profile_hashref{'firstname'}.' '.$$profile_hashref{'lastname'}.'<br />');
        $r->print('  </div>'."\n");
        $r->print('</div>'."\n"); # close the item container
        # container for subject
        $r->print('<div class="profileItemContainer">'."\n");
        $r->print('  <div class="profileLink">'."\n");
        $fields{'action'} = 'editsubject';
        $url = &Apache::Promse::build_url('home',\%fields);
        $r->print('<a href="'.$url.'">[Edit Subject]</a>');
        $r->print('  </div>'."\n");
        $r->print('  <div class="profileContent">'."\n");
        $r->print($$profile_hashref{'level'}." ".$$profile_hashref{'subject'}.'<br />');
        $r->print('  </div>'."\n");
        $r->print('</div>'."\n"); # close the item container
        
    if ($env{'user_roles'} =~ /Admin/) {
    # container for location
        $r->print('<div class="profileItemContainer">'."\n");
        $r->print('  <div class="profileLink">'."\n");
        $fields{'action'} = 'editlocation';
        $fields{'step'} = 'one';
        $url = &Apache::Promse::build_url('home',\%fields);
        
        $r->print('<a href="'.$url.'">[Edit District/School]</a>');
        $r->print('  </div>'."\n");
        $r->print('  <div class="profileContent">'."\n");
        $r->print($$profile_hashref{'district_name'}." / ".$$profile_hashref{'school'}.'<br />');
        $r->print('  </div>'."\n");
        $r->print('</div>'."\n"); # close the item container
    }
        
        # container for email 
        $r->print('<div class="profileItemContainer">'."\n");
        $r->print('  <div class="profileLink">'."\n");
        $fields{'action'} = 'editemail';
        $url = &Apache::Promse::build_url('home',\%fields);
        $r->print('<a href="'.$url.'">[Edit Email]</a>');
        $r->print('  </div>'."\n");
        $r->print('  <div class="profileContent">'."\n");       
        $r->print($$profile_hashref{'email'}.'<br />');
        $r->print('  </div>'."\n");
        $r->print('</div>'."\n"); # close the item container
        
        # container for bio
        $$profile_hashref{'bio'}=~ s/\n/<br \/>/g;
        $r->print('<div class="profileItemContainer">');
        $r->print('  <div class="profileLink">');
        $fields{'action'} = 'editbio';
        $url = &Apache::Promse::build_url('home',\%fields);
        $r->print('<a href="'.$url.'">[Edit Bio]</a>');
        $r->print('  </div>');
        $r->print('  <div class="profileContent">');
        $r->print($$profile_hashref{'bio'});
        $r->print('  </div>');
        $r->print('</div>');
    }
    return 'ok';
}


sub preferences_profile_submenu {
    my ($active) = @_;
    my %fields = ('target'=>'courses');
    my $tab_info = &Apache::Promse::tabbed_menu_item('home','Profile','preferences','profile',$active,'tabBottom',\%fields);
    return($tab_info);
}
sub preferences_settings_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('home','Settings','preferences','settings',$active,'tabBottom',undef);
    return($tab_info);
}
sub preferences_email_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('home','Email','preferences','email',$active,'tabBottom',undef);
    return($tab_info);
}


sub home_sub_tabs {
    my ($r) = @_;
    my @sub_tabs;
    my %tab_info;
    my $tab_info;
    my $active = 1;
    my %fields;
    my $menu = $r->param('menu')?$r->param('menu'):"";
    if ($env{'menu'} eq 'preferences') {
        $active = ($env{'submenu'} eq 'profile')?1:0;
        $tab_info = &preferences_profile_submenu($active);
        push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'settings')?1:0;
        $tab_info = &preferences_settings_submenu($active);
        push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'email')?1:0;
        $tab_info = &preferences_email_submenu($active);
        push(@sub_tabs,{%$tab_info});
    } elsif ($menu eq 'data') {
        $active = ($env{'submenu'} eq 'tabular')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('home','Tabular','data','tabular',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'graphic')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('home','Graphic','data','graphic',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
    } elsif ($menu eq 'groups') {
        # need to be aware of $env{'group_id'} and $env{'user_roles'}
        if ($env{'user_roles'} =~ /Administrator/ || $env{'user_roles'} =~ /Editor/) {
            $active = ($env{'submenu'} eq 'selectgroup')?1:0;
            $tab_info = &Apache::Promse::tabbed_menu_item('home','Select Group','groups','selectgroup',$active,'tabBottom',undef);
            push(@sub_tabs,{%$tab_info});
            $active = ($env{'submenu'} eq 'addgroup')?1:0;
            my $tab_info = &Apache::Promse::tabbed_menu_item('home','Add Group','groups','addgroup',$active,'tabBottom',undef);
            push(@sub_tabs,{%$tab_info});
            if ($env{'group_id'} ne 'undefined') {
                if ($env{'submenu'} ne 'addthread' && $env{'submenu'} ne 'browsethread' &&
                    $env{'submenu'} ne 'discuss' && $env{'submenu'} ne 'editthread' && 
                    $env{'submenu'} ne 'reply' && $env{'submenu'} ne 'post'  && $env{'submenu'} ne 'editpost') {
                    %fields = ('groupid'=>$env{'group_id'});
                    $active = ($env{'submenu'} eq 'membership')?1:0;
                    $tab_info = &Apache::Promse::tabbed_menu_item('home','Membership','groups','membership',$active,'tabBottom',\%fields);
                    push(@sub_tabs,{%$tab_info});
                    $active = ($env{'submenu'} eq 'editgroup')?1:0;
                    $tab_info = &Apache::Promse::tabbed_menu_item('home','Edit Group','groups','editgroup',$active,'tabBottom',\%fields);
                    push(@sub_tabs,{%$tab_info});
                    $active = ($env{'submenu'} eq 'discuss')?1:0;
                    $tab_info = &Apache::Promse::tabbed_menu_item('home','Discuss','groups','discuss',$active,'tabBottom',\%fields);
                    push(@sub_tabs,{%$tab_info});
                    $active = ($env{'submenu'} eq 'addthread')?1:0;
                    $tab_info = &Apache::Promse::tabbed_menu_item('home','New Thread','groups','addthread',$active,'tabBottom',\%fields);
                    push(@sub_tabs,{%$tab_info});
                } else {
                    %fields = ('groupid'=>$env{'group_id'});
                    $active = ($env{'submenu'} eq 'discuss')?1:0;
                    $tab_info = &Apache::Promse::tabbed_menu_item('home','Discuss','groups','discuss',$active,'tabBottom',\%fields);
                    push(@sub_tabs,{%$tab_info});
                    $active = ($env{'submenu'} eq 'addthread')?1:0;
                    $tab_info = &Apache::Promse::tabbed_menu_item('home','New Thread','groups','addthread',$active,'tabBottom',\%fields);
                    push(@sub_tabs,{%$tab_info});
                    if ($env{'submenu'} ne 'addthread' && $env{'submenu'} ne 'discuss') {
                        %fields = ('groupid'=>$env{'group_id'},
                                   'threadid'=>$env{'thread_id'});
                        $active = ($env{'submenu'} eq 'browsethread')?1:0;
                        $tab_info = &Apache::Promse::tabbed_menu_item('home','Browse Thread','groups','browsethread',$active,'tabBottom',\%fields);
                        push(@sub_tabs,{%$tab_info});
                    }
                    if ($env{'submenu'} eq 'editthread') {
                        $active = 1;
                        $tab_info = &Apache::Promse::tabbed_menu_item('home','Edit Thread','groups','editthread',$active,'tabBottom',\%fields);
                        push(@sub_tabs,{%$tab_info});
                    } elsif ($env{'submenu'} eq 'reply') {
                        $active = 1;
                        $tab_info = &Apache::Promse::tabbed_menu_item('home','Respond','groups','reply',$active,'tabBottom',\%fields);
                        push(@sub_tabs,{%$tab_info});
                    } elsif ($env{'submenu'} eq 'editpost') {
                        $active = 1;
                        $tab_info = &Apache::Promse::tabbed_menu_item('home','Edit Post','groups','editpost',$active,'tabBottom',\%fields);
                        push(@sub_tabs,{%$tab_info});
                    }
                    if ($env{'submenu'} ne 'addthread' && $env{'submenu'} ne 'discuss' && $env{'submenu'} ne 'editthread'
                        && $env{'submenu'} ne 'editpost' ) {
                        $active = ($env{'submenu'} eq 'post')?1:0;
                        $tab_info = &Apache::Promse::tabbed_menu_item('home','New Post','groups','post',$active,'tabBottom',\%fields);
                        push(@sub_tabs,{%$tab_info});
                    }
                }
            }
        } else {
            # submenu for teachers
            if ($env{'group_count'} ne 'none' ) {
                $active = ($env{'submenu'} eq 'selectgroup')?1:0;
                $tab_info = &Apache::Promse::tabbed_menu_item('home','Select Group','groups','selectgroup',$active,'tabBottom',undef);
                push(@sub_tabs,{%$tab_info});
            }
            $active = ($env{'submenu'} eq 'documents')?1:0;
            $tab_info = &Apache::Promse::tabbed_menu_item('home','Documents','groups','documents',$active,'tabBottom',undef);
            push(@sub_tabs,{%$tab_info});
            $active = ($env{'submenu'} eq 'startthread')?1:0;
            $tab_info = &Apache::Promse::tabbed_menu_item('home','Start Thread','groups','startthread',$active,'tabBottom',undef);
            push(@sub_tabs,{%$tab_info});
        }
    }
    return(\@sub_tabs);
}
sub home_tabs_menu {
    my($r) = @_;
    my %fields;
    my @tabs_info;
    my $active;
    my $tab_info;
    $active = ($env{'menu'} eq 'home')?1:0;
    $tab_info = &Apache::Promse::tabbed_menu_item('home','Home','home','',$active,'tabTop',undef);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'resources')?1:0;
    $tab_info = &Apache::Promse::tabbed_menu_item('home','Resources','resources','',$active,'tabTop',undef);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'groups')?1:0;
    %fields = ('secondary'=>&home_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('home','Groups','groups','selectgroup',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'data')?1:0;
    %fields = ('secondary'=>&home_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('home','Data','data','tabular',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'preferences')?1:0;
    %fields = ('secondary'=>&home_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('home','Preferences','preferences','profile',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    return(&Apache::Promse::tabbed_menu_start(\@tabs_info));
}
    
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
        if ($env{'menu'} eq 'preferences') {
            if ($env{'action'} eq 'update') {
                &Apache::Promse::update_preferences($r);
            }
        }
        my $prefs = &Apache::Promse::get_preferences($r);    
        &Apache::Promse::top_of_page_menus($r, 'home', &home_tabs_menu($r));
        if ($env{'menu'} eq 'home') {
            $r->print('<div class="floatLeft">'."\n");
            if ($$prefs{'show_im'} eq 'Yes') {
                &Apache::Promse::read_im($r,$$prefs{'im_expire'});
            }
            &Apache::Promse::current_messages($r);
            $r->print('<br /><br />');
            if ($warning) {
                if ($warning =~ 'password') {
                    $r->print('Your password is the default. You should change your password by clicking "Preferences".<br /><br />');
                }
                if ($warning =~ 'subject') {
                    $r->print('All users must be associated with either Math or Science. Please select your subject at "Preferences"');
                }
            }
            $r->print('</div>'."\n");
            $r->print('<div class="floatLeft">'."\n");
            $r->print('<div class="frontText">Welcome to PROM/SE VPD,'."\n");
            $r->print(' a place for you to: <ul>
                        <li>Continue your face-to-face work by discussing and sharing ideas within working groups'."\n");
            $r->print('<li>Gain access to recommended resources related to the PROM/SE goals');
            $r->print('<li>View and/or listen to talks and presentations (video &amp; audio)</ul>'."\n");
            $r->print('<hr /><a href="../applets/tenblocks.html" target="_blank"><img align="left" alt="apple" height="64" width="65" src="../images/applesmall.gif" /></a>');
            $r->print('Try an applet a day');
            $r->print('</div>');
			$r->print('<div style="clear:both;display:block;width:100%;height:60px"><hr /><br /><br /><a style="margin:20px;" href="apprentice?submenu=&menu=journal&token=' . $env{'token'} . '">Teacher Journal Summary</a></div>');
			$r->print('<div style="clear:both;display:block;width:100%;height:60px"><hr /><br /><br /><a style="margin:20px;" href="apprentice?submenu=&menu=myjournal&token=' . $env{'token'} . '">My Journal Summary</a></div>');
            $r->print('</div>'."\n");
            $r->print('<div class="floatLeft">');
            $r->print('<img src="../images/BoulderSmall.jpg" alt="boulder" />');
            $r->print('<br /><img src="../images/WuCourseSmall.jpg" alt="Wu Course" /><br />');
            my %fields = ('target'=>'resource',
                          'url'=>'invented_algorithm',
                          'action'=>'showvidslide',
                          'token'=>$env{'token'},
                          'showname'=>'invented_algorithm',
                          'resourceid'=>'212');
            my $url = &Apache::Promse::build_url('home',\%fields);
            $r->print('<a href="'.$url.'">Dr. Wu'."'".'s perspective on student invented algorithms.</a>');
                          
            # $r->print('<a href="../video/InvAlgWu2.mov" target="_blank">Dr. Wu'."'".'s perspective on student invented algorithms.</a>');
            $r->print('</div>');
        } elsif ($env{'menu'} eq 'resources') {
            if ($env{'action'} eq 'upload') {
                &Apache::Promse::save_resource($r);
            }
            if ($env{'action'} eq 'update') {
                &Apache::Promse::update_resource($r);
            }
            if ($env{'action'}  eq 'tag') {
                if ($r->param('submit') eq 'Tag Resource') {
	                &Apache::Promse::save_meta_data($r);
	                print $r->param('resourceid');
	                print $r->param('tagcell');
	            }
	        } else {
	            # &Apache::Promse::framework_gizmo($r,'tag');
	        }
    	    # &Apache::Promse::resource_box($r);
    	    if ($env{'action'} eq 'makefave') {
    	        &Apache::Promse::save_fave($r);
    	        &Apache::Promse::resource_box($r);
    	    } elsif ($env{'action'} eq 'removefave' ) {
    	        &Apache::Promse::delete_fave($r);
    	        &Apache::Promse::resource_box($r);
    	    
            } elsif ($env{'action'} eq 'view' ) {
                &Apache::Promse::view_edit_resource($r);
            } elsif ($env{'action'} eq 'delete' ) {
                &Apache::Promse::delete_resource($r);
            } elsif ($env{'action'} eq 'edit' ) {
                &Apache::Promse::edit_resource($r);
            } elsif ($env{'action'} eq 'showvidslide' ) {
                &Apache::Flash::vid_slide_html($r);
            } else {
                # &Apache::Promse::resource_menu($r);
                if ($env{'menu'} eq 'upload') {
                    &Apache::Promse::upload_resource_form($r);
                } else {
                    &Apache::Promse::resource_box($r);
                }
            }
        } elsif ($env{'menu'} eq 'groups') {
            &Apache::Promse::groups($r);
        } elsif ($env{'menu'} eq 'data') {
            &Apache::Promse::data($r);
        } elsif ($env{'menu'} eq 'preferences') {
            if ($env{'action'} eq 'updateprofile') {
                &Apache::Promse::update_profile($r);
            } elsif ($env{'action'} eq 'expertise') {
                &Apache::Promse::update_expertise($r);
            }
            if ($env{'menu'} eq 'interests') {
                &Apache::Promse::user_expertise($r);
            } elsif ($r->param('submenu') eq 'settings') {    
                &Apache::Promse::set_preferences($r);
            } elsif ($r->param('submenu') eq 'email') {   
                &Apache::Promse::set_email_preferences($r); 
            } else {
                &profile_display_edit($r);
            }
        }
        if ($env{'target'} eq 'message') {
            if ($env{'action'} eq 'setprops') {
                &Apache::Promse::update_message_props($r);
            }
            print qq~
            <div id="interiorHeader">
              <h2>PROM/SE Message Center</h2>
            </div>                    
            ~;
            &Apache::Promse::message_menus($r);
            if ($env{'menu'} eq 'compose') {
                &Apache::Promse::compose_message_form($r);
            } elsif ($env{'menu'} eq 'inbox') {
                if ($env{'action'} eq 'view') {
                    &Apache::Promse::view_message($r);
                } elsif ($env{'action'} eq 'Reply') {
                    &Apache::Promse::compose_message_form($r);
                } else {
#                   &Apache::Promse::message_inbox($r);
                    &Apache::Promse::message_box($r,'inbox');
                }
            } elsif ($env{'menu'} eq 'drafts') {
                if ($env{'action'} eq 'view') {
                    &Apache::Promse::compose_message_form($r);
                } 
                if ($env{'action'} eq 'send') {
                    &Apache::Promse::send_message($r,'draft');
                } 
                &Apache::Promse::message_box($r,'draftbox');
            } elsif ($env{'menu'} eq 'outbox') {
                if ($env{'action'} eq 'send') {
                    &Apache::Promse::send_message($r);
                }
                if ($env{'action'} eq 'view') {
                    &Apache::Promse::view_message($r);
                } else {
                    &Apache::Promse::message_box($r,'outbox');
                }
            } elsif ($env{'menu'} eq 'address') {
                if ($env{'action'} eq 'addname') {
                    &Apache::Promse::add_address_book($r);
                }
                if ($env{'action'} eq 'delname') {
                    &Apache::Promse::delete_address_book($r);
                }
                &Apache::Promse::address_book($r);
            } else {
                print "the menu param is ". $env{'menu'};
            }
        } elsif ($env{'target'} eq 'help'){
            $r->print('<div id="interiorHeader">');
            $r->print('<h2>Welcome to the PROM/SE Help Center</h2>');
            $r->print('</div>');
            &Apache::Promse::help_system($r);
        
        } elsif ($env{'target'} eq 'discussion'){
            &Apache::Promse::discussion($r);
        } elsif ($env{'target'} eq 'whoson'){
            &Apache::Promse::who_is_on($r);
        } elsif ($env{'target'} eq 'whosclose'){ 
            &Apache::Promse::who_is_close($r);  
        } elsif ($env{'target'} eq 'im'){
            if ($env{'action'} eq 'send') {
                &Apache::Promse::send_im($r);
            } else {
                &Apache::Promse::compose_im($r);
            }
            &Apache::Promse::read_im($r,$$prefs{'im_expire'});
        } elsif ($env{'menu'} eq 'preferences'){
        } elsif ($env{'target'} eq 'profiledisplay'){
            &Apache::Promse::profile_display($r);
        } elsif ($env{'target'} eq 'mentorquestions'){
            &Apache::Promse::mentor_top_questions($r);
        } elsif ($env{'target'} eq 'lessonlab'){
            &Apache::Promse::lesson_lab_page($r);
        } elsif ($env{'target'} eq 'chat'){
            &Apache::Chat::chat_root($r);
        } elsif ($env{'menu'} eq 'groups'){
        } elsif ($env{'menu'} eq 'resources'){
        } elsif ($env{'target'} eq 'video') {
            if ($env{'action'} eq 'saveclip') {
                &Apache::Promse::save_clip($r);
                &Apache::Promse::resource_box($r);
            } else {
                &Apache::Promse::video($r);
            }
        } elsif ($env{'target'} eq 'keyword') {
            &Apache::Promse::keyword($r);
        } elsif ($env{'target'} eq 'curriculum') {
            if ($env{'action'} eq 'save') {
                &Apache::Promse::save_curriculum($r);
            }
            &Apache::Promse::curriculum($r);
        } elsif ($env{'target'} eq 'data') {
        } else { # target not captured
        }
    } else {
            &Apache::Promse::top_of_page($r);
            &Apache::Promse::user_not_valid($r);
        
    }
    &Apache::Promse::footer;
    #print STDERR "\n*****  Check Point   *****\n";
}
1;