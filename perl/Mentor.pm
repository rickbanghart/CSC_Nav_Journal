#
# $Id: Mentor.pm,v 1.6 2008/11/16 19:53:09 banghart Exp $
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
package Apache::Mentor;
# File: Apache/Mentor.pm
use CGI;
use Apache::Promse;
use Apache::Flash;
use strict;
sub mentor_messages {
    print '<br />Mentor messages to go here<br />';
    return 'ok';
}
sub mentor_sub_tabs {
    my ($r) = @_;
    my @sub_tabs;
    my $tab_info;
    my $active = 1;
    my %fields;
    if ($r->param('menu') eq 'search') {
        if ($env{'submenu'} eq 'results') {
            $active = ($env{'submenu'} eq 'search')?1:0;
            $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Search Again','search','search',$active,'tabBottom',undef);
            push(@sub_tabs,{%$tab_info});
            $active = ($env{'submenu'} eq 'results')?1:0;
            $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Results','search','results',$active,'tabBottom',undef);
            push(@sub_tabs,{%$tab_info});
        }
    } elsif ($r->param('menu') eq 'courses') {
        $active = ($env{'submenu'} eq 'mine')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('mentor','My Courses','courses','mine',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'allcourses')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('mentor','All Courses','courses','allcourses',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
        if ($env{'course_id'} ne 'undefined') {
            %fields = ('courseid'=>$env{'course_id'});
            $active = ($env{'submenu'} eq 'study')?1:0;
            $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Study','courses','study',$active,'tabBottom',\%fields);
            push(@sub_tabs,{%$tab_info});
#            $active = ($env{'submenu'} eq 'notebook')?1:0;
#            $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Notebook','courses','notebook',$active,'tabBottom',\%fields);
#            push(@sub_tabs,{%$tab_info});
        }
    } elsif ($r->param('menu') eq 'questions') {
        $active = ($env{'submenu'} eq 'answers')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Answers','questions','answers',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'questions')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Questions','questions','questions',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'newquestion')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('mentor','New Question','questions','newquestion',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
    }
    return(\@sub_tabs);
}
sub mentor_tabs_menu {
    my($r) = @_;
    my %fields;
    my @tabs_info;
    my $active;
    my $tab_info;
    $active = ($env{'menu'} eq 'home')?1:0;
    $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Mentor Home','home','',$active,'tabTop',undef);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'questions')?1:0;
    %fields = ('secondary'=>&mentor_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Questions','questions','',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'resources')?1:0;
    $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Resources','resources','',$active,'tabTop',undef);
    push (@tabs_info,{%$tab_info});
#    %fields = ('secondary'=>&mentor_sub_tabs($r));
#    $active = ($env{'menu'} eq 'framework')?1:0;
#    $tab_info = &Apache::Promse::tabbed_menu_item('mentor','Framework','framework','mine',$active,'tabTop',undef);
#    push (@tabs_info,{%$tab_info});
    return(&Apache::Promse::tabbed_menu_start(\@tabs_info));
}
sub handler {
my $r = new CGI;
&Apache::Promse::validate_user($r);
if ($Apache::Promse::env{'token'}=~/[^\s]/){
    &Apache::Promse::top_of_page_menus($r,'mentor',&mentor_tabs_menu($r));
    if ($r->param('target') eq 'resource') {
        if ($env{'action'} eq 'upload') {
            &Apache::Promse::save_resource($r);
        }
        if ($env{'action'} eq 'tag') {
            if ($r->param('submit') eq 'Tag Resource') {
                &Apache::Promse::save_meta_data($r);
                print $r->param('resourceid');
                print $r->param('tagcell');
            } else {
                print '<span>Tag the resource</span>';
                &Apache::Promse::framework_gizmo($r,'tag');
                print '<p>You are tagging '.$r->param('resourceid');
            }
        }
        if ($env{'action'} eq 'profile') {
            print '<span>Display user profile here</span>';
        }
        if ($r->param('menu') eq 'upload') {
            &Apache::Promse::upload_resource_form($r);
        } elsif ($r->param('menu') eq 'browse') {
            &Apache::Promse::resource_box($r);
        }

    } elsif ($r->param('target') eq 'ohiomath') {
        &Apache::Promse::standard_gizmo($r);   
    } elsif ($r->param('target') eq 'framework') {
        &Apache::Promse::framework_gizmo($r);
    } elsif ($r->param('menu') eq 'questions') {
        &Apache::Flash::teacher_message_html($r);
#        if ($env{'action'} eq 'send') {
#            &Apache::Promse::send_answer($r);
#        }
#        if ($env{'action'} eq 'setprops') {
#            $r->print('Setting props ');
#        }
#        if ($env{'action'} eq 'view') {
#            &Apache::Promse::view_question($r);
#            &Apache::Promse::compose_answer_form($r);
#        } else {
#            if ($r->param('submenu') eq "drafts") {
#                &Apache::Promse::question_box($r, 'draftbox');
#            } else {
#                &Apache::Promse::question_box($r, 'inbox');
#            }
#        }
    } else {
        $r->print('<div id="leftColumnContainer">');
        $r->print('<div class="columnTitle">');
        $r->print('System Messages');
        $r->print('</div>');
        $r->print('<div class="columnBorder">');
        &Apache::Promse::current_messages($r);
        $r->print('</div>');
        $r->print('</div>');
        $r->print('<div id="centerColumnContainer">');
        $r->print('<div class="columnTitle">');
        $r->print('Mentor Stats');
        $r->print('</div>');
        $r->print('<div class="columnBorder">');
        &mentor_messages;       
        $r->print('</div>');
        $r->print('</div>');
        $r->print('<div id="rightColumnContainer">');
        $r->print('<div class="columnTitle">');
        $r->print('Mail Box');
        $r->print('</div>');
        $r->print('<div class="columnBorder">');
        &Apache::Promse::mentor_question_alert($r);
        $r->print('</div>');
        $r->print('</div>');
#        &Apache::Promse::mentor_rating;
#        &Apache::Promse::last_login;
    }
    &Apache::Promse::footer;
} else {
    &Apache::Promse::top_of_page($r);
    &Apache::Promse::user_not_valid($r);
    &Apache::Promse::footer;
}
}
1;
