#
# $Id: Apprentice.pm,v 1.18 2009/02/01 18:07:10 banghart Exp $
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
package Apache::Apprentice;
# this is a test
use CGI;
use Apache::Promse;
use Apache::Flash;
use Apache::Journal;
use strict;
use DBI;
use vars qw(%env);
sub apprentice_search_form {
    my ($r) = @_;
    my $code = $r->param('code');
    my $topic_description;
    if ($code) {
        # came from alignment link
        $topic_description = &code_to_description($code);
    }
    $r->print('<form method="post" action="apprentice" >');
    $r->print('<fieldset>');
    $r->print('<h4>Subject</h4>');
    $r->print('<label>Math</label><input type="radio" name="contentarea" value="math" checked />'."\n");
    $r->print('<label>Science</label><input type="radio" name="contentarea" value="science" /> '."\n");
    $r->print('<label>Time Commitment:</label>'."\n");
    $r->print('<select name="timecommitment" id="SelectOne">'."\n");
    $r->print('<option>0-10 Min.</option>'."\n");
    $r->print('<option selected>10-30 Min.</option>'."\n");
    $r->print('<option>30-60 Min.</option>'."\n");
    $r->print('<option>1-2 Hrs.</option>'."\n");
    $r->print('<option>2-4 Hrs.</option>'."\n");
    $r->print('<option>More than a day</option>'."\n");
    $r->print('</select>'."\n");
    $r->print('<label>Search for:</label>'."\n");
    $r->print('<input name="searchtext" type="text" size="30" value="'.$topic_description.'" />'."\n");
    $r->print('<input name="search" type="submit" id="search" value="Search" />'."\n");
    my %fields = ('code'=>$code,
                  'menu'=>'search',
                  'submenu'=>'results',
                  'action'=>'search');
    $r->print(&Apache::Promse::hidden_fields(\%fields));
    $r->print('</fieldset>'."\n");
    $r->print('</form>'."\n");
}

sub apprentice_find {
    my ($r) = @_;
    my $qry = "";
    our %search_results;
    my $where_clause;
    my $sth;
    my $framework_index = $r->param('code');
    my $upload_dir_url = "../resources";
    my @search_text = split / /, uc($r->param('searchtext'));
    foreach my $word (@search_text) {
        $word = substr $word, 0, 6;
        if (length($word)>5) {
            $word = &Apache::Promse::fix_quotes('%' . $word.'%');
        } else {
            $word = &Apache::Promse::fix_quotes($word);
        }
        $qry = "SELECT doc_id FROM doc_code WHERE word LIKE $word";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        while (my $row = $sth->fetchrow_hashref) {
            $search_results{$$row{'doc_id'}} += $$row{'count'}
        }
        # $r->print("the search text is $word <br />");
    }
    $qry="";
    sub by_value_descending {$search_results{$b} <=> $search_results{$a}}
    foreach my $key (sort by_value_descending (keys (%search_results))) {
        #$r->print("doc $key received $search_results{$key} points<br />");
        $qry .= " select title, location, time_commitment, type, id, $search_results{$key} as score from resources where id = $key union";
    }
    $qry =~ s/union$//;
    
    #$qry = "select resources.title, resources.location, resources.id from resources, res_meta, tags where res_meta.tag_id = tags.id and ";
    #$qry .= " resources.id = res_meta.res_id and tags.location = '".$framework_index."'";
    $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    if ($sth->rows == 0 ) {
        print "No resources were found that match your search. Try modifying or adding to your search phrase.";
    } else {
        print "<h4>The following resources match your search request:</h4>";
        $r->print('<table><thead><tr ><th>Resource Title</th><th>Time Commitment</th>');
        $r->print('<th>Topics Covered</th><th>User Rating</th><th>Search Rating</th></tr>');
        $r->print('</thead><tbody>');
        while (my $resource = $sth->fetchrow_hashref) {
            print '<tr><td>';
            if ($$resource{'type'} eq 'Web URL') {
                print '<a target="new" href="'.$$resource{'location'}.'">'.$$resource{'title'}."</a></td>";
            } else {
                print '<a target="new" href="'.$upload_dir_url.'/'.$$resource{'location'}.'.'.$$resource{'id'}.'">'.$$resource{'title'}."</a></td>";
            }
            $r->print('<td>'.$$resource{'time_commitment'}.'</td>');
            $r->print('<td>'.$$resource{'time_commitment'}.'</td>');
            $r->print('<td>'.$$resource{'time_commitment'}.'</td>');
            $r->print('<td>'.$$resource{'score'}.'</td>');
            $r->print('</tr>');
        }
        print '</tbody></table>';
    }
    print "";
    return 'ok';
}

sub apprentice_sub_tabs {
    my ($r) = @_;
    my @sub_tabs;
    my $tab_info;
    my $active = 1;
    my %fields;
    if ($r->param('menu') eq 'search') {
        if ($env{'submenu'} eq 'results') {
            $active = ($env{'submenu'} eq 'search')?1:0;
            $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Search Again','search','search',$active,'tabBottom',undef);
            push(@sub_tabs,{%$tab_info});
            $active = ($env{'submenu'} eq 'results')?1:0;
            $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Results','search','results',$active,'tabBottom',undef);
            push(@sub_tabs,{%$tab_info});
        }
	} elsif ($r->param('menu') eq 'journal') {
		$active = ($env{'submenu'} eq 'mine')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','My Journal','journal','mine',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
		$active = ($env{'submenu'} eq 'district')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','District Summary','journal','district',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
		
    } elsif ($r->param('menu') eq 'courses') {
        $active = ($env{'submenu'} eq 'mine')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','My Courses','courses','mine',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'allcourses')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','All Courses','courses','allcourses',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
        if ($env{'course_id'} ne 'undefined') {
            %fields = ('courseid'=>$env{'course_id'});
            $active = ($env{'submenu'} eq 'study')?1:0;
            $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Study','courses','study',$active,'tabBottom',\%fields);
            push(@sub_tabs,{%$tab_info});
#            $active = ($env{'submenu'} eq 'notebook')?1:0;
#            $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Notebook','courses','notebook',$active,'tabBottom',\%fields);
#            push(@sub_tabs,{%$tab_info});
        }
    } elsif ($r->param('menu') eq 'questions') {
        $active = ($env{'submenu'} eq 'answers')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Answers','questions','answers',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'questions')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Questions','questions','questions',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'newquestion')?1:0;
        $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','New Question','questions','newquestion',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info});
    }
    return(\@sub_tabs);
}
sub apprentice_tabs_menu {
    my($r) = @_;
    my %fields;
    my @tabs_info;
    my $active;
    my $tab_info;
    $active = ($env{'menu'} eq 'home')?1:0;
    $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Teacher Home','home','',$active,'tabTop',undef);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'search')?1:0;
    %fields = ('secondary'=>&apprentice_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Search','search','',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'journal')?1:0;
	%fields = ('secondary'=>&apprentice_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Journal','journal','',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    %fields = ('secondary'=>&apprentice_sub_tabs($r));
    $active = ($env{'menu'} eq 'courses')?1:0;
    $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Mini-Courses','courses','mine',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'questions')?1:0;
    %fields = ('secondary'=>&apprentice_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('apprentice','Questions','questions','answers',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    return(&Apache::Promse::tabbed_menu_start(\@tabs_info));
}
sub journal_summaries {
	my ($r) = @_;
	my $rst;
	my $qry;
	my $submenu = $r->param('submenu');
	my $end_date = $r->param('start_date')?$r->param('end_date'):'2014-02-01';
	my $profile = &Apache::Promse::get_user_profile($env{'user_id'});
	my $district_id = $$profile{'district_id'};
	$qry = "SELECT date FROM districts where district_id = ?";
	$rst = $env{'dbh'}->prepare($qry);
	$rst->execute($district_id);
	my $row = $rst->fetchrow_hashref();
	my $district_start_date = $$row{'date'};
	my $start_date = $r->param('start_date')?$r->param('start_date'):$district_start_date;
	my $class_selector = &Apache::Journal::get_district_classes($district_id);
	$r->print ('<div> ' . "district is $district_id user id is $env{'user_id'}" . '</div>');
	$r->print ('<div id="statusMessage" style="background-color:#ffdddd;
		padding:3px;
		float:right;
		display:none;
		width:300px;
		height:50px">Status Message</div>');
	$r->print('<div id="controlPanel" style="margin-left;3px;border-style:solid;border-width:1px;border-color:#888888;float:left;background-color:#ddffdd;padding:5px;display:block;width:275px;text-align:left" >');
	$r->print('<div style="width:100%;text-align:center"><b>Control Panel</b>');
	$r->print('<img style="float:right" height="15" width="15" helpid="help04" onmouseover="mouseoverhelp(this)" onmouseout="mouseouthelp()" src="../images/helpsmall.png" />');
	$r->print('</div>');
	$r->print('<input type="hidden" id="districtid" value="' . $district_id . '" />');
	$r->print('<div style="display:block;width:100%;text-align:center;" id="classselector">' . $class_selector . '</div>');
	$r->print ('<span style="display:block;float:left;width:100px;height:20px;text-align:right;">Start Date:</span> <input type="text" id="startdate" 
	name="start_date" 
	value="' . $start_date . '" 
	style="float:right;width:80px;" onchange="classSelectorChange()" /><br />');
	$r->print ('<span style="display:block;clear:both;float:left;width:100px;height:20px;text-align:right" onchange="classSelectorChange()">End Date: </span> <input type="text" id="enddate" name="end_date" value="2014-05-01" style="float:right;width:80px;" onchange="classSelectorChange()" />');
	$r->print ('<span style="display:block;clear:both;float:left;width:100px;height:20px;text-align:right" onchange="classSelectorChange()">Completion %: </span> <input type="text" id="threshold" name="threshold" value="75" style="float:right;width:80px;" onchange="classSelectorChange()"/>');
	$r->print ('<input type="hidden" name="action" value="retrieve" />');
	$r->print ('<input type="hidden" name="token" value="' . $env{'token'} . '" />');
	$r->print ('<input type="hidden" name="menu" value="tj" />');
	$r->print ('<input type="hidden" name="submenu" value="' . $submenu . '" />');
	$r->print ('<button style="display:block;width:100px;" id="updateButton" type="button" onclick="buttonClicked()">Update Table</button>');
	$r->print('</div>');
	my $disclaimer = &Apache::Journal::get_disclaimer();
	$r->print($disclaimer);
	$r->print('<div id="standardText" style="border-style:solid;
		border-width:1px;
		border-color:#cccccc;
		text-align:left;display:none;background-color:#ffffee;width:250px;padding:4px;"></div>');
	$r->print('<div id="summaryTable" style="clear:both"></div>');
	my $token = $env{'token'};
	my $output = &Apache::Journal::get_journal_summary_javascript($r);
	$r->print($output);
	$output = qq~
	<div id="helpDisplay" 
	style="display:none;
	position:absolute;
	border-style:solid;
	border-width:1px;
	border-color:#555555;
	background-color:#ffffee;
	width:400px">Starting text for test</div>
	~;
	$r->print($output);
	$output = &Apache::Journal::get_journal_summary_help();
	$r->print($output);
	$output = qq~	<canvas id="canvasOne" width="200" height="100"
	style="border:1px solid #000000;" onclick="canvasClicked(this)">
	</canvas>
	<canvas id="canvasTwo" width="200" height="100" onclick="canvasClicked(this)"
	style="border:1px solid #ff0000;">
	</canvas>
	~;
	return();
}

sub handler {
    my $r = new CGI;
    &Apache::Promse::validate_user($r);
    my $redirect = $r->param('resource')?$r->param('resource'):"";
    if ($env{'username'} ne 'not_found'){
        if ($redirect eq 'redirect') {
            &Apache::Promse::course_log_progress($r);
            &Apache::Promse::logthis("apprentice redirect");
            &Apache::Promse::logthis($r->param('url'));
            &Apache::Promse::redirect($r);
        }
        &Apache::Promse::top_of_page_menus($r,'apprentice',&apprentice_tabs_menu($r));
        if ($env{'menu'} eq 'home') {
            $r->print('<div id="systemMessages">');
            &Apache::Promse::current_messages($r);
            $r->print('</div>');
			$r->print('<div style="text-align:left">');
			$r->print('<div style="clear:both;display:block;width:100%;height:60px"><hr /><br /><br /><a style="margin:20px;" href="apprentice?submenu=&menu=journal&token=' . $env{'token'} . '">Teacher Journal Summary</a></div>');
            $r->print('</div>'."\n");
			$r->print('</div>');
            $r->print('<div id="surveys">');
            &Apache::Promse::survey_link($r);
            $r->print('</div>');
        } elsif ($env{'menu'} eq 'search') {
            if ($env{'action'} eq 'search') {
                &apprentice_find($r);
            } else {
                &apprentice_search_form($r);
            }
        } elsif ($env{'menu'} eq 'journal') {
			if ($env{'submenu'} eq 'district') {
            	&journal_summaries($r);
			} elsif ($env{'submenu'} eq 'mine') {
				&journal_summaries($r);
			}
			#if ($env{'action'} eq 'selectstrand') {
            #    $env{'strand_id'} = $r->param('strandid');     
            #}
            #&Apache::Promse::list_strands($r);
            #if ($env{'strand_id'}) {
            #    &Apache::Promse::visualize_strand($r);
            #}
        } elsif ($env{'menu'} eq 'courses') {
            if ($env{'action'} eq 'showvidslide') {
                &Apache::Promse::course_log_progress($r);
                &Apache::Flash::vid_slide_html($r);
            } elsif ($env{'action'} eq 'selectcourse') {
                    &Apache::Promse::add_user_course($r);
            } elsif ($env{'action'} eq 'updatesegmentnotebook') {
                &Apache::Promse::update_segment_notebook($r);
            }
            if ($env{'submenu'} eq 'mine') {
                $r->print(&Apache::Promse::show_user_courses($r));
            } elsif ($env{'submenu'} eq 'allcourses') {
                $r->print(&Apache::Promse::show_course_selection($r));
            } elsif ($env{'submenu'} eq 'study') {
                &Apache::Promse::course_study($r);
                
            } elsif ($env{'submenu'} eq 'notebook') {
                
            }
        } elsif ($env{'menu'} eq 'questions') {
            &Apache::Flash::teacher_message_html($r);
#            if ($env{'action'} eq 'saverating') {
#                &Apache::Promse::save_rating($r);
#            }
#            if ($env{'action'} eq 'setprops') {
#                &Apache::Promse::update_message_props($r);
#            }
#            # &Apache::Promse::question_menu($r);
#            if ($env{'submenu'} eq 'newquestion') {
#                &Apache::Promse::compose_question_form($r);
#            } elsif ($env{'submenu'} eq 'answers') {
#                if ($env{'action'} eq 'view') {
#                    &Apache::Promse::view_answer($r);
#                } else {
#                    &Apache::Promse::answer_box($r);
#                }
#            } elsif ($env{'submenu'} eq 'questions') {
#                if ($env{'action'} eq 'view') {
#                    &Apache::Promse::compose_question_form($r);
#                } elsif ($env{'action'} eq 'send') {
#                    &Apache::Promse::send_question($r);
#                    &Apache::Promse::question_box($r, 'outbox');
#                } else {
#                    &Apache::Promse::question_box($r, 'outbox');
#                }
#            }elsif ($env{'submenu'} eq 'questions') {
#                if ($env{'action'} eq 'send') {
#                    if ($r->param('Submit') eq 'Save Question') {
#                        &Apache::Promse::send_question($r);
#                    } elsif ($r->param('Submit') eq 'Send Question!') {
#                        &Apache::Promse::send_question($r);
#                    }
#                }
#                &Apache::Promse::question_box($r, 'outbox');
#            }   
        }
        if ($env{'target'} eq 'questions') {
        } elsif ($env{'target'} eq 'search') {
        } elsif ($env{'target'} eq 'journal') {
            # &Apache::Promse::framework_gizmo($r);
        } elsif ($env{'target'} eq 'frameworkreporter') {
            # &Apache::Promse::display_23($r);
            &Apache::Promse::framework_reporter($r);
        } elsif ($env{'target'} eq 'video') {
            &Apache::Promse::video($r);
        } elsif ($env{'target'} eq 'survey') { 
            &Apache::Promse::survey($r);
        } elsif ($env{'target'} eq 'minicourse') {
        } else {
        }
        &Apache::Promse::footer;
    } else {
        &Apache::Promse::top_of_page($r);
        &Apache::Promse::user_not_valid($r);
        &Apache::Promse::footer;
    }
}
1;