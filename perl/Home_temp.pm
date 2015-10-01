#
# $Id: Home.pm,v 1.14 2006/07/29 08:21:41 kosze Exp $
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
package Apache::Promse;package Apache::Home;
# File: Apache/Home.pm
use CGI;
$CGI::POST_MAX = 900000;
use Apache::Promse;
use Apache::Chat;
use strict;
use Apache::Constants qw(:common);
sub handler {
    my $r = new CGI;
    if ($r->cgi_error) {
        &Apache::Promse::top_of_page($r);
        print $r->cgi_error;
        &Apache::Promse::footer($r)
    }
    &Apache::Promse::validate_user($r); #sets environment variables.
    if (($Apache::Promse::env{'username'} ne 'not_found') || ($Apache::Promse::env{'token'}=~/[^\s]/)){
        if ($Apache::Promse::env{'target'} eq 'preferences') {
            if ($r->param('action') eq 'update') {
                &Apache::Promse::update_preferences($r);
            }
        }
        my $prefs = &Apache::Promse::get_preferences($r);    
        &Apache::Promse::top_of_page_menus($r, 'home');
        if ($Apache::Promse::env{'target'} eq 'message') {
            if ($r->param('action') eq 'setprops') {
                &Apache::Promse::update_message_props($r);
            }
            print qq~
             <div id="interiorHeader">
                  <h2>PROM/SE Message Center</h2>
             </div>                    
            ~;
            &Apache::Promse::message_menus($r);
            if ($r->param('menu') eq 'compose') {
                &Apache::Promse::compose_message_form($r);
            } elsif ($r->param('menu') eq 'inbox') {
                if ($r->param('action') eq 'view') {
                    &Apache::Promse::view_message($r);
                } elsif ($r->param('action') eq 'Reply') {
                    &Apache::Promse::compose_message_form($r);
                } else {
    #            &Apache::Promse::message_inbox($r);
                    &Apache::Promse::message_box($r,'inbox');
                }
            } elsif ($r->param('menu') eq 'drafts') {
                if ($r->param('action') eq 'view') {
                    &Apache::Promse::compose_message_form($r);
                } 
                if ($r->param('action') eq 'send') {
                    &Apache::Promse::send_message($r,'draft');
                } 
                &Apache::Promse::message_box($r,'draftbox');
            } elsif ($r->param('menu') eq 'outbox') {
                if ($r->param('action') eq 'send') {
                    &Apache::Promse::send_message($r);
                }
                if ($r->param('action') eq 'view') {
                    &Apache::Promse::view_message($r);
                } else {
                    &Apache::Promse::message_box($r,'outbox');
                }
            } elsif ($r->param('menu') eq 'address') {
                if ($r->param('action') eq 'addname') {
                    &Apache::Promse::add_address_book($r);
                }
                if ($r->param('action') eq 'delname') {
                    &Apache::Promse::delete_address_book($r);
                }
                &Apache::Promse::address_book($r);
            } else {
                print "the menu param is ". $r->param('menu');
            }
            
            
        } elsif ($Apache::Promse::env{'target'} eq 'help'){
            $r->print('<div id="interiorHeader">');
            $r->print('<h2>Welcome to the PROM/SE Help Center</h2>');
            $r->print('</div>');
            &Apache::Promse::help_system($r);
            
        } elsif ($Apache::Promse::env{'target'} eq 'discussion'){
            &Apache::Promse::discussion($r);
        } elsif ($Apache::Promse::env{'target'} eq 'whoson'){
            &Apache::Promse::who_is_on($r);
        } elsif ($Apache::Promse::env{'target'} eq 'whosclose'){ 
            &Apache::Promse::who_is_close($r);  
        } elsif ($Apache::Promse::env{'target'} eq 'im'){
            if ($r->param('action') eq 'send') {
                &Apache::Promse::send_im($r);
            } else {
                &Apache::Promse::compose_im($r);
            }
            &Apache::Promse::read_im($r,$$prefs{'im_expire'});
        } elsif ($Apache::Promse::env{'target'} eq 'preferences'){
            &Apache::Promse::user_preferences_menu($r);
            if ($r->param('action') eq 'updateprofile') {
                &Apache::Promse::update_profile($r);
            } elsif ($r->param('action') eq 'expertise') {
                &Apache::Promse::update_expertise($r);
            }
            if ($r->param('menu') eq 'interests') {
                &Apache::Promse::user_expertise($r);
            } elsif ($r->param('menu') eq 'settings') {    
                &Apache::Promse::set_preferences($r);
            } else {
                &Apache::Promse::profile_form($r);
            }
        } elsif ($Apache::Promse::env{'target'} eq 'mentorquestions'){
            &Apache::Promse::mentor_top_questions($r);
        } elsif ($Apache::Promse::env{'target'} eq 'lessonlab'){
            &Apache::Promse::lesson_lab_page($r);
        } elsif ($Apache::Promse::env{'target'} eq 'chat'){
            &Apache::Chat::chat_root($r);
        } elsif ($Apache::Promse::env{'target'} eq 'groups'){
            &Apache::Promse::groups($r);
        } elsif ($Apache::Promse::env{'target'} eq 'resource'){
	    if ($r->param('action') eq 'upload') {
                &Apache::Promse::save_resource($r);
            }
            if ($r->param('action') eq 'update') {
	        &Apache::Promse::update_resource($r);
	    }
            if ($r->param('action') eq 'Add Tag') {
		            if ($r->param('submit') eq 'Tag Resource') {
		                &Apache::Promse::save_meta_data($r);
		                print $r->param('resourceid');
		                print $r->param('tagcell');
		            } else {
		                &Apache::Promse::framework_gizmo($r,'tag');
		            }
		            &Apache::Promse::resource_box($r);
		        } elsif ($r->param('action') eq 'view' ) {
		            &Apache::Promse::view_edit_resource($r);
		        } elsif ($r->param('action') eq 'Delete' ) {
		            &Apache::Promse::delete_resource($r);
		        } else {
		            &Apache::Promse::resource_menu($r);
		            if ($r->param('menu') eq 'upload') {
		                &Apache::Promse::upload_resource_form($r);
		            } else {
		                &Apache::Promse::resource_box($r);
		            }
		        }
        } elsif ($Apache::Promse::env{'target'} eq 'video') {
		        if ($r->param('action') eq 'saveclip') {
		            &Apache::Promse::save_clip($r);
		            &Apache::Promse::resource_box($r);
		        } else { 
		            &Apache::Promse::video($r);
		        }
		    } elsif ($Apache::Promse::env{'target'} eq 'keyword') {
		        &Apache::Promse::keyword($r);
		    } elsif ($Apache::Promse::env{'target'} eq 'curriculum') {
		        if ($r->param('action') eq 'save') {
		            &Apache::Promse::save_curriculum($r);
		        }
		        &Apache::Promse::curriculum($r);
        } else {
            $r->print('<div id="interiorHeader">'."\n");
            $r->print('<br><h3><strong>Welcome to the PROM/SE Homepage</strong></h3>'."\n");
            $r->print('</div>'."\n");
            if ($$prefs{'show_im'} eq 'Yes') {
                &Apache::Promse::read_im($r,$$prefs{'im_expire'});
            }
            $r->print('<div class="floatLeft">'."\n");
            &Apache::Promse::current_messages($r);
            $r->print('<br><br>');
            &Apache::Promse::top_help($r);
            $r->print('</div>'."\n");
            $r->print('<div class="floatLeft">'."\n");
            $r->print('<font size="2">Welcome to the Virtual Professional Development,'."\n");
            $r->print(' a place where you can have conversations with your colleagues, gain access to data,'."\n");
            $r->print('standards and recommended resources to use in your classroom, ');
            $r->print('as well as engage in follow-up experiences from the summer academies. </font>'."\n");
            #$r->print('</td></tr></table>'."\n");
            $r->print('</div>'."\n");
        }
    } else {
        &Apache::Promse::top_of_page($r);
        &Apache::Promse::user_not_valid($r);
        
    }
    &Apache::Promse::footer;
}
1;