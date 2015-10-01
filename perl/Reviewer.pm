#
# $Id: Admin.pm,v 1.13 2009/02/01 18:05:27 banghart Exp $
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
package Apache::Reviewer;
# File: Apache/Admin.pm 
use CGI;
use Apache::Promse;
use Apache::Flash;
use vars qw(%env);
use strict;
use DBI;
sub reviewer_sub_tabs {
    my ($r) = @_;
    my @sub_tabs;
    my %tab_info;
    my $tab_info;
    my $tab_info_hashref;
    my $active = 1;
    my %fields;
    if ($env{'menu'} eq 'courses') {
        if (($env{'submenu'} eq 'existing') || ($env{'submenu'} eq 'add')) {
            $active = ($env{'submenu'} eq 'existing')?1:0;
            $tab_info_hashref = &course_existing_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'add')?1:0;
            $tab_info_hashref = &course_add_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
        } elsif (($env{'submenu'} eq 'edit') || ($env{'submenu'} eq 'build') ||
                  ($env{'submenu'} eq 'build') || ($env{'submenu'} eq 'addcourseonlyresource'))  {
            $active = ($env{'submenu'} eq 'existing')?1:0;
            $tab_info_hashref = &course_existing_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'add')?1:0;
            $tab_info_hashref = &course_add_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'edit')?1:0;
            $tab_info_hashref = &course_edit_submenu($active, $r->param('courseid'));
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'build')?1:0;
            $tab_info_hashref = &course_build_submenu($active, $r->param('courseid'));
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'addcourseonlyresource')?1:0;
            $tab_info_hashref = &course_addcourseonlyresource_submenu($active, $r->param('courseid'));
            push(@sub_tabs,{%$tab_info_hashref});
            if ($env{'submenu'} eq 'editcourseonly') {
                $active = ($env{'submenu'} eq 'editcourseonly')?1:0;
                $tab_info_hashref = &course_addcourseonlyresource_submenu($active, $r->param('courseid'));
                push(@sub_tabs,{%$tab_info_hashref});
            }
        }
    } elsif ($env{'menu'} eq 'resources') {
        if (($env{'submenu'} eq 'browse') || ($env{'submenu'} eq 'add')) {
            $active = ($env{'submenu'} eq 'browse')?1:0;
            $tab_info_hashref = &resource_browse_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'add')?1:0;
            $tab_info_hashref = &resource_add_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
        } elsif (($env{'submenu'} eq 'edit') || ($env{'submenu'} eq 'edit') ||
                  ($env{'submenu'} eq 'categories') || ($env{'submenu'} eq 'tags')||
                  ($env{'submenu'} eq 'showvidslide')) {
            $active = ($env{'submenu'} eq 'browse')?1:0;
            $tab_info_hashref = &resource_browse_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'add')?1:0;
            $tab_info_hashref = &resource_add_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'edit')?1:0;
            $tab_info_hashref = &resource_edit_submenu($active, $r->param('resourceid'));
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'categories')?1:0;
            $tab_info_hashref = &resource_categories_submenu($active, $r->param('resourceid'));
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'tags')?1:0;
            $tab_info_hashref = &resource_tags_submenu($active, $r->param('resourceid'));
            push(@sub_tabs,{%$tab_info_hashref});
            &Apache::Promse::logthis(&Apache::Promse::get_resource_type($r->param('resourceid')).' is the type');
            if (&Apache::Promse::get_resource_type($r->param('resourceid')) eq 'Video/Slide') {
                $active = ($env{'submenu'} eq 'showvidslide')?1:0;
                $tab_info_hashref = &resource_showvidslide_submenu($active, $r->param('resourceid'),$r->param('showname'));
                push(@sub_tabs,{%$tab_info_hashref});
            }
        }
    } elsif ($env{'menu'} eq 'curriculum') {
        $active = ($env{'submenu'} eq 'selectcurriculum')?1:0;
        $active = ($env{'submenu'} eq 'addcurriculum')?1:0;
        if ($env{'curriculum_id'} ne 'undefined') {
            $active = ($env{'submenu'} eq 'develop')?1:0;
        }
        $active = ($env{'submenu'} eq 'materials')?1:0;
        $active = ($env{'submenu'} eq 'addmaterials')?1:0;
    }
    return(\@sub_tabs);
}
sub reviewer_tabs_menu {
    my($r) = @_;
    my @tabs_info;
    my %fields;
    my $active;
    my $tab_info;
    $active = ($env{'menu'} eq 'home')?1:0;
    %fields = ('secondary'=>'');
    $tab_info = &Apache::Promse::tabbed_menu_item('reviewer','Reviewer Home','home','',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'curriculum')?1:0;
    %fields = ('secondary'=>'');
    $tab_info = &Apache::Promse::tabbed_menu_item('reviewer','Curriculum','curriculum','selectcurriculum',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'code')?1:0;
    %fields = ('secondary'=>'');
    $tab_info = &Apache::Promse::tabbed_menu_item('reviewer','Code','code','',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    return(&Apache::Promse::tabbed_menu_start(\@tabs_info));
}


sub handler {
    my $r = new CGI;
    &Apache::Promse::validate_user($r);
    my $auth_token = &Apache::Promse::authenticate('Reviewer');
    my $alert_message;
    if ($auth_token ne 'ok') {
        &Apache::Promse::top_of_page($r);
        print "Not authorized for this page<br>";
        &Apache::Promse::footer($r);
    } else {
        &Apache::Promse::top_of_page_menus($r, 'reviewer',&reviewer_tabs_menu());
        if ($env{'menu'} eq 'curriculum') {
            &Apache::Flash::curriculum_coherence_html($r);
        } elsif ($env{'menu'} eq 'code') {
            &Apache::Flash::promse_admin_code_html($r);
        }
        &Apache::Promse::footer;
    }
}
1;
