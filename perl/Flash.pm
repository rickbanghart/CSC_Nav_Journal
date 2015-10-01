#
# $Id: Flash.pm,v 1.14 2009/02/01 18:03:06 banghart Exp $
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

package Apache::Flash;
# File: Apache/Flash.pm

# this module delivers responses to requests from the Flash application
# Also now is used for AJAX functions.
# Eventually, everything returned should be in an XML document
# some things may be fine with URL encoding (field=value)
# changing from XML documents to JSON encoding of data
use strict;
use Apache::Constants qw(:common);
#!/usr/bin/perl 

use CGI;
use Config;
$Config{useithreads} or die('Recompile Perl with threads to run this program.');
use threads;
use Apache::Promse;
use XML::DOM;
use XML::Parser;
use JSON::XS;

#use Apache::Design;
sub handler {
    my $r = new CGI;
    &Apache::Promse::validate_user($r); #sets environment variables.
    my $action;
    $action = $env{'action'};
    my $variable = $r->param('variable');
    my $profile = &Apache::Promse::get_user_profile($env{'user_id'});
    $env{'photo'} = $$profile{'photo'};
    print STDERR "\n ****** \n $action is action \n ****** \n";
    if ($action eq 'getdistricts' || $action eq 'getalldistricts' ) {
        &get_districts($r);
        # used to be the html calls, now Flash calls
        #my @districts = &Apache::Promse::get_districts();
        #&return_districts($r, \@districts);
	} elsif ($action eq 'getactivityreport') {
	    &get_activity_report($r);
    } elsif ($action eq 'getcurriculaJSON') {
        getCurriculaJSON($r);
    } elsif ($action eq 'getdelayedxml') {
        my $file_name = $r->param('filename');
        my $upload_dir = "/var/www/html/images/userpics";
        &xml_header($r);
        if (open TEMPXML, "<$upload_dir/$file_name") {
            while (my $line = <TEMPXML>) {
                $r->print($line);
            }
            close TEMPXML;
        } else {
            $r->print('<response filename="' . $file_name . '" check="true">working</response>');
        } 
    } elsif ($action eq 'importunit') {
        &import_unit($r);
    } elsif ($action eq 'geteliminatedthemes') {
        &get_curriculum($r);
    } elsif ($action eq 'getlockstatus') {
        &get_lock_status($r);
    } elsif ($action eq 'assigntemplate') {
        &assign_template($r);
    } elsif ($action eq 'completegrade') {
        my %fields = ('time_finished'=>' NOW() ',
                    'grade_id'=>$r->param('grade'),
                    'curriculum_id'=>$r->param('curriculumid'));
        &Apache::Promse::save_record('cc_curriculum_grade_completed',\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<response>ok</response>');
    } elsif ($action eq 'togglediscussionfavorite') {
        my $user_id = $env{'user_id'};
        my $discussion_id = $r->param('discussionid');
        my $qry = "SELECT COUNT(*) as count FROM kb_discussion_favorites 
                    WHERE user_id = $user_id AND
                          discussion_id = $discussion_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $row = $rst->fetchrow_hashref();
        if ($$row{'count'}) {
            $qry = "DELETE FROM kb_discussion_favorites 
                    WHERE user_id = $user_id AND
                          discussion_id = $discussion_id";
            $env{'dbh'}->do($qry);
        } else {
            my %fields = ('user_id'=>$user_id,
                          'discussion_id'=>$discussion_id);
           &Apache::Promse::save_record('kb_discussion_favorites',\%fields,0);
        }       
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<response>ok</response>');
    } elsif ($action eq 'getframework') {
        &get_framework($r);
    } elsif ($action eq 'getlessontags') {
        &get_lesson_tags($r);
    } elsif ($action eq 'getthemesforcoding') {
        my $curriculum_id = $r->param('curriculumid');
        my $grade = $r->param('grade');
        my $subject = $r->param('subject');
        my $themes = &get_themes_for_coding($subject, $curriculum_id, $grade);
        my $xml_doc = XML::DOM::Document->new;
        my $themes_xml = $xml_doc->createElement('themes');
        $themes_xml->setAttribute('curriculumid',$curriculum_id);
        $themes_xml->setAttribute('grade',$grade);
        my $current_unit = 0;
        my $current_theme = 0;
        my $unit_xml;
        my $theme_xml;
        my $in_unit = 0;
        my $in_theme = 0;
        foreach my $theme(@$themes) {
            if ($current_unit ne $$theme{'unit_id'}) {
                if ($in_unit) {
                    if ($in_theme) {
                        $unit_xml->appendChild($theme_xml);
                        $in_theme = 0;
                    }
                    $themes_xml->appendChild($unit_xml);
                    $in_unit = 0;
                }
                $unit_xml = $xml_doc->createElement('unit');
                $in_unit = 1;
                $unit_xml->setAttribute('unitid',$$theme{'unit_id'});
                my $unit_title_element = $xml_doc->createElement('title');
                my $unit_title_text = $xml_doc->createTextNode($$theme{'unit_title'});
                $unit_title_element->appendChild($unit_title_text);
                $unit_xml->appendChild($unit_title_element);
                my $unit_description_element = $xml_doc->createElement('description');
                my $unit_description_text = $xml_doc->createTextNode($$theme{'unit_description'});
                $unit_description_element->appendChild($unit_description_text);
                $unit_xml->appendChild($unit_description_element);
                $current_unit = $$theme{'unit_id'};
                $theme_xml = $xml_doc->createElement('theme');
                $theme_xml = &build_theme_xml($xml_doc,$theme_xml,$theme);
                $in_theme = 1;
                $current_theme = $$theme{'theme_id'};
            } else {
                if ($current_theme ne $$theme{'theme_id'}) {
                    if ($in_theme) {
                        $unit_xml->appendChild($theme_xml);
                    }
                    $theme_xml = $xml_doc->createElement('theme');
                    $theme_xml = &build_theme_xml($xml_doc,$theme_xml,$theme);
                    $in_theme = 1;
                    $current_theme = $$theme{'theme_id'};
                } else { # must be a new tag here
                    my $tag_element = $xml_doc->createElement('tag');
                    $tag_element->setAttribute('principleid',$$theme{'principle_id'});
                    my $tag_text_node = $xml_doc->createTextNode($$theme{'principle'});
                    $tag_element->appendChild($tag_text_node);
                    $theme_xml->appendChild($tag_element);
                }
            }
        }
        if ($in_theme) {
            $unit_xml->appendChild($theme_xml);
        }
        if ($in_unit) {
            $themes_xml->appendChild($unit_xml);
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($themes_xml->toString);
    } elsif ($action eq 'saveeliminatelesson') {
        &save_lesson_history($r);
        my $eliminated = $r->param('eliminated');
        my %fields = ('eliminated'=>$eliminated,
                      'lesson_notes'=>Apache::Promse::fix_quotes($r->param('lessonnotes')));
        my %id = ('id'=>$r->param('lessonid'));
        &Apache::Promse::update_record('cc_themes',\%id,\%fields);
        &xml_header($r);
        $r->print('<return>ok</return>');
    } elsif ($action eq 'getquestions') {
        my $filter = $r->param('filter');
        my $sort_direction = $r->param('sortdirection');# asc or desc
        my $sort_field = $r->param('sortfield'); # date, subject, lastname, etc
        my $questions = &Apache::Promse::get_questions($filter, $sort_field, $sort_direction);
        my $xml_doc = XML::DOM::Document->new;
        my $questions_xml = $xml_doc->createElement('questions');
        #$questions_xml->setAttribute('curriculumid',$curriculum_id);
        #$questions_xml->setAttribute('grade',$grade);
        # date, subject, lastname
        foreach my $question(@$questions) {
            my $question_element = $xml_doc->createElement('question');
            $question_element->setAttribute('questionid', $$question{'question_id'});
            $question_element->setAttribute('isread', $$question{'is_read'});
            $question_element->setAttribute('date', $$question{'date'});
            my $subject_element = $xml_doc->createElement('subject');
            my $subject_text_node = $xml_doc->createTextNode($$question{'subject'});
            $subject_element->appendChild($subject_text_node);
            $question_element->appendChild($subject_element);
            my $content_element = $xml_doc->createElement('content');
            my $content_text_node = $xml_doc->createTextNode($$question{'content'});
            $content_element->appendChild($content_text_node);
            $question_element->appendChild($content_element);
            $questions_xml->appendChild($question_element);
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($questions_xml->toString);
    } elsif ($action eq 'getdiscussions') {
        my $role = $r->param('role');
        my $qry;
        my $where_clause;
#        &Apache::Promse::logthis('******  below is role *********');
#        &Apache::Promse::logthis($role);
        if ($role eq 'mentor') {    
            $where_clause = "";
        } else {
            # teachers now see all questions
            $where_clause = "";
            # $where_clause = " AND kb_discussions.author = $env{'user_id'} ";
        }
        my $user_id = $env{'user_id'};
        $qry = "SELECT kb_discussions.id as discussion_id, kb_discussions.grade, 
                    DATE_FORMAT(kb_discussions.date,'%c/%e/%Y %l:%i%p') as discussion_date, users.FirstName as first_name,
                    UNIX_TIMESTAMP(kb_discussions.date) as discussion_utcdate,
                    UNIX_TIMESTAMP(kb_messages.date) as message_utcdate,
                    users.photo as photo, kb_discussion_favorites.user_id as favorite,
                    cc_themes.description as lesson_description,
                    cc_units.grade_id as lesson_grade,
                    kb_discussions.title as discussion_title, kb_discussions.answer as discussion_answer,
                    kb_discussions.question as discussion_question, kb_discussions.lesson_id as lesson_id,
                    kb_discussions.is_complete as is_complete,kb_discussions.is_published as is_published,
                    users.LastName as last_name, kb_messages.is_draft as is_draft,
                    kb_discussions.author, kb_messages.user_id, kb_messages.subject as subject,
                    kb_messages.id as message_id, kb_messages.date as message_date, kb_messages.discussion_id,
                    DATE_FORMAT(kb_messages.date,'%c/%e/%Y %l:%i%p') as pretty_date,
                    kb_messages.is_sent, kb_messages.is_read,
                    kb_messages.content as message_content
                  FROM (kb_discussions, users)
                  LEFT JOIN kb_messages ON kb_messages.discussion_id = kb_discussions.id
                  LEFT JOIN kb_discussion_favorites ON (kb_discussion_favorites.discussion_id = kb_discussions.id AND
                                                       (kb_discussion_favorites.user_id = $user_id))
                  LEFT JOIN (cc_themes, cc_units) ON (cc_themes.id = kb_discussions.lesson_id) AND
                                                     (cc_themes.unit_id = cc_units.id)
                  WHERE users.id = kb_messages.user_id
                  $where_clause
                  ORDER BY kb_discussions.date DESC, kb_messages.discussion_id, kb_messages.date ASC";
        my $rst = $env{'dbh'}->prepare($qry);
        #&Apache::Promse::logthis('******');
        #&Apache::Promse::logthis($qry);
        $rst->execute();
        my $xml_doc = XML::DOM::Document->new;
        my $discussions_root = $xml_doc->createElement('discussions');
        my $current_discussion = -1;
        my $in_discussion = 0;
        my $discussion_element;
        my $message_element;
        my $question_element;
        my $answer_element;
        my $answer_text_node;
        my $question_text_node;
        my $title_element;
        my $title_text_node;
        my $first = 1;
        while (my $row = $rst->fetchrow_hashref()) {
            if ($first) {
                $first = 0;
                $discussions_root->setAttribute('now',time());
            }
            if ($current_discussion ne $$row{'discussion_id'}) {
                if ($in_discussion) {
                    $discussions_root->appendChild($discussion_element);
                }  
                $discussion_element = $xml_doc->createElement('discussion');
                $discussion_element->setAttribute('id',$$row{'discussion_id'});
                $discussion_element->setAttribute('date',$$row{'discussion_date'});
                $discussion_element->setAttribute('utcdate',time());
                $discussion_element->setAttribute('discussionutcdate',$$row{'discussion_utcdate'});
                $discussion_element->setAttribute('fromid',$$row{'author'});
                $discussion_element->setAttribute('photo',$$row{'photo'});
                if ($$row{'favorite'}) {
                    $discussion_element->setAttribute('favorite','true');
                } else {
                    $discussion_element->setAttribute('favorite','false');
                }
                my $lesson_id = $$row{'lesson_id'}?$$row{'lesson_id'}:0;
                $discussion_element->setAttribute('lessonid',$lesson_id);
                $discussion_element->setAttribute('iscomplete',$$row{'is_complete'});
                $discussion_element->setAttribute('ispublished',$$row{'is_published'});
                $title_element = $xml_doc->createElement('title');
                $title_text_node = $xml_doc->createTextNode($$row{'discussion_title'});
                $title_element->appendChild($title_text_node);
                $discussion_element->appendChild($title_element);
                if ($lesson_id) {
                    my $lesson_element = $xml_doc->createElement('lesson');
                    $lesson_element->setAttribute('grade', $$row{'grade'});
                    my $lesson_text = $xml_doc->createTextNode($$row{'lesson_description'});
                    $lesson_element->appendChild($lesson_text);
                    $discussion_element->appendChild($lesson_element);
                }
                $question_element = $xml_doc->createElement('question');
                $question_text_node = $xml_doc->createTextNode($$row{'discussion_question'});
                $question_element->appendChild($question_text_node);
                $answer_element = $xml_doc->createElement('answer');
                $answer_text_node = $xml_doc->createTextNode($$row{'discussion_answer'});
                $answer_element->appendChild($answer_text_node);
                $discussion_element->appendChild($question_element);
                $discussion_element->appendChild($answer_element);
                $current_discussion = $$row{'discussion_id'};
                $in_discussion = 1;
            }
            $message_element = $xml_doc->createElement('message');
            $message_element->setAttribute('id', $$row{'message_id'});
            $message_element->setAttribute('issent', $$row{'is_sent'});
            $message_element->setAttribute('isdraft', $$row{'is_draft'});
            $message_element->setAttribute('photo', $$row{'photo'});
            $message_element->setAttribute('isread', $$row{'is_read'});
            $message_element->setAttribute('date', $$row{'message_date'});
            $message_element->setAttribute('messageutcdate',$$row{'message_utcdate'});
            $message_element->setAttribute('prettydate', $$row{'pretty_date'});
            $message_element->setAttribute('fromid', $$row{'user_id'});
            $message_element->setAttribute('from', $$row{'first_name'} . " " . $$row{'last_name'});
            my $message_text_node = $xml_doc->createTextNode($$row{'message_content'});
            $message_element->appendChild($message_text_node);
            my $subject_element = $xml_doc->createElement('subject');
            my $subject_text_node = $xml_doc->createTextNode($$row{'subject'});
            $subject_element->appendChild($subject_text_node);
            $message_element->appendChild($subject_element);
            $discussion_element->appendChild($message_element);
        }
        if ($in_discussion) {
            $discussions_root->appendChild($discussion_element);
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($discussions_root->toString);
    } elsif ($action eq 'markasread') {
        my %fields = ('is_read'=>1);
        my %ids = ('id'=>$r->param('messageid'));
        &Apache::Promse::update_record('kb_messages',\%ids,\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<response>OK</response>');
    } elsif ($action eq 'updatediscussion') {
        my %fields = ('question'=>&Apache::Promse::fix_quotes($r->param('question')),
                      'answer'=>&Apache::Promse::fix_quotes($r->param('answer')));
        my %idfields = ('id'=>$r->param('discussionid'));
        &Apache::Promse::update_record('kb_discussions',\%idfields,\%fields);              
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<response>OK</response>');
    } elsif ($action eq 'sendmessage') {
        my %fields;
        my %ids;
        my $discussion_id;
        my $is_draft;
        my $is_sent;
        if ($r->param('isdraft')) {
            $is_draft = 1;
            $is_sent = 0;
        } else {
            $is_draft = 0;
            $is_sent = 1;
        }
        if ($r->param('messageaction') ne 'update') {
            # we're  not updating an existing message
            if ($r->param('messageaction') eq 'startdiscussion') {
                # not continuing a previous discussion'
                %fields = ('author'=>$env{'user_id'},
                        'lesson_id'=>$r->param('lessonid'),
                        'question'=>&Apache::Promse::fix_quotes($r->param('content')),
                        'title'=>&Apache::Promse::fix_quotes($r->param('subject')),
                        'grade'=>$r->param('grade'),
                        'date'=>' now() ');
                $discussion_id = &Apache::Promse::save_record('kb_discussions',\%fields, "id");
            } else {
                $discussion_id = $r->param('discussionid');
            }
            %fields = ('discussion_id'=>$discussion_id,
                      'user_id'=>$env{'user_id'},
                      'content'=>&Apache::Promse::fix_quotes($r->param('content')),
                      'subject'=>&Apache::Promse::fix_quotes($r->param('subject')),
                      'is_draft'=>$is_draft,
                      'is_sent'=>$is_sent,
                      'date'=>' now() '
                     );
            my $message_id = &Apache::Promse::save_record('kb_messages', \%fields, "id");
        } else { # comes here only to update 
            %fields = (
                  'content'=>&Apache::Promse::fix_quotes($r->param('content')),
                  'subject'=>&Apache::Promse::fix_quotes($r->param('subject')),
                  'is_draft'=>$is_draft,
                  'is_sent'=>$is_sent,
                  'date'=>' now() '
                 );
            %ids = ('id'=>$r->param('messageid'));
            &Apache::Promse::update_record('kb_messages',\%ids,\%fields);
        }
        # FIX ME - the following is pointless
        my $xml_doc = XML::DOM::Document->new;
        my $root_xml = $xml_doc->createElement('root');
        my $text_node = $xml_doc->createTextNode('something ' . $discussion_id);
        $root_xml->appendChild($text_node);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($root_xml->toString);
    } elsif ($action eq 'getthemesbytag') {
        my $curriculum_id = $r->param('curriculumid');
        my $grade = $r->param('grade');
        my $themes = &get_themes_by_tag($r);
        my $xml_doc = XML::DOM::Document->new;
        my $themes_xml = $xml_doc->createElement('themes');
        $themes_xml->setAttribute('curriculumid',$curriculum_id);
        $themes_xml->setAttribute('grade',$grade);
        my $current_unit = 0;
        my $current_theme = 0;
        my $unit_xml;
        my $theme_xml;
        my $in_unit = 0;
        my $in_theme = 0;
        foreach my $theme(@$themes) {
            if ($current_unit ne $$theme{'unit_id'}) {
                if ($in_unit) {
                    if ($in_theme) {
                        $unit_xml->appendChild($theme_xml);
                        $in_theme = 0;
                    }
                    $themes_xml->appendChild($unit_xml);
                    $in_unit = 0;
                }
                $unit_xml = $xml_doc->createElement('unit');
                $in_unit = 1;
                $unit_xml->setAttribute('unitid',$$theme{'unit_id'});
                my $unit_title_element = $xml_doc->createElement('title');
                my $unit_title_text = $xml_doc->createTextNode($$theme{'unit_title'});
                $unit_title_element->appendChild($unit_title_text);
                $unit_xml->appendChild($unit_title_element);
                my $unit_description_element = $xml_doc->createElement('description');
                my $unit_description_text = $xml_doc->createTextNode($$theme{'unit_description'});
                $unit_description_element->appendChild($unit_description_text);
                $unit_xml->appendChild($unit_description_element);
                $current_unit = $$theme{'unit_id'};
                $theme_xml = $xml_doc->createElement('theme');
                $theme_xml = &build_theme_xml($xml_doc,$theme_xml,$theme);
                $in_theme = 1;
                $current_theme = $$theme{'theme_id'};
            } else {
                if ($current_theme ne $$theme{'theme_id'}) {
                    if ($in_theme) {
                        $unit_xml->appendChild($theme_xml);
                    }
                    $theme_xml = $xml_doc->createElement('theme');
                    $theme_xml = &build_theme_xml($xml_doc,$theme_xml,$theme);
                    $in_theme = 1;
                    $current_theme = $$theme{'theme_id'};
                } else { # must be a new tag here
                    my $tag_element = $xml_doc->createElement('tag');
                    $tag_element->setAttribute('principleid',$$theme{'principle_id'});
                    my $tag_text_node = $xml_doc->createTextNode($$theme{'principle'});
                    $tag_element->appendChild($tag_text_node);
                    $theme_xml->appendChild($tag_element);
                }
            }
        }
        if ($in_theme) {
            $unit_xml->appendChild($theme_xml);
        }
        if ($in_unit) {
            $themes_xml->appendChild($unit_xml);
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($themes_xml->toString);
    } elsif ($action eq 'toggletaggedtheme') {
        my $theme_id = $r->param('themeid');
        my $qry = "select tagged from cc_themes where id = $theme_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $row = $rst->fetchrow_hashref();
        my $return_message = '';
        if ($$row{'tagged'} eq 1 ) {
            $qry = "update cc_themes set tagged = 0 where id = $theme_id";
            $return_message = 'false';
        } else {
            $qry = "update cc_themes set tagged = 1 where id = $theme_id";
            $return_message = 'true';
        }
        $env{'dbh'}->do($qry);
        &xml_header($r);
        $r->print('<response tagged="' . $return_message . '">ok</response>');
    } elsif ($action eq 'savetagnote') {
        my $theme_id = $r->param('themeid');
        my $pf_end_id = $r->param('pfendid');
        my $strength = $r->param('strength');
        my $notes = &Apache::Promse::fix_quotes($r->param('notes'));
        my $qry = "UPDATE cc_pf_theme_tags set notes = $notes, strength = $strength WHERE theme_id = $theme_id and pf_end_id = $pf_end_id";
        $env{'dbh'}->do($qry);
        &xml_header($r);
        $r->print('<response>ok</response>');
    } elsif ($action eq 'getfilterednames') {
        my $filter = $r->param('filter');
        my $records = $r->param('records');
        my $where_clause = " WHERE lastname LIKE '" . $filter . "%' ";
        my $qry = "select users.id, lastname, firstname, active, ";
        $qry .= "(select group_concat(roles.role) from userroles, roles where userroles.user_id  = users.id and roles.id = userroles.role_id) as roles from users ";
        $qry .= $where_clause." order by lastname, firstname LIMIT $records";
        my $sth = $env{'dbh'}->prepare($qry) or &logthis($Mysql::db_errstr);
        $sth->execute();
        my $light_color = ' class="adminFormRow" ';
        my $dark_color = ' class="adminFormRowAlternate" ';
        my $row_color = $light_color;
        print $r->header(-type => 'text/plain');
		my @roles = &Apache::Promse::get_roles();
        while (my $row = $sth->fetchrow_hashref) {
            my $user_id = $$row{'id'};
            my $roles = $$row{'roles'};
            $roles = !$roles?'none':$roles;
			foreach my $role(@roles) {
				if ($roles =~ m/$$role{'role'}/) {
					$$role{'checked'} = ' checked ';
				} else {
					$$role{'checked'} = '';
				}
			}
            my $display_name = $$row{'lastname'}.', '.$$row{'firstname'};
            $r->print('<form method="post" action="">');
            $r->print('<div '.$row_color.'>'."\n");
            
            $r->print('<div class="adminFormColHeadName">');
            $r->print('<a href="admin?userid='.$user_id.'&amp;menu=users&amp;submenu=edituser&amp;token='.$env{'token'}.'"><span>'.$display_name.'</span></a>');
            $r->print('</div>'."\n");
	        foreach my $role(@roles) {
				$r->print(&Apache::Promse::make_admin_form_checkbox($role));
			}
            $r->print('<div class="adminFormColHeadButton">');
            $r->print( '<input class="adminFormSubmit" type="submit" name="action" value="update" />');
            $r->print('</div>'."\n");
            my $activate_msg = $$row{'active'}?'Active':'Inactive';
            
            $r->print('<div class="adminFormColHeadButton">');
            $r->print( '<input class="adminFormSubmit" type="submit" name="action" value="'.$activate_msg.'" />');
            $r->print('</div>'."\n");
           
            $r->print('</div>'."\n"); # end the row div 
            
            if ($row_color eq $light_color){
                $row_color = $dark_color;
            } else {
                $row_color = $light_color;
            }
            my %fields = ('userid'=>$$row{'id'},
                          'menu'=>'users',
                          'submenu'=>'roles',
                          'letter'=>$filter
                         );
            $r->print(&Apache::Promse::hidden_fields(\%fields));
            $r->print('</form>');
        }
        
    } elsif ($action eq 'linkcurriculumdistrict') {
        &link_curriculum_district($r);
    } elsif ($action eq 'pftagtheme') {
        &pf_tag_theme($r);
    } elsif ($action eq 'getuncodedthemes') {
        &get_uncoded_themes($r);
    } elsif ($action eq 'getsciencedisplayxml') {
        &get_science_display_by_principle($r);
    } elsif ($action eq 'getcurriculumgrades') {
        &get_curriculum_grades($r);
    } elsif ($action eq 'getcurriculum') {
        &get_curriculum_changes($r);
    } elsif ($action eq 'getpromsemathframeworkxml') {
        &get_promse_math_framework_xml($r);
    } elsif ($action eq 'gettimssmathframeworkxml') {
        &get_timss_math_framework_xml($r);
    } elsif ($action eq 'getexistingtags') {
        &get_existing_tags($r);
        return('ok');
    } elsif ($action eq 'getcodedthemes') {
        &get_coded_themes($r);
        return('ok');
    } elsif ($action eq 'insertpartner') {
        my %fields = ('partner_name'=>&Apache::Promse::fix_quotes($r->param('partner')),
                      'state'=>&Apache::Promse::fix_quotes($r->param('state')));
        my $partner_id = &Apache::Promse::save_record('partners',\%fields,"id");
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>$partner_id</response>"); 
        return('ok');       
    } elsif ($action eq 'updatepartner') {
        my $partner_id = $r->param('partnerid');
        my %fields = ('partner_name'=>&Apache::Promse::fix_quotes($r->param('partner')),
                      'state'=>&Apache::Promse::fix_quotes($r->param('state')));
        my %id = ('partner_id'=>$partner_id);
        &Apache::Promse::update_record('partners',\%id,\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>$partner_id</response>");        
    } elsif ($action eq 'deletepartner') {
        my $partner_id = $r->param('partnerid');
        my $qry = "DELETE FROM partners WHERE partner_id = $partner_id";
        $env{'dbh'}->do($qry);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>ok</response>");        
    } elsif ($action eq 'deletedistrict') {
        my $district_id = $r->param('districtid');
        my $qry = "DELETE FROM districts WHERE district_id = $district_id";
        $env{'dbh'}->do($qry);
        $qry = "DELETE FROM locations WHERE district_id = $district_id";
        $env{'dbh'}->do($qry);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>ok</response>");        
    } elsif ($action eq 'deletelocation') {
        my $location_id = $r->param('locationid');
        my $qry = "DELETE FROM locations WHERE location_id = $location_id";
        $env{'dbh'}->do($qry);
        $qry = "DELETE FROM user_locs WHERE loc_id = $location_id";
        $env{'dbh'}->do($qry);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>ok</response>");        
    } elsif ($action eq 'updatelocation') {
        my $NCESID = $r->param('NCESID')?$r->param('NCESID'):0;
        my $stateSchoolID = $r->param('stateSchoolID')?$r->param('stateSchoolID'):0;
        my $stateAgencyID = $r->param('stateAgencyID')?$r->param('stateAgencyID'):0;
        my $elem = $r->param('elem')?$r->param('elem'):0;
        my $middle = $r->param('middle')?$r->param('middle'):0;
        my $high = $r->param('high')?$r->param('high'):0;
        my $district_id = $r->param('districtID')?$r->param('districtID'):0;
        my %fields = ("school"=>&Apache::Promse::fix_quotes($r->param('school')),
                      "Grade_range"=>&Apache::Promse::fix_quotes($r->param('gradeRange')),
                      "NCES_ID"=>$NCESID,
                      "State_school_id"=>$stateSchoolID,
                      "State_agency_id"=>$stateAgencyID,
                      "district_id"=>$district_id,
                      "address"=>&Apache::Promse::fix_quotes($r->param('address')),
                      "city"=>&Apache::Promse::fix_quotes($r->param('city')),
                      "zip"=>&Apache::Promse::fix_quotes($r->param('zip')),
                      "principal"=>&Apache::Promse::fix_quotes($r->param('principal')),
                      "phone"=>&Apache::Promse::fix_quotes($r->param('phone')),
                      "elem"=>$elem,
                      "middle"=>$middle,
                      "high"=>$high);
        my %id = ('location_id'=>$r->param('locationID'));
        my $location_id = &Apache::Promse::update_record('locations',\%id,\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>ok</response>");        
    } elsif ($action eq 'insertdistrict') {
        my $partner_id = $r->param('partnerID')?$r->param('partnerID'):0;
        my $county_num = $r->param('countyNum')?$r->param('countyNum'):0;
        my $reduced_lunch = $r->param('reducedLunch')?$r->param('reducedLunch'):0;
        my $free_lunch = $r->param('freeLunch')?$r->param('freeLunch'):0;
        my $students = $r->param('students')?$r->param('students'):0;
        my $agency_type = $r->param('agencyType')?$r->param('agencyType'):0;
        my %fields = ("district_name"=>&Apache::Promse::fix_quotes($r->param('name')),
                      "county"=>&Apache::Promse::fix_quotes($r->param('county')),
                      "partner_id"=>$partner_id,
                      "county_num"=>$county_num,
                      "agency_type"=>$agency_type,
                      "students"=>$students,
                      "district_alt_name"=>&Apache::Promse::fix_quotes($r->param('districtAltName')),
                      "free_lunch"=>$free_lunch,
                      "reduced_lunch"=>$reduced_lunch);
        my $district_id = &Apache::Promse::save_record('districts',\%fields,"id");
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>$district_id</response>");        
    } elsif ($action eq 'updatedistrict') {
        my $partner_id = $r->param('partnerID')?$r->param('partnerID'):0;
        my $county_num = $r->param('countyNum')?$r->param('countyNum'):0;
        my $reduced_lunch = $r->param('reducedLunch')?$r->param('reducedLunch'):0;
        my $free_lunch = $r->param('freeLunch')?$r->param('freeLunch'):0;
        my $students = $r->param('students')?$r->param('students'):0;
        my $agency_type = $r->param('agencyType')?$r->param('agencyType'):0;
        my $district_id = $r->param('districtID');
        my %fields = ("district_name"=>&Apache::Promse::fix_quotes($r->param('name')),
                      "county"=>&Apache::Promse::fix_quotes($r->param('county')),
                      "partner_id"=>$partner_id,
                      "county_num"=>$county_num,
                      "agency_type"=>$agency_type,
                      "students"=>$students,
                      "district_alt_name"=>&Apache::Promse::fix_quotes($r->param('districtAltName')),
                      "free_lunch"=>$free_lunch,
                      "reduced_lunch"=>$reduced_lunch);
        my %id = ('district_id'=>$district_id);
        &Apache::Promse::update_record('districts',\%id,\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>ok</response>");        
    } elsif ($action eq 'insertlocation') {
        my $NCESID = $r->param('NCESID')?$r->param('NCESID'):0;
        my $stateSchoolID = $r->param('stateSchoolID')?$r->param('stateSchoolID'):0;
        my $stateAgencyID = $r->param('stateAgencyID')?$r->param('stateAgencyID'):0;
        my $elem = $r->param('elem')?$r->param('elem'):0;
        my $middle = $r->param('middle')?$r->param('middle'):0;
        my $high = $r->param('high')?$r->param('high'):0;
        my $district_id = $r->param('districtID')?$r->param('districtID'):0;
        my %fields = ("school"=>&Apache::Promse::fix_quotes($r->param('school')),
                      "Grade_range"=>&Apache::Promse::fix_quotes($r->param('gradeRange')),
                      "NCES_ID"=>$NCESID,
                      "State_school_id"=>$stateSchoolID,
                      "State_agency_id"=>$stateAgencyID,
                      "district_id"=>$district_id,
                      "address"=>&Apache::Promse::fix_quotes($r->param('address')),
                      "city"=>&Apache::Promse::fix_quotes($r->param('city')),
                      "zip"=>&Apache::Promse::fix_quotes($r->param('zip')),
                      "principal"=>&Apache::Promse::fix_quotes($r->param('principal')),
                      "phone"=>&Apache::Promse::fix_quotes($r->param('phone')),
                      "elem"=>$elem,
                      "middle"=>$middle,
                      "high"=>$high);
        my $location_id = &Apache::Promse::save_record('locations',\%fields,"id");
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>$location_id</response>");        
    } elsif ($action eq 'getlocations') {
        &get_locations($r);
    } elsif ($action eq 'getdistrictscores') {
        &return_nodes($r);
    } elsif ($action eq 'getdistrictintended') {
        &return_district_intended($r);
    } elsif ($action eq 'showvidslide') {
        vid_slide_html($r);
    } elsif ($action eq 'getimplemented') {
        &return_implemented($r);
    } elsif ($action eq 'savenotebook') {
        &save_notebook($r);
    } elsif ($action eq 'getPage') {
        &get_notebook_page($r);
    } elsif ($action eq 'addpage') {
        &add_notebook_page($r);
    } elsif ($action eq 'getdistrictschools') {
        &return_district_schools_select($r);
    } elsif ($action eq 'getlocationrecord') {
        &return_location_record($r);
    } elsif ($action eq 'getdistrictrecord') {
        &return_district_record($r);
#    } elsif ($action eq 'getpartners') { used for html call, replaced by Flash call elsewhere
#        &return_partners_select($r);
    } elsif ($action eq 'getagencytypes') {
        &return_agency_types_select($r);
    } elsif ($action eq 'getgraphiclist') {
        &get_graphic_list($r);
    } elsif ($action eq 'getdistrictschoolsbygrade') {
        &return_district_schools_by_grade_select($r);
        # returns select populated only by schools with selected grade
    } elsif ($action eq 'linkmaterialdistrict') {
        &link_material_district($r);
    } elsif ($action eq 'getpartners') {
        &get_partners($r);
        
    } elsif ($action eq 'getprintsciencebycurriculum') {
        &get_print_science_by_curriculum($r);
    } elsif ($action eq 'getprintmathbycurriculum') {
    } elsif ($action eq 'getunits') {
        my $curriculum_id = $r->param('curriculumid');
        my $grade;
        $grade = ($r->param('grade') eq 'K')?'0':$r->param('grade');
        $grade = ($r->param('grade') eq 'HS')?'9':$r->param('grade');
        my $qry = "SELECT count(*) AS count FROM cc_curriculum_grade_completed 
                WHERE grade_id = $grade AND curriculum_id = $curriculum_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $row = $rst->fetchrow_hashref();
        my $grade_completed = $$row{'count'}?'true':'false';
        my $units = &get_units($curriculum_id, $grade);
        #print $r->header('Content_type'=>'text/xml');
        print $r->header(-type => 'text/xml');
        my $doc = XML::DOM::Document->new;
        my $units_root_element = $doc->createElement('units');
        $units_root_element->setAttribute('completed',$grade_completed);
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        foreach my $unit(@$units) {
            my $period_duration = $$unit{'period_duration'}?$$unit{'period_duration'}:0;
            my $unit_element = $doc->createElement('unit');
            my $sequence_element = $doc->createElement('sequence');
            my $sequence_text = $doc->createTextNode($$unit{'sequence'});
            $sequence_element->appendChild($sequence_text);
            $unit_element->appendChild($sequence_element);
            my $periods_element = $doc->createElement('periods');
            my $periods_text = $doc->createTextNode($$unit{'periods'});
            $periods_element->appendChild($periods_text);
            $unit_element->appendChild($periods_element);
            my $period_duration_element = $doc->createElement('periodduration');
            my $period_duration_text = $doc->createTextNode($period_duration);
            $period_duration_element->appendChild($period_duration_text);
            $unit_element->appendChild($period_duration_element);
            my $unit_id_element = $doc->createElement('unitid');
            my $unit_id_text = $doc->createTextNode($$unit{'id'});
            $unit_id_element->appendChild($unit_id_text);
            $unit_element->appendChild($unit_id_element);
            my $title_element = $doc->createElement('title');
            my $title_text = $doc->createTextNode(&Apache::Promse::text_to_html($$unit{'title'}));
            $title_element->appendChild($title_text);
            $unit_element->appendChild($title_element);
            my $description_element = $doc->createElement('description');
            my $description_text = $doc->createTextNode(&Apache::Promse::text_to_html($$unit{'description'}));
            $description_element->appendChild($description_text);
            $unit_element->appendChild($description_element);
            $units_root_element->appendChild($unit_element);
        }
        $r->print($units_root_element->toString);
    } elsif ($action eq 'insertunit') {
        my $output;
        my $grade;
        $grade = $r->param('grade') eq 'K'?0:$r->param('grade');
        $grade = $grade eq 'HS'?9:$grade;
        my $next_unit_seq = &get_next_unit_seq($r);
        my $curriculum_id = $r->param('curriculumid');
        my $grade_id = $r->param('gradeid');
        my $title;
        my $period_duration = $r->param('periodduration')?$r->param('periodduration'):0;
        my $return_title;
        if(!$r->param('title')) {
            $return_title = "Unit $next_unit_seq (temporary name)";
        } else {
            $return_title = $r->param('title');
        }
        $title = &Apache::Promse::fix_quotes($r->param('title'));
        my %fields = ('grade_id'=>$grade,
                    'title'=>$title,
                    'description'=>&Apache::Promse::fix_quotes($r->param('description')),
                    'periods'=>$r->param('periods'),
                    'period_duration'=>$period_duration,
                    'curriculum_id'=>$curriculum_id,
                    'sequence'=>$next_unit_seq);
        
        my $unit_id = &Apache::Promse::save_record('cc_units',\%fields, 1);
        my $doc = XML::DOM::Document->new;
        my $responseElement = $doc->createElement('response');
        $responseElement->setAttribute('newid',$unit_id);
        $responseElement->setAttribute('sequence',$next_unit_seq);
        $responseElement->setAttribute('title',$return_title);
        &xml_header($r);
        $r->print($responseElement->toString);
    } elsif ($action eq 'inserttheme') {
        my $output;
        my $unit_id = $r->param('unitid');
        my $next_theme_seq = &get_next_theme_seq($r);
        my $title;
        my $period_duration = $r->param('periodduration')?$r->param('periodduration'):0;
        if(!$r->param('title')) {
            $title = &Apache::Promse::fix_quotes("Theme $next_theme_seq (temporary name)");
        } else {
            $title = &Apache::Promse::fix_quotes($r->param('title'));
        }
        my %fields = ('unit_id'=>$unit_id,
                    'title'=>$title,
                    'periods'=>$r->param('periods'),
                    'period_duration'=>$period_duration,
                    'supporting_activity'=>$r->param('supportingactivity'),
                    'description'=>&Apache::Promse::fix_quotes($r->param('description')),
                    'sequence'=>$next_theme_seq);
        my $theme_id = &Apache::Promse::save_record('cc_themes',\%fields, 1);
        my $doc = XML::DOM::Document->new;
        my $response_element = $doc->createElement('response');
        $response_element->setAttribute('newid', $theme_id);
        $response_element->setAttribute('sequence', $next_theme_seq);
        &xml_header($r);
        $r->print($response_element->toString);
    } elsif ($action eq 'getcurriculumtemplates') {
        &get_curriculum_templates($r);
    } elsif ($action eq 'getcurriculaselector') {
		my $curricula = &get_curricula($$profile{'district_id'}, $$profile{'subject'});
		my $doc = XML::DOM::Document->new();
		my $root = $doc->createElement('content');
		$root->setAttribute('destination', 'selectorItemsContainer');		
		foreach my $curriculum(@$curricula) {
			my $item = $doc->createElement('div');
			$item->setAttribute('class', 'selectorItem');
			$item->setAttribute('onclick', 'selectorClickHandler(this)');
			$item->setAttribute('itemtype', 'curriculum');
			$item->setAttribute('curriculumid', $$curriculum{'id'});
			my $itemTextNode = $doc->createTextNode($$curriculum{'title'});
			$item->appendChild($itemTextNode);
			$root->appendChild($item);
		}
        &xml_header($r);
		$r->print($root->toString());
    } elsif ($action eq 'getgradeselector') {
		my $curriculum_id = $r->param('curriculumid');
        my $qry = "SELECT DISTINCT cc_units.grade_id FROM cc_units, cc_themes
                    WHERE cc_units.curriculum_id = $curriculum_id
                     AND cc_themes.unit_id = cc_units.id
                    ORDER BY cc_units.grade_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
		my @grades;
        while (my $row = $rst->fetchrow_hashref) {
			push (@grades, {%$row});
        }
		my $doc = XML::DOM::Document->new();
		my $root = $doc->createElement('content');
		$root->setAttribute('destination', 'selectorItemsContainer');
		foreach my $grade(@grades) {
			my $item = $doc->createElement('div');
			$item->setAttribute('class', 'selectorItem');
			$item->setAttribute('onclick', 'selectorClickHandler(this)');
			$item->setAttribute('itemtype', 'grade');
			$item->setAttribute('gradeid', $$grade{'grade_id'});
			$item->setAttribute('curriculumid', $curriculum_id);
			my $gradeDisplay = ($$grade{'grade_id'} eq '0')?'K':$$grade{'grade_id'};
			my $itemTextNode = $doc->createTextNode('Grade ' . $gradeDisplay);
			$item->appendChild($itemTextNode);
			$root->appendChild($item);
		}
        &xml_header($r);
		$r->print($root->toString());
	} elsif ($action eq 'getunitselector') {
		my $curriculum_id = $r->param('curriculumid');
		my $grade_id = $r->param('gradeid');
        my $qry = "SELECT DISTINCT cc_units.title, cc_units.id FROM cc_units, cc_themes
                    WHERE cc_units.curriculum_id = $curriculum_id
                     AND cc_themes.unit_id = cc_units.id
                    ORDER BY cc_units.sequence";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
		my @units;
        while (my $row = $rst->fetchrow_hashref) {
			push (@units, {%$row});
        }
		my $doc = XML::DOM::Document->new();
		my $root = $doc->createElement('content');
		$root->setAttribute('destination', 'selectorItemsContainer');
		foreach my $unit(@units) {
			my $item = $doc->createElement('div');
			$item->setAttribute('class', 'selectorItem');
			$item->setAttribute('onclick', 'selectorClickHandler(this)');
			$item->setAttribute('itemtype', 'unit');
			$item->setAttribute('gradeid', $grade_id);
			$item->setAttribute('curriculumid', $curriculum_id);
			$item->setAttribute('unitid', $$unit{'id'});
			my $itemTextNode = $doc->createTextNode($$unit{'title'});
			$item->appendChild($itemTextNode);
			$root->appendChild($item);
		}
		&xml_header($r);
		$r->print($root->toString());
	} elsif ($action eq 'getlessonselector') {
		my $curriculum_id = $r->param('curriculumid');
		my $grade = $r->param('gradeid');
		my $unit_id = $r->param('unitid');
		my $lessons = &Apache::Promse::get_curriculum_grade_unit_lessons($unit_id);
		my $doc = XML::DOM::Document->new();
		my $root = $doc->createElement('content');
		$root->setAttribute('destination', 'selectorItemsContainer');
		foreach my $lesson(@$lessons) {
			my $lessonDiv = $doc->createElement('div');
			$lessonDiv->setAttribute('class','selectorItem');
			$lessonDiv->setAttribute('onclick','selectorClickHandler(this)');
			$lessonDiv->setAttribute('itemtype', 'lesson');
			$lessonDiv->setAttribute('curriculumid', $curriculum_id);
			$lessonDiv->setAttribute('gradeid', $grade);
			$lessonDiv->setAttribute('lessonid', $$lesson{'id'});
			$lessonDiv->setAttribute('title', $$lesson{'title'});
			my $lessonTextNode = $doc->createTextNode($$lesson{'title'});
			$lessonDiv->appendChild($lessonTextNode);
			$root->appendChild($lessonDiv);
		}
        &xml_header($r);
		$r->print($root->toString());
	} elsif ($action eq 'getlessondetail') {
		my $returnXML;
		my $lesson_id = $r->param('lessonid');
        my $qry = "SELECT t1.title, t1.description, t1.lesson_notes, cc_pf_theme_tags.pf_end_id, t1.sequence,
					cc_pf_theme_tags.strength, framework_items.title as code, cc_pf_theme_tags.notes,
				(select t2.id FROM cc_themes AS t2 WHERE t2.unit_id = t1.unit_id AND t2.sequence < t1.sequence ORDER BY t2.sequence DESC LIMIT 1) as prev,
				(select t2.id FROM cc_themes AS t2 WHERE t2.unit_id = t1.unit_id AND t2.sequence > t1.sequence ORDER BY t2.sequence ASC LIMIT 1) as next
				FROM cc_themes AS t1
				LEFT JOIN (framework_items, cc_pf_theme_tags) ON 
				(t1.id = cc_pf_theme_tags.theme_id and
				cc_pf_theme_tags.pf_end_id = framework_items.id)
				                    WHERE t1.id =$lesson_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
		my $row = $rst->fetchrow_hashref();
		my $previous_lesson = $$row{'prev'}?$$row{'prev'}:'none';
		my $next_lesson = $$row{'next'}?$$row{'next'}:'none';
		my $doc = XML::DOM::Document->new;
		my $root = $doc->createElement('lessondetails');
		$root->setAttribute('destination','multiple');
		my $content_item = $doc->createElement('content');
		$content_item->setAttribute('destination', 'lessonTitleContainer');
		$content_item->setAttribute('previousLesson', $previous_lesson);
		$content_item->setAttribute('nextLesson', $next_lesson);
		my $content_text_node = $doc->createTextNode($$row{'title'});
		$content_item->appendChild($content_text_node);
		$root->appendChild($content_item);
		$content_item = $doc->createElement('content');
		$content_item->setAttribute('destination', 'lessonDescriptionContainer');
		$content_text_node = $doc->createTextNode(  &Apache::Promse::text_to_html($$row{'description'}) );
		$content_item->appendChild($content_text_node);
		$root->appendChild($content_item);
		$content_item = $doc->createElement('content');
		$content_item->setAttribute('destination', 'lessonNoteContainer');
		$content_item->setAttribute('lessonid', $lesson_id);
		$content_text_node = $doc->createTextNode(  &Apache::Promse::text_to_html($$row{'lesson_notes'}) );
		$content_item->appendChild($content_text_node);
		$root->appendChild($content_item);
		if ($$row{'pf_end_id'}) {
			$content_item = $doc->createElement('content');
			$content_item->setAttribute('destination','lessonTagContainer');
			my $tagItem = $doc->createElement('tag');
			$tagItem->setAttribute('pfendid', $$row{'pf_end_id'});
			$tagItem->setAttribute('code', $$row{'code'});
			$tagItem->setAttribute('strength', $$row{'strength'});
			my $tagComment = $doc->createTextNode($$row{'notes'});
			$tagItem->appendChild($tagComment);
			$content_item->appendChild($tagItem);
			while ($row = $rst->fetchrow_hashref) {
				$tagItem = $doc->createElement('tag');
				$tagItem->setAttribute('pfendid', $$row{'pf_end_id'});
				$tagItem->setAttribute('code', $$row{'code'});
				$tagItem->setAttribute('strength', $$row{'strength'});
				$tagComment = $doc->createTextNode($$row{'notes'});
				$tagItem->appendChild($tagComment);
				$content_item->appendChild($tagItem);
			}
			$root->appendChild($content_item);
		}
		if ($r->param('standards') eq 'yes') {
			my ($standards, $hidden) = &get_standard_select($r,$doc);
			$root->appendChild($standards);
			$root->appendChild($hidden);
		}
        &xml_header($r);
        $r->print($root->toString());
	} elsif ($action eq 'updatelessonnote') {
		my $qry = "UPDATE cc_themes SET lesson_notes = ? WHERE cc_themes.id = ?";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute($r->param('lessonnote'), $r->param('lessonid'));
		my $doc = XML::DOM::Document->new;
		my $root = $doc->createElement('content');
		$root->setAttribute('destination', 'update');
		&xml_header($r);
		$r->print($root->toString());
	} elsif ($action eq 'getccstandards') {
		my $doc = XML::DOM::Document->new;
		my $root = $doc->createElement('content');
		$root->setAttribute('destination', 'multiple');
		my ($standards, $hidden) = &get_standard_select($r,$doc);
		$root->appendChild($standards);
		$root->appendChild($hidden);
        &xml_header($r);
        $r->print($root->toString());			
    } elsif ($action eq 'getcurricula') {
        my $district_id = $r->param('districtid');
        my $subject = $r->param('subject');
        my $curricula = &get_curricula($district_id, $subject);
        my $doc = XML::DOM::Document->new;
        my $curricula_root = $doc->createElement('curricula');
        my $first_row = 1;
        foreach my $curriculum(@$curricula) {
            if ($first_row eq 1) {
                $first_row = 0;
                $curricula_root->setAttribute('districtname',$$curriculum{'district_name'});
            }
            my $curriculum_element = $doc->createElement('curriculum');
            $curriculum_element->setAttribute('id', '2');
            my $curriculum_id_element = $doc->createElement('curriculumid');
            my $curriculum_id_text_node = $doc->createTextNode($$curriculum{'id'});
            $curriculum_id_element->appendChild($curriculum_id_text_node);
            $curriculum_element->appendChild($curriculum_id_element);
            my $curriculum_title_element = $doc->createElement('title');
            my $curriculum_title_text_node = $doc->createTextNode(&Apache::Promse::text_to_html($$curriculum{'title'}));
            $curriculum_title_element->appendChild($curriculum_title_text_node);
            $curriculum_element->appendChild($curriculum_title_element);
            my $curriculum_description_element = $doc->createElement('description');
            my $curriculum_description_text_node = $doc->createTextNode($$curriculum{'description'});
            $curriculum_description_element->appendChild($curriculum_description_text_node);
            $curriculum_element->appendChild($curriculum_description_element);
            $curricula_root->appendChild($curriculum_element);
        }
        &xml_header($r);
        $r->print($curricula_root->toString());
    } elsif ($action eq 'getallcurricula') {
        &get_all_curricula($r);
    } elsif ($action eq 'insertcurriculum') {
        my $subject = $env{'subject'};
        my %fields = ('title'=>&Apache::Promse::fix_quotes($r->param('title')),
                      'description'=>&Apache::Promse::fix_quotes($r->param('description')),
                      'is_template'=>$r->param('istemplate'),
                      'subject'=>&Apache::Promse::fix_quotes($subject));
        my $curriculum_id = &Apache::Promse::save_record('cc_curricula',\%fields,"id");
        %fields = ('curriculum_id'=>$curriculum_id,
                'district_id'=>$r->param('districtid'));
        &Apache::Promse::save_record('cc_curricula_districts',\%fields);     
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<return>$curriculum_id</return>");
    } elsif ($action eq 'updatecurriculum') {
        my %fields = ('title'=>&Apache::Promse::fix_quotes($r->param('title')),
                      'description'=>&Apache::Promse::fix_quotes($r->param('description')));
        my %id = ('id'=>$r->param('curriculumid'));
        &Apache::Promse::update_record('cc_curricula',\%id,\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<return>ok</return>');
    } elsif ($action eq 'deletecurriculum') {
        # must delete units, themes, chunks, etc.
        my $curriculum_id = $r->param('curriculumid');
        my $qry = "delete from cc_curricula where id = $curriculum_id";
        $env{'dbh'}->do($qry);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<return>ok</return>');
    } elsif ($action eq 'deletetheme') {
        &save_lesson_history($r);
        my %fields = ('eliminated'=>1);
        my %id = ('id'=>$r->param('themeid'));
        &Apache::Promse::update_record('cc_themes',\%id,\%fields);
#        
#        my $theme_id = $r->param('themeid');
#        my $qry;
#        $qry = "DELETE FROM cc_math_ideas WHERE id IN (select lesson_id as id FROM cc_lesson_ideas WHERE lesson_id = $theme_id) ";
#        $env{'dbh'}->do($qry);
#        $qry = "delete from cc_lesson_ideas where lesson_id = $theme_id";
#        $env{'dbh'}->do($qry);
#        $qry = "delete from cc_themes where id = $theme_id";
#        $env{'dbh'}->do($qry);
        &xml_header($r);
        $r->print('<return>deleted</return>');
    } elsif ($action eq 'updatetheme') {
        # first we save the current theme before updating it
        &save_lesson_history($r);
        my $qry;
        my $unit_id = $r->param('unitid');
        my $sequence;
        my $theme_id = $r->param('themeid');
        &dirty_flag($unit_id);
        $qry = "SELECT sequence from cc_themes where id = $theme_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $lesson = $rst->fetchrow_hashref();
        if ($r->param('sequence')) {
            # $sequence is 
            $sequence = $r->param('sequence');
            $qry = "UPDATE cc_themes SET sequence = sequence + 1 WHERE sequence >= $sequence AND unit_id = $unit_id";
            $env{'dbh'}->do($qry);
        } else {
            $sequence = $$lesson{'sequence'};
        }
        my %fields = ('title'=>&Apache::Promse::fix_quotes($r->param('title')),
                    'unit_id'=>$unit_id,
                    'sequence'=>$sequence,
                      'periods'=>$r->param('periods'),
                      'supporting_activity'=>$r->param('supportingactivity'),
                      'period_duration'=>$r->param('periodduration'),
                      'description'=>&Apache::Promse::fix_quotes($r->param('description')));
        my %id = ('id'=>$r->param('themeid'));
        &Apache::Promse::update_record('cc_themes',\%id,\%fields);
        print STDERR "\n Updated unit id " . $r->param('unitid');
        &xml_header($r);
        $r->print('<return>updated</return>');
    } elsif ($action eq 'getmaterials') {
        my $location = &Apache::Promse::get_user_location();
        my $district_id = $r->param('districtid');
        my $subject = $r->param('subject');
        my $grade = $r->param('filtergrades')?$r->param('grade'):0;
        my $materials = &get_materials($district_id, $subject, $grade);
        my $doc = XML::DOM::Document->new();
        my $materials_root = $doc->createElement('materials');
        foreach my $item (@$materials) {
            my $item_element = &build_material_item_element($item,$doc);
            $materials_root->appendChild($item_element);
        }
        &xml_header($r);
        $r->print($materials_root->toString);
    } elsif ($action eq 'getdistrictmaterials') {
        my $materials = &get_district_materials($r);
        my $doc = XML::DOM::Document->new();
        my $materials_root = $doc->createElement('materials');
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        foreach my $item (@$materials) {
            my $item_element = &build_material_item_element($item,$doc);
            $materials_root->appendChild($item_element);
        }
        $r->print($materials_root->toString);
	} elsif ($action eq 'deletetag') {
		my $theme_id = $r->param('lessonid');
		my $pf_end_id = $r->param('pfendid');
		my $qry = "DELETE FROM cc_pf_theme_tags 
					WHERE theme_id = $theme_id AND
							pf_end_id = $pf_end_id";
		$env{'dbh'}->do($qry);
		&xml_header($r);
		$r->print('<response>deleted</response>');
    } elsif ($action eq 'getideas') {
        my $unit_or_lesson = $r->param('unitorlesson');
        my $unit_or_lesson_id = $r->param('unitorlessonid');
        my $qry;
        if ($unit_or_lesson eq 'unit') {
            $qry = "SELECT idea, id from cc_math_ideas, cc_unit_ideas 
                    WHERE cc_math_ideas.id = cc_unit_ideas.idea_id AND 
                          cc_unit_ideas.unit_id = $unit_or_lesson_id";
        } else {
            $qry = "SELECT idea, id from cc_math_ideas, cc_lesson_ideas  
                    WHERE cc_math_ideas.id = cc_lesson_ideas.idea_id AND 
                          cc_lesson_ideas.lesson_id = $unit_or_lesson_id";
        }
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $doc = XML::DOM::Document->new;
        my $ideas_root = $doc->createElement('ideas');
        while (my $row = $rst->fetchrow_hashref()) {
            my $idea_element = $doc->createElement('idea');
            $idea_element->setAttribute('id',$$row{'id'});
            my $idea_text_node = $doc->createTextNode($$row{'idea'});
            $idea_element->appendChild($idea_text_node);
            $ideas_root->appendChild($idea_element);
        }
        &xml_header($r);
        $r->print($ideas_root->toString);
    } elsif ($action eq 'deleteidea') {
        my $unit_or_lesson = $r->param('unitorlesson');
        my $unit_or_lesson_id = $r->param('unitorlessonid');
        my $idea_id = $r->param('ideaid');
        my $qry;
        if ($unit_or_lesson eq 'unit') {
            $qry = "delete from cc_unit_ideas where unit_id = $unit_or_lesson_id and idea_id = $idea_id";
        } else {
            $qry = "delete from cc_lesson_ideas where lesson_id = $unit_or_lesson_id and idea_id = $idea_id";
        }
        $env{'dbh'}->do($qry);
        $qry = "delete from cc_math_ideas where cc_math_ideas.id = $idea_id";
        $env{'dbh'}->do($qry);
        &xml_header($r);
        $r->print("<response>deleted</response>");
    } elsif ($action eq 'updateidea') {
        my $idea_id = $r->param('ideaid');
        my $idea = &Apache::Promse::fix_quotes($r->param('idea'));
        my $qry = "UPDATE cc_math_ideas SET idea = $idea WHERE id = $idea_id";
        $env{'dbh'}->do($qry);
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>updated</response>");
    } elsif ($action eq 'saveidea') {
        my $unit_or_lesson = $r->param('unitorlesson');
        my $unit_or_lesson_id = $r->param('unitorlessonid');
        my $idea = &Apache::Promse::fix_quotes($r->param('idea'));
        my $qry;
        # will want eventually to decide if this is a new idea, or 
        # assigning an existing idea to the unit or lesson
        my %fields = ('idea'=>$idea);
        my $idea_id = &Apache::Promse::save_record('cc_math_ideas',\%fields,1);
        $idea_id = $idea_id?$idea_id:'fail';
        if ($unit_or_lesson eq 'unit') {
            $qry = "insert into cc_unit_ideas (unit_id, idea_id) values ($unit_or_lesson_id,$idea_id)";
        } else {
            $qry = "insert into cc_lesson_ideas (lesson_id, idea_id) values ($unit_or_lesson_id,$idea_id)";
        }
        $env{'dbh'}->do($qry);
        &xml_header($r);
        $r->print("<response>$idea_id</response>");
    } elsif ($action eq 'insertmaterial') {
        my $new_material_id = &Apache::Promse::save_materials($r);
        $new_material_id = !$new_material_id?'fail':$new_material_id;
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>$new_material_id</response>");
    } elsif ($action eq 'getchunks') {
        my $theme_id = $r->param('themeid');
        my $material_chunks = &get_theme_chunks($theme_id);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<materialchunks>');
        foreach my $chunk(@$material_chunks) {
            $r->print('<chunk>');
            $r->print('<chunkid>');
            $r->print($$chunk{'id'});
            $r->print('</chunkid>');
            $r->print('<materialid>');
            $r->print($$chunk{'material_id'});
            $r->print('</materialid>');
            $r->print('<materialtitle>');
            $r->print(&Apache::Promse::text_to_html($$chunk{'material_title'}));
            $r->print('</materialtitle>');
            $r->print('<title>');
            $r->print(&Apache::Promse::text_to_html($$chunk{'title'}));
            $r->print('</title>');
            $r->print('<description>');
            $r->print(&Apache::Promse::text_to_html($$chunk{'description'}));
            $r->print('</description>');
            $r->print('<unusedportion>');
            $r->print(&Apache::Promse::text_to_html($$chunk{'unused_portion'}));
            $r->print('</unusedportion>');
            $r->print('</chunk>');
        } 
        $r->print('</materialchunks>');
    } elsif ($action eq 'insertchunk') {
        my $description;
        my $id;
        if(!$r->param('description')) {
            $description = &Apache::Promse::fix_quotes("No Selected Material");
        } else {
            $description = &Apache::Promse::fix_quotes($r->param('description'));
        }
        if ($r->param('materialid')) {
            my %fields = ('material_id'=>$r->param('materialid'),
                          'theme_id'=>$r->param('themeid'),
                          'title'=>&Apache::Promse::fix_quotes($r->param('title')),
                          'unused_portion'=>&Apache::Promse::fix_quotes($r->param('unusedportion')),
                          'description'=>$description);
            $id = &Apache::Promse::save_record('cc_material_chunks',\%fields, 1);
        } else {
            $id = 'no material id';
        }
        &xml_header($r);
        $r->print('<response>'.$id.'</response>');
    } elsif ($action eq 'updatechunk') {
        my $chunk_id = $r->param('chunkid');
        my %id = ('id'=>$chunk_id);
        my %fields = ('material_id'=>$r->param('materialid'),
                      'theme_id'=>$r->param('themeid'),
                      'title'=>&Apache::Promse::fix_quotes($r->param('title')),
                      'unused_portion'=>&Apache::Promse::fix_quotes($r->param('unusedportion')),
                      'description'=>&Apache::Promse::fix_quotes($r->param('description')));
        my $id = &Apache::Promse::update_record('cc_material_chunks',\%id,\%fields);
        &xml_header($r);
        $r->print('<response>updated</response>');
    } elsif ($action eq 'deletechunk') {
        my $chunk_id = $r->param('chunkid');
        my $qry = "delete from cc_material_chunks where id = $chunk_id";
        $env{'dbh'}->do($qry);
        &xml_header($r);
        $r->print('<response>deleted</response>');
    } elsif ($action eq 'getchunkprinciples') {
        my $chunk_id = $r->param('chunkid');
        my $chunk_principles = &get_chunk_principles($chunk_id);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<chunkprinciples chunkid="'.$chunk_id.'">');
        foreach my $chunk_principle(@$chunk_principles) {
            $r->print('<chunkprinciple>');
            $r->print('<principleid>');
            $r->print($$chunk_principle{'principle_id'});
            $r->print('</principleid>');
            $r->print('<principle>');
            $r->print(&Apache::Promse::text_to_html($$chunk_principle{'principle'}));
            $r->print('</principle>');
            $r->print('<notes>');
            $r->print(&Apache::Promse::text_to_html($$chunk_principle{'notes'}));
            $r->print('</notes>');
            $r->print('</chunkprinciple>');
        }
        $r->print('</chunkprinciples>');
    } elsif ($action eq 'insertchunkprinciple') {
        my %fields = ('chunk_id'=>$r->param('chunkid'),
                      'principle_id'=>$r->param('principleid'),
                      'notes'=>&Apache::Promse::fix_quotes($r->param('notes')));
        my $id = &Apache::Promse::save_record('cc_chunk_principle',\%fields,1);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>$id</response>");
    } elsif ($action eq 'updatechunkprinciple') {
        my %fields = ('notes'=>&Apache::Promse::fix_quotes($r->param('notes')));
        my %id = ('chunk_id'=>$r->param('chunkid'),
                  'principle_id'=>$r->param('principleid'));
        &Apache::Promse::update_record('cc_chunk_principle',\%id,\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>ok</response>");
    } elsif ($action eq 'deletechunkprinciple') {
        my $chunk_id = $r->param('chunkid');
        my $principle_id = $r->param('principleid');
        my $qry = "delete from cc_chunk_principle where chunk_id = $chunk_id and principle_id = $principle_id";
        $env{'dbh'}->do($qry);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>ok</response>");
    } elsif ($action eq 'getchunkstandards') {
        my $chunk_id = $r->param('chunkid');
        my $chunk_standards = &get_chunk_standards($chunk_id);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<chunkstandards chunkid="'.$chunk_id.'">');
        foreach my $chunk_standard(@$chunk_standards) {
            $r->print('<chunkstandard>');
            $r->print('<standardid>');
            $r->print($$chunk_standard{'standard_id'});
            $r->print('</standardid>');
            $r->print('<standard>');
            $r->print(&Apache::Promse::text_to_html($$chunk_standard{'standard'}));
            $r->print('</standard>');
            $r->print('<notes>');
            $r->print(&Apache::Promse::text_to_html($$chunk_standard{'notes'}));
            $r->print('</notes>');
            $r->print('</chunkstandard>');
        }
        $r->print('</chunkstandards>');
    } elsif ($action eq 'insertchunkstandard') {
        my %fields = ('chunk_id'=>$r->param('chunkid'),
                      'standard_id'=>$r->param('standardid'),
                      'notes'=>&Apache::Promse::fix_quotes($r->param('notes')));
        my $id = &Apache::Promse::save_record('cc_chunk_standard',\%fields,1);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>$id</response>");
    } elsif ($action eq 'updatechunkstandard') {
        my %fields = ('notes'=>&Apache::Promse::fix_quotes($r->param('notes')));
        my %id = ('chunk_id'=>$r->param('chunkid'),
                  'standard_id'=>$r->param('standardid'));
        &Apache::Promse::update_record('cc_chunk_standard',\%id,\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>ok</response>");
    } elsif ($action eq 'deletechunkstandard') {
        my $chunk_id = $r->param('chunkid');
        my $standard_id = $r->param('standardid');
        my $qry = "delete from cc_chunk_standard where chunk_id = $chunk_id and standard_id = $standard_id";
        $env{'dbh'}->do($qry);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<response>ok</response>");
    } elsif ($action eq 'getthemes') {
        my $unit_id = $r->param('unitid');
        my $themes = &get_themes($unit_id);
        my $doc = XML::DOM::Document->new;
        my $themes_root = $doc->createElement('themes');
        $themes_root->setAttribute('unit_id', $unit_id);
        my $theme_element;
        my $current_theme = -1;
        my %lookup;
        foreach my $theme(@$themes) {
            my $ghost;
            my $tid = $$theme{'id'};
            if (($current_theme ne $$theme{'id'}) && !($lookup{$tid})) {
                $lookup{$tid} = 1;
                if ($$theme{'unit_id'} ne $unit_id) {
                    $ghost = $$theme{'ghost'};
                } else {
                    $ghost = 0;
                }
                my $eliminated = $$theme{'eliminated'}?$$theme{'eliminated'}:0;
                $current_theme = $$theme{'id'};
                $theme_element = $doc->createElement('theme');
                $theme_element->setAttribute('id', $$theme{'id'});
                $theme_element->setAttribute('periods',$$theme{'periods'});
                $theme_element->setAttribute('periodduration',$$theme{'period_duration'});
                $theme_element->setAttribute('supportingactivity',$$theme{'supporting_activity'});
                $theme_element->setAttribute('eliminated',$eliminated);
                $theme_element->setAttribute('sequence',$$theme{'sequence'});
                $theme_element->setAttribute('unitid',"$$theme{'unit_id'}");
                $theme_element->setAttribute('ghost', $ghost);
                my $title_element = $doc->createElement('title');
                my $title_text = $doc->createTextNode($$theme{'title'});
                $title_element->appendChild($title_text);
                $theme_element->appendChild($title_element);
                my $description_element = $doc->createElement('description');
                my $description_text = $doc->createTextNode($$theme{'description'});
                $description_element->appendChild($description_text);
                $theme_element->appendChild($description_element);
                my $unit_element = $doc->createElement('unit');
                $unit_element->setAttribute('id',$$theme{'unit_id'});
                $unit_element->setAttribute('grade',$$theme{'grade'});
                my $unit_title = $doc->createElement('title');
                my $unit_text = $doc->createTextNode($$theme{'unit_title'});
                $unit_title->appendChild($unit_text);
                $unit_element->appendChild($unit_title);
                my $comment_element = $doc->createElement('comment');
                my $comment_text = $doc->createTextNode($$theme{'comment'}.'');
                $comment_element->appendChild($comment_text);
                $unit_element->appendChild($comment_element);
                $theme_element->appendChild($unit_element);
                $themes_root->appendChild($theme_element);
            }
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($themes_root->toString);
	} elsif ($action eq 'getstandardsselect') {
		my $doc = XML::DOM::Document->new;
		my $rootElement = $doc->createElement('standards');
		my ($standards, $hidden) = &get_standard_select($r,$doc);
		$rootElement->appendChild($standards);
		$rootElement->appendChild($hidden);
        &xml_header($r);
		$r->print($rootElement->toString);
    } elsif ($action eq 'getstandards') {
        my $location = &Apache::Promse::get_user_location();
        my $district_id = $$location{'district_id'};
        my $standards = &get_standards($district_id);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<standards>');
        foreach my $standard(@$standards) {
            $r->print('<standard>');
            $r->print('<standardid>');
            $r->print($$standard{'id'});
            $r->print('</standardid>');
            $r->print('<standard>');
            $r->print(&Apache::Promse::text_to_html($$standard{'standard'}));
            $r->print('</standard>');
            $r->print('<description>');
            $r->print(&Apache::Promse::text_to_html($$standard{'description'}));
            $r->print('</description>');
            $r->print('<sequence>');
            $r->print($$standard{'sequence'});
            $r->print('</sequence>');
            $r->print('</standard>');
        }
        $r->print('</standards>');
    } elsif ($action eq 'saveconnection') {
        my %fields = ('theme_id'=>$r->param('themeid'),
                      'chunk_id'=>$r->param('chunkid'),
                      'principle_id'=>$r->param('principleid'),
                      'standard_id'=>$r->param('standardid'),
                      'teaching'=>&Apache::Promse::fix_quotes($r->param('teaching')),
                      'principle_connection'=>&Apache::Promse::fix_quotes($r->param('connection')));
        &Apache::Promse::save_record('cc_connections',\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<response>ok</response>');
    } elsif ($action eq 'movesequence') {
        &move_sequence($r);
    } elsif ($action eq 'updateunit') {
        my $next_unit_seq = &get_next_unit_seq($r);
        my $curriculum_id = $r->param('curriculumid');
        my $grade_id = $r->param('gradeid');
        my $qry = "SELECT id, curriculum_id, grade_id, sequence, periods, period_duration, title, description
                    FROM cc_units WHERE id = " . $r->param('unitid');
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $row = $rst->fetchrow_hashref();
        my $periods = $$row{'periods'}?$$row{'periods'}:0;
        my $period_duration = $$row{'period_duration'}?$$row{'period_duration'}:0;
        my $title = $$row{'title'}?$$row{'title'}:"";
        my $description = $$row{'description'}?$$row{'description'}:"";
        my %fields = ('unit_id'=>$$row{'id'},
                    'curriculum_id'=>$$row{'curriculum_id'},
                    'change_date'=>' NOW() ',
                    'grade_id'=>$$row{'grade_id'},
                    'sequence'=>$$row{'sequence'},
                    'periods'=>$periods,
                    'period_duration'=>$period_duration,
                    'title'=>&Apache::Promse::fix_quotes($title),
                    'description'=>&Apache::Promse::fix_quotes($description) );
        &Apache::Promse::save_record('cc_unit_history',\%fields); 
        %fields = ('title'=>&Apache::Promse::fix_quotes($r->param('title')),
                    'description'=>&Apache::Promse::fix_quotes($r->param('description')),
                    'periods'=>$r->param('periods'),
                    'period_duration'=>$r->param('periodduration'));
        my %id = ('id'=>$r->param('unitid'));
        &Apache::Promse::update_record('cc_units',\%id,\%fields);
        &xml_header($r);
        $r->print('<response>updated</response>');
    } elsif ($action eq 'deleteunit') {
        my $unit_id = $r->param('unitid');
        my $qry = "delete from cc_units where id = $unit_id";
        $env{'dbh'}->do($qry);
        $qry = "DELETE from cc_template_imports WHERE curriculum_unit_id = $unit_id";
        $env{'dbh'}->do($qry);
        $qry = "DELETE FROM cc_math_ideas WHERE id IN (select unit_id as id FROM cc_unit_ideas WHERE unit_id = $unit_id) ";
        $env{'dbh'}->do($qry);
        $qry = "DELETE from cc_unit_ideas where unit_id = $unit_id";
        $env{'dbh'}->do($qry);
        $qry = "DELETE from cc_themes where unit_id = $unit_id";
        $env{'dbh'}->do($qry);
        &xml_header($r);
        $r->print('<response>deleted</response>');
    } elsif ($action eq 'updatematerial') {
        my %fields = ('title'=>&Apache::Promse::fix_quotes($r->param('title')),
                      'author'=>&Apache::Promse::fix_quotes($r->param('author')),
                      'year'=>&Apache::Promse::fix_quotes($r->param('year')),
                      'grades'=>&Apache::Promse::fix_quotes($r->param('grades')),
                      'edition'=>&Apache::Promse::fix_quotes($r->param('edition')),
                      'isbn'=>&Apache::Promse::fix_quotes($r->param('isbn')),
                      'publisher'=>&Apache::Promse::fix_quotes($r->param('publisher')),
                      'organization'=>&Apache::Promse::fix_quotes($r->param('organization')),
                      'notes'=>&Apache::Promse::fix_quotes($r->param('notes')));
        my %id = ('id'=>$r->param('materialid'));
        &Apache::Promse::update_record('cc_materials',\%id,\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<response>ok</response>');
    } elsif ($action eq 'deletematerial') {
        my $material_id = $r->param('materialid');
        my $qry = "delete from cc_materials where id = $material_id";
        $env{'dbh'}->do($qry);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<response>ok</response>');
	} elsif ($action eq 'getbreadcrumbs') {
		my ($crumbs, $depth) = &Apache::Promse::build_bread_crumbs($r,$profile);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
		$r->print($crumbs);
	} elsif ($action eq 'getgriddata') {
        my $curriculum_id = $r->param('curriculumid');
        my $grade = $r->param('grade');
        my $qry = "SELECT
                cc_units.title AS unit_title,
                cc_units.description AS unit_description,
                cc_units.id AS unit_id,
                cc_material_chunks.material_id,
                cc_material_chunks.title AS chunk_title,
                cc_material_chunks.description,
                cc_themes.title AS theme_title,
                cc_themes.id AS theme_id,
                cc_themes.sequence,
                cc_chunk_principle.principle_id,
                cc_principles.principle,
                cc_units.grade_id,
                cc_material_chunks.id AS chunk_id
                FROM ( cc_curricula )
                LEFT JOIN cc_units on cc_curricula.id = cc_units.curriculum_id
                LEFT JOIN cc_themes on cc_themes.unit_id = cc_units.id
                LEFT JOIN cc_material_chunks on cc_material_chunks.theme_id = cc_themes.id
                LEFT JOIN cc_chunk_principle on cc_chunk_principle.chunk_id = cc_material_chunks.id
                LEFT JOIN cc_principles on cc_principles.id = cc_chunk_principle.principle_id
                WHERE        cc_curricula.id = $curriculum_id AND
                                    cc_units.grade_id = $grade
                ORDER BY
                    cc_curricula.id ASC,
                    cc_units.grade_id ASC,
                    cc_units.sequence ASC,
                    cc_principles.id ASC,
                    cc_themes.sequence ASC,
                    cc_material_chunks.id ASC";
        my $rs = $env{'dbh'}->prepare($qry);
        $rs->execute();
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<grid>');
        my $current_unit = -1;
        my $current_principle = -1;
        my $current_theme = -1;
        my $in_unit = 0;
        my $in_principle = 0;
        my $in_theme = 0;
        while (my $row = $rs->fetchrow_hashref()) {
            if ($$row{'unit_id'}) {
                if ($$row{'unit_id'} ne $current_unit) {
                    $current_unit = $$row{'unit_id'};
                    $current_theme = - 1;
                    $current_principle = - 1;
                    if ($in_principle) {
                        if ($in_theme) {
                            $r->print('</theme>');
                            $in_theme = 0;
                        }
                        $r->print('</principle>');
                        $in_principle = 0;
                    } else {
                        if ($in_theme) {
                            $r->print('</theme>');
                            $in_theme = 0;
                        }
                    } 
                    if ($in_unit) {
                        $r->print('</unit>');
                        $in_unit = 0;
                    }
                    $r->print('<unit unitid="'.$$row{'unit_id'}.'">');
                    $r->print('<title>');
                    $r->print(&Apache::Promse::text_to_html($$row{'unit_title'}));
                    $r->print('</title>');
                    $r->print('<description>');
                    $r->print(&Apache::Promse::text_to_html($$row{'unit_description'}));
                    $r->print('</description>');
                    $in_unit = 1;
                } else {
                    if ($$row{'principle_id'}) {
                        if ($current_principle ne $$row{'principle_id'}) {
                            $current_principle = $$row{'principle_id'};
                            $current_theme = - 1;
                            if ($in_principle) {
                                if ($in_theme) {
                                    $r->print('</theme>');
                                    $in_theme = 0;
                                }
                                $r->print('</principle>');
                                $in_principle = 0;
                                $r->print('<principle principleid="'.$$row{'principle_id'}.'">');
                                $r->print('<principlename>');
                                $r->print(&Apache::Promse::text_to_html($$row{'principle'}));
                                $r->print('</principlename>');
                                $in_principle = 1;
                            } else {
                                if ($in_theme) {
                                    $r->print('</theme>');
                                    $in_theme = 0;
                                }
                                $r->print('<principle principleid="'.$$row{'principle_id'}.'">');
                                $r->print('<principlename>');
                                $r->print(&Apache::Promse::text_to_html($$row{'principle'}));
                                $r->print('</principlename>');
                                $in_principle = 1;
                            }
                            $r->print('<theme themeid="'.$$row{'theme_id'}.'">');
                            $r->print('<title>');
                            $r->print(&Apache::Promse::text_to_html($$row{'theme_title'}));
                            $r->print('</title>');
                            $r->print('<description>');
                            $r->print(&Apache::Promse::text_to_html($$row{'theme_description'}));
                            $r->print('</description>');
                            $in_theme = 1;
                        }
                    } else {
                        if ($current_theme ne $$row{'theme_id'}) {
                            if ($in_theme) {
                                $r->print('</theme>');
                                $in_theme = 0;
                            }
                            
                            $r->print('<theme themeid="'.$$row{'theme_id'}.'">');
                            $r->print('<title>');
                            $r->print(&Apache::Promse::text_to_html($$row{'theme_title'}));
                            $r->print('</title>');
                            $r->print('<description>');
                            $r->print(&Apache::Promse::text_to_html($$row{'theme_description'}));
                            $r->print('</description>');
                            $in_theme = 1;
                        }
                    }
                }
                my $chunk_node = &chunk_node($row);
                $r->print($chunk_node);
            }
        }
        if ($in_theme) {
            $r->print('</theme>');
            $in_theme = 0;
        }
        if ($in_principle) {
            $r->print('</principle>');
            $in_theme = 0;
        }
        if ($in_unit) {
            $r->print('</unit>');
            $in_unit = 0;
        }
        $r->print('</grid>');
	} elsif ($action eq 'updatetag') {
		my $doc = XML::DOM::Document->new();
		my $root = $doc->createElement('response');
		my $pf_end_id = $r->param('pfendid');
		my $strength = $r->param('strength');
		my $notes = &Apache::Promse::fix_quotes($r->param('notes'));
		my $theme_id = $r->param('lessonid');
		my $qry = "SELECT count(*) as entered 
					FROM cc_pf_theme_tags 
					WHERE cc_pf_theme_tags.theme_id = $theme_id AND
						cc_pf_theme_tags.pf_end_id = $pf_end_id";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my $row = $rst->fetchrow_hashref();
		my $message = '';
		if ($$row{'entered'}) {
			# do an update here
			my %id_fields = ('theme_id'=>$theme_id,
							'pf_end_id'=>$pf_end_id);
			my %fields = ('strength'=>$strength,
						'notes'=>$notes);
			&Apache::Promse::update_record('cc_pf_theme_tags',\%id_fields, \%fields);
			print STDERR "should update tag\n";
			$message = "updated";
		} else {
			# insert new record here
			my %fields = ('pf_end_id'=>$pf_end_id,
						'theme_id'=>$theme_id,
						'strength'=>$strength,
						'notes'=>$notes);
			&Apache::Promse::save_record('cc_pf_theme_tags',\%fields,0);
			print STDERR "should insert tag \n";
			$message = "inserted";
		}
		$root->setAttribute('pfendid', $pf_end_id);
		my $textNode = $doc->createTextNode($message);
		$root->appendChild($textNode);
		&xml_header($r);
		$r->print($root->toString());
    } elsif ($action eq 'savestandard') {
        my $grade;
        $grade = $r->param('grade') eq 'K'?'0':$r->param('grade');
        $grade = $grade eq 'HS'?'9':$grade;
        my %fields = ('district_id'=>$r->param('districtid'),
                      'title'=>&Apache::Promse::fix_quotes($r->param('title')),
                      'description'=>&Apache::Promse::fix_quotes($r->param('description')),
                      'sequence'=>$r->param('sequence'),
                      'grade'=>$grade);
        &Apache::Promse::save_record('cc_district_standards',\%fields);
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<response>ok</response>');
    }
    return;
    sub get_curriculum_changes {
        # common routine delivers curriculumXML for curriculum_coherence and lessonLinker
        my ($r) = @_;
        my $file_name = 'temp' . $env{'token'} . 'curric' . '.xml';
        my $pid = fork();
        #print STDERR "\n ************** About to stat File ************\n ";
        if ($pid) {
            &get_curriculum_changes_thread($r,$file_name);
        } else {
            my ($dev, $ino, $mode, $nlink) = stat($file_name);
            if (stat ("/var/www/html/images/userpics/". $file_name)) {
                unlink("/var/www/html/images/userpics/". $file_name);
                # print STDERR "\n ************** Found File ************\n ";
                unlink("/var/www/html/images/userpics/". $file_name);
            }
            &xml_header($r);
            $r->print('<response filename="'. $file_name . '">working</response>');
        }
    }
    sub get_curriculum_grades {
        my ($r) = @_;
        my $curriculum_id = $r->param('curriculumid');
        my $qry = "SELECT DISTINCT cc_units.grade_id FROM cc_units, cc_themes
                    WHERE cc_units.curriculum_id = $curriculum_id
                     AND cc_themes.unit_id = cc_units.id
                    ORDER BY cc_units.grade_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my %grades_hash;
        my $doc = XML::DOM::Document->new;
        my $grades_root = $doc->createElement('grades');
        while (my $row = $rst->fetchrow_hashref) {
            my $grade_element = $doc->createElement('grade');
            $grade_element->setAttribute('gradelevel',$$row{'grade_id'});
            $grades_root->appendChild($grade_element);
        }
        &xml_header($r);
        $r->print($grades_root->toString()); 
    }
    sub dirty_flag {
        my ($unit_id) = @_;
        my $qry = "SELECT curriculum_id, grade_id FROM cc_units WHERE id = $unit_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $row = $rst->fetchrow_hashref();
        my $curriculum_id = $$row{'curriculum_id'};
        my $grade = $$row{'grade_id'};
        $qry = "UPDATE checkout SET dirty = 1 WHERE
                    curriculum_id = $curriculum_id AND
                    grade = $grade AND
                    user_id != $env{'user_id'}";
        $env{'dbh'}->do($qry);
    }
	sub get_standard_select {
		my ($r, $doc) = @_;
		my $contentElement = $doc->createElement('content');
		my $hiddenContentElement = $doc->createElement('content');
		$contentElement->setAttribute('destination', 'selectorItemsContainer');
		$hiddenContentElement->setAttribute('destination', 'hiddenContainer');
		my $filter_string = $r->param('filterstring')?$r->param('filterstring'):'%';
		$filter_string = $filter_string . '%';
		my $qry = "SELECT id, title, description
					FROM framework_items 
				WHERE framework_id = 1 AND title > '' AND title like '$filter_string'
				ORDER BY title";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my $elementCount = 0;
		while (my $row = $rst->fetchrow_hashref()) {
			$elementCount ++;
			my $standard_id = $$row{'id'};
			my $description = $$row{'description'};
			my $divElement = $doc->createElement('div');
			$divElement->setAttribute('onmouseover','mouseOverStandard(this)');
			$divElement->setAttribute('onclick','stdItemClicked(this)');
			$divElement->setAttribute('class','stdItem');
			$divElement->setAttribute('id', $standard_id);
			my $titleElement = $doc->createTextNode($$row{'title'});
			$divElement->appendChild($titleElement);
			$contentElement->appendChild($divElement);
			my $hiddenDivElement = $doc->createElement('div');
			$hiddenDivElement->setAttribute('id', 'description' . $standard_id);
			$hiddenDivElement->setAttribute('class','hiddenDescription');
			my $descriptionTextNode = $doc->createTextNode($description);
			$hiddenDivElement->appendChild($descriptionTextNode);
			$hiddenContentElement->appendChild($hiddenDivElement);
		}
		print STDERR "Created $elementCount standards elements";
		return($contentElement, $hiddenContentElement);
	}
    sub get_lock_status {
        my ($r) = @_;
        my $doc = XML::DOM::Document->new;
        my @grades = split(/,/, $r->param('grades'));
        my $curriculum_id = $r->param('curriculumid');
        my $wrapper = $doc->createElement('lockedgrades');
        foreach my $grade(@grades) {
            my $response_element = $doc->createElement('grade');
            $response_element->setAttribute('grade',$grade);
            my $qry = "SELECT checkout.user_id, checkout.peer_id,checkout.monitor,
                        (60 * HOUR((TIMEDIFF(NOW(), log.last_act))) +
                            MINUTE(TIMEDIFF(NOW(), log.last_act))) as idle
                     FROM checkout, log WHERE 
                            checkout.user_id = log.user_id AND
                            curriculum_id = $curriculum_id AND
                            grade = $grade ORDER BY monitor DESC";
            my $rst = $env{'dbh'}->prepare($qry);
            $rst->execute();
            my $locked = 1;
            my $idle = 0;
            if (my $row = $rst->fetchrow_hashref()) {
                if ($$row{'user_id'} eq $env{'user_id'}) {
                    # no one else has priority
                    $response_element->setAttribute('locked','0');
                } else {
                    $response_element->setAttribute('locked','1');
                }
                $response_element->setAttribute('idle',$$row{'idle'});
            }
            $wrapper->appendChild($response_element);
        }
        &xml_header($r);
        $r->print($wrapper->toString());
    }



    sub get_curriculum_changes_thread {
        my ($r, $file_name) = @_;
        my $doc = XML::DOM::Document->new;
        my $curriculum_id = $r->param('curriculumid');
        my $grade = $r->param('grade')?$r->param('grade'):0;
        my $peer_id = $r->param('peerid');
        my $framework_id = $r->param('frameworkid')?$r->param('frameworkid'):1;
        my $unit_history_filter = '';
        my $lesson_history_filter = '';
        my $grade_filter = '';
        my $monitor = 'iam';
        my $sth;
        # see if this is already checked out 
        # first, make sure peer_id is current
        my $qry = "UPDATE checkout SET peer_id = '$peer_id' WHERE
                                    user_id = $env{'user_id'}";
        $env{'dbh'}->do($qry);
#        $qry = "SELECT checkout.user_id, checkout.peer_id,checkout.monitor,
#                    (60 * HOUR((TIMEDIFF(NOW(), log.last_act))) +
#                        MINUTE(TIMEDIFF(NOW(), log.last_act))) as idle
#                 FROM checkout, log WHERE 
#                        checkout.user_id = log.user_id AND
#                        curriculum_id = $curriculum_id AND
#                        grade = $grade ORDER BY monitor DESC";
#        my $sth = $env{'dbh'}->prepare($qry);
#        $sth->execute();
#        my $exists_flag = 0;
#        
#        my $editors_element = $doc->createElement('editors');
#        if (my $row = $sth->fetchrow_hashref()) {
#            # First in list is always monitor, even if not set that way
#            # in DB. 
#            my $editor_element = $doc->createElement('editor');
#            $editor_element->setAttribute('userid',$$row{'user_id'});
#            $editor_element->setAttribute('peerid',$$row{'peer_id'});
#            $editor_element->setAttribute('idle',$$row{'idle'});
#            $editor_element->setAttribute('monitor',1);
#            $editors_element->appendChild($editor_element);
#            if ($$row{'user_id'} eq $env{'user_id'}) {
#                $exists_flag = 1;
#            }
#            if (! $$row{'monitor'}) {
#                #need to update record is not already set as monitor
#                my $pid;
#                $qry = "UPDATE checkout SET monitor = 1
#                                    WHERE
#                                    user_id = $env{'user_id'} AND
#                                    curriculum_id = $curriculum_id AND
#                                    grade = $grade";
#                $env{'dbh'}->do($qry);
#            } 
#            $editors_element->appendChild($editor_element);
#            while ($row = $sth->fetchrow_hashref()) {
#                $editor_element = $doc->createElement('editor');
#                $editor_element->setAttribute('userid',$$row{'user_id'});
#                $editor_element->setAttribute('peerid',$$row{'peer_id'});
#                $editor_element->setAttribute('idle',$$row{'idle'});
#                $editor_element->setAttribute('monitor',0);
#                $editors_element->appendChild($editor_element);
#                if ($$row{'user_id'} eq $env{'user_id'}) {
#                    $exists_flag = 1;
#                }
#            }
#            if ($exists_flag eq 0 && $env{'user_id'} ne 0) {
#                # if user_id = 0 means user not validated
#                $qry = "INSERT INTO checkout (user_id,curriculum_id,grade,peer_id,monitor)
#                        VALUES ($env{'user_id'},$curriculum_id,$grade, '$peer_id', 0)";
#                $env{'dbh'}->do($qry);
#                $editor_element = $doc->createElement('editor');
#                $editor_element->setAttribute('userid',$env{'user_id'});
#                $editor_element->setAttribute('peerid',$r->param('peerid'));
#                $editor_element->setAttribute('monitor',0);
#                $editors_element->appendChild($editor_element);
#            }
#        } else {
            # no one has checked out so set this as monitor = 1
#            if ($env{'user_id'} ne 0) {
#                $qry = "INSERT INTO checkout (user_id, curriculum_id, grade, peer_id, monitor)
#                        VALUES ($env{'user_id'}, $curriculum_id, $grade, '$peer_id', 1)";
#                $env{'dbh'}->do($qry);
#            }
#            my $editor_element = $doc->createElement('editor');
#            $editor_element->setAttribute('userid',$env{'user_id'});
#            $editor_element->setAttribute('peerid',$r->param('peerid'));
#            $editor_element->setAttribute('monitor',1);
#            $editors_element->appendChild($editor_element);
#        }
        if ($r->param('grade') || $r->param('grade') eq 0) {
            $grade_filter = " AND cc_units.grade_id = " . $r->param('grade');
        }
        if ($curriculum_id eq 21) {
            $unit_history_filter = " && cc_unit_history.change_date > '2010-2-5' ";
            $lesson_history_filter = " && cc_lesson_history.change_date > '2010-2-5' ";
        }
    	my $dbh = &Apache::Promse::db_connect();
        $qry = "SELECT cc_material_chunks.id,
                cc_material_chunks.material_id, cc_themes.id, 
                cc_material_chunks.title, cc_material_chunks.description,
                cc_material_chunks.unused_portion
                FROM cc_material_chunks, cc_units, cc_themes
                WHERE cc_material_chunks.theme_id = cc_themes.id AND 
                    cc_units.id = cc_themes.unit_id AND
	                cc_units.curriculum_id = $curriculum_id
	                $grade_filter ";
	    $sth = $dbh->prepare($qry);
	    $sth->execute();
	    our %materials_hash = ();
	    while (my $row_ref = $sth->fetchrow_arrayref()) {
	        push(@{ $materials_hash{$$row_ref[2]} }, [ @$row_ref ]);
	    }
	    $qry = "SELECT cc_lesson_ideas.idea_id, cc_themes.id, cc_math_ideas.idea
	            FROM cc_lesson_ideas, cc_units, cc_themes, cc_math_ideas
                WHERE cc_lesson_ideas.lesson_id = cc_themes.id AND
                cc_math_ideas.id = cc_lesson_ideas.idea_id AND
                cc_units.id = cc_themes.unit_id AND
	            cc_units.curriculum_id = $curriculum_id
	            $grade_filter";
	    $sth = $dbh->prepare($qry);
	    $sth->execute();
        our %lesson_ideas_text_hash = ();
        our %lesson_ideas_hash = ();
	    while (my $row_ref = $sth->fetchrow_arrayref()) {
	        $lesson_ideas_hash{$$row_ref[1]} .= $$row_ref[0] . ":";
	        $lesson_ideas_text_hash{$$row_ref[0]} = $$row_ref[2];
	    }
	    $qry = "SELECT cc_unit_ideas.idea_id, cc_units.id, cc_math_ideas.idea
	        FROM cc_unit_ideas, cc_units, cc_math_ideas
            WHERE cc_unit_ideas.unit_id = cc_units.id AND
                    cc_math_ideas.id = cc_unit_ideas.idea_id AND
	            cc_units.curriculum_id = $curriculum_id
	            $grade_filter";
	    $sth = $dbh->prepare($qry);
	    $sth->execute();
        our %unit_ideas_hash = ();
        our %unit_ideas_text_hash = ();
        our %unit_moved_lessons_hash = ();
	    while (my $row_ref = $sth->fetchrow_arrayref()) {
	        $unit_ideas_hash{$$row_ref[1]} .= $$row_ref[0] . ":";
	        $unit_ideas_text_hash{$$row_ref[0]} = $$row_ref[2];
	    }
	    $qry = "select cc_pf_theme_tags.pf_end_id, cc_pf_theme_tags.theme_id, 
	                    cc_pf_theme_tags.strength, cc_pf_theme_tags.notes,
	                    framework_items.framework_id
	            FROM cc_pf_theme_tags, framework_items
                WHERE cc_pf_theme_tags.pf_end_id = framework_items.id AND
		            framework_items.framework_id = $framework_id AND
		            cc_pf_theme_tags.theme_id IN 
		                (SELECT cc_themes.id as theme_id 
		                    FROM cc_units, cc_themes
					        WHERE cc_themes.unit_id = cc_units.id AND
						        cc_units.curriculum_id = $curriculum_id
						        $grade_filter)";
	    $sth = $dbh->prepare($qry);
	    $sth->execute();
        our %lesson_tags_hash = ();
	    while (my $row_ref = $sth->fetchrow_arrayref()) {
	        push(@{ $lesson_tags_hash{$$row_ref[1]} }, [ @$row_ref ]);
	    }
        $qry = "SELECT DISTINCT cc_units.id as unit_id,
	        cc_curriculum_grade_completed.id AS completed_id,
            cc_units.grade_id               as grade, 
            cc_units.title                  as unit_title, 
            cc_units.description            as unit_description,
            cc_units.sequence               as unit_sequence,
            cc_units.periods                as unit_periods,
            cc_units.period_duration        as unit_period_duration,
            DATE_FORMAT(cc_unit_history.change_date, '%c/%d/%Y') as hist_unit_change_date, 
            cc_unit_history.description     as hist_unit_description,
	        cc_unit_history.grade_id        as hist_unit_grade, 
	        cc_unit_history.period_duration as hist_unit_period_duration,
	        cc_unit_history.periods         as hist_unit_periods,
	        cc_unit_history.title           as hist_unit_title,
            cc_themes.id                    as lesson_id, 
            cc_themes.description           as lesson_description, 
            cc_themes.title                 as lesson_title,
            cc_themes.supporting_activity   as supporting_activity,
            cc_themes.periods               as periods, 
            cc_themes.period_duration       as period_duration, 
            cc_themes.eliminated            as lesson_eliminated,
            cc_themes.sequence              as lesson_sequence, 
            cc_themes.tagged                as lesson_tagged,
            DATE_FORMAT(cc_lesson_history.change_date, '%c/%d/%Y') as hist_lesson_change_date, 
            cc_lesson_history.comment       as hist_lesson_comments,
	        cc_lesson_history.title         as hist_lesson_title, 
	        cc_lesson_history.unit_id       AS hist_lesson_unit_id,
	        unit_lesson_history.grade_id    AS hist_lesson_grade,
            cc_lesson_history.description   as hist_lesson_description, 
	        cc_lesson_history.period_duration as hist_lesson_period_duration,
	        cc_lesson_history.periods       as hist_lesson_periods, 
	        cc_lesson_history.sequence      as hist_lesson_sequence,
	        cc_lesson_history.supporting_activity as hist_lesson_supporting_activity, 
	        cc_lesson_history.tagged        as tagged,
		moved_lessons.lesson_id as moved_lesson_id,
		check_lessons.title as moved_lesson_title,
		check_units.grade_id as moved_to_unit_grade,
		check_units.title as moved_to_unit_title,
		moved_lessons.comment as move_comment,
		moved_lessons.unit_id as moved_from_unit_id,
		check_lessons.unit_id AS moved_to_unit_id
    	FROM cc_units
    	LEFT JOIN cc_themes ON cc_themes.unit_id = cc_units.id
	    LEFT JOIN (cc_lesson_history) ON cc_lesson_history.lesson_id = cc_themes.id
	              
	              $lesson_history_filter
	              
	 LEFT JOIN (cc_lesson_history as moved_lessons, cc_units as check_units, cc_themes as check_lessons) ON 
			moved_lessons.unit_id = cc_units.id AND
			check_lessons.id  = moved_lessons.lesson_id AND
			check_lessons.unit_id = check_units.id AND
			check_units.id <> cc_units.id
        LEFT JOIN cc_curriculum_grade_completed
            ON cc_curriculum_grade_completed.curriculum_id = cc_units.curriculum_id AND 
            cc_curriculum_grade_completed.grade_id = cc_units.grade_id                                                      
    	LEFT JOIN cc_units as unit_lesson_history ON cc_lesson_history.unit_id = unit_lesson_history.id
	    LEFT JOIN cc_unit_history ON cc_unit_history.unit_id = cc_units.id 
	    
	            $unit_history_filter
	            
     	WHERE cc_units.curriculum_id = $curriculum_id 
     	        $grade_filter
    	ORDER BY cc_units.grade_id ASC, cc_units.sequence ASC, 
    	         cc_themes.sequence ASC, 
    	         cc_unit_history.change_date DESC,
    	         cc_lesson_history.change_date DESC,
    	         move_comment DESC";
        $sth = $dbh->prepare($qry);
        $sth->execute();
        my $district_curriculum_root = $doc->createElement('curriculum');
        $district_curriculum_root->setAttribute('name', 'lesson');
        $district_curriculum_root->setAttribute('editorid', $env{'user_id'});
        $district_curriculum_root->setAttribute('id', $curriculum_id);
        $district_curriculum_root->setAttribute('title','District Curriculum');
        my $in_grade = 0;
        my $in_lesson = 0;
        my $grade_element;
        my $unit_history_element;
        my $unit_element;
        my $unit_text_node;
        my $unit_description_element;
        my $unit_title_element;
        my $lesson_element;
        my $lesson_text_node;
        my $lesson_title_element;
        my $current_grade = -1;
        my $current_unit = -1;
        my $current_lesson = -1;
        my $lesson_change_date = 0;
        my $lesson_tag_change_date = 0;
        my $pf_end_id = 0;
        my $lesson_description;
        my $state_hashref;
        while (my $lesson = $sth->fetchrow_hashref()) {
            if ($current_grade ne $$lesson{'grade'}) {
                $current_grade = $$lesson{'grade'};
                $current_unit = $$lesson{'unit_id'};
                $current_lesson = $$lesson{'lesson_id'};
                if ($in_grade) { # skip appending unit if first time through loop
                   	if ($lesson_element) {
                       	$unit_element->appendChild($lesson_element);
                   	}
                   	if ($unit_element) {
                       	$grade_element->appendChild($unit_element);
                   	}
                   	$district_curriculum_root->appendChild($grade_element);
               	}
				if ($$lesson{'grade'} or $$lesson{'grade'} == 0) {
                	$grade_element = $doc->createElement('grade');
                	$in_grade = 1;
					print STDERR ("\n SET THE GRADELEVEL TO " . $$lesson{'grade'} . " VALUE ***** \n\n");
                	$grade_element->setAttribute('gradelevel', $$lesson{'grade'});
                	# $grade_element->appendChild($editors_element);
                	%unit_moved_lessons_hash = ();
                	$unit_element = &build_unit_element($lesson,$doc,$peer_id);
                	$unit_element = &append_unit_children($doc, $lesson, $unit_element);
                	if ($$lesson{'lesson_id'}) {
                    	$in_lesson = 1;
                    	$lesson_element = &build_curriculum_lesson($lesson,$doc);
                    	$lesson_element = &append_lesson_children($doc, $lesson_element, $lesson);
                	}
				}
            } else {
                if ($current_unit ne $$lesson{'unit_id'}) {
                    $current_unit = $$lesson{'unit_id'};
                    $current_lesson = $$lesson{'lesson_id'};
                    if ($in_lesson) { 
                        $unit_element->appendChild($lesson_element);
                        $in_lesson = 0;
                    }
                    $grade_element->appendChild($unit_element);
                    %unit_moved_lessons_hash = ();
                    $unit_element = &build_unit_element($lesson,$doc,$peer_id);
                    $unit_element = &append_unit_children($doc, $lesson, $unit_element);
                    if ($$lesson{'lesson_id'}) {
                        $in_lesson = 1;
                        $lesson_element = &build_curriculum_lesson($lesson,$doc);
                        $lesson_element = &append_lesson_children($doc, $lesson_element, $lesson);
                    }
                } else {
                    $unit_element = &append_unit_children($doc, $lesson, $unit_element);
                    # have to check for unit history and unit ideas
                    if ($current_lesson ne $$lesson{'lesson_id'}) {
                        if ($in_lesson) {
                            $unit_element->appendChild($lesson_element);
                            $in_lesson = 0;
                        }
                        $current_lesson = $$lesson{'lesson_id'};
                        if ($$lesson{'lesson_id'}) {
                            $lesson_element = &build_curriculum_lesson($lesson,$doc);
                            $in_lesson = 1;
                            $lesson_element = &append_lesson_children($doc, $lesson_element, $lesson);
                        }
                    } else {
                        if ($$lesson{'lesson_id'} eq 3060) {
#                            &Apache::Promse::logthis($$state_hashref{'lesson_change_hash'}{$$state_hashref{'lesson_change_date'}} . ' is lesson change hash for date below');
#                            &Apache::Promse::logthis('after call ' . $$state_hashref{'lesson_change_date'});
                        }
                    }
                }
            }
        }
        if ($in_grade) {
            if ($in_lesson) {
                $unit_element->appendChild($lesson_element);
            }
            if ($unit_element) {
                $grade_element->appendChild($unit_element);
            }
            $district_curriculum_root->appendChild($grade_element);
        } else {
            $grade_element = $doc->createElement('grade');
            $grade_element->setAttribute('gradelevel', $grade);
            #$grade_element->appendChild($editors_element);
            $district_curriculum_root->appendChild($grade_element);
        }
        
        
        # End of procedural code for get_curriculum_changes
        &Apache::Promse::queue_file_for_pickup($file_name, $district_curriculum_root->toString);
        
        sub append_unit_children {
            my ($doc, $row, $unit_element) = @_;
            if ($unit_ideas_hash{$$row{unit_id}}) {
                my @ideas = split(/:/,$unit_ideas_hash{$$row{unit_id}});
                delete($unit_ideas_hash{$$row{unit_id}});
                foreach my $idea_id(@ideas) {
                    my $unit_idea_element = $doc->createElement('idea');
                    $unit_idea_element->setAttribute('id',$idea_id);
                    my $idea_text_node = $doc->createTextNode($unit_ideas_text_hash{$idea_id});
                    $unit_idea_element->appendChild($idea_text_node);
                    $unit_element->appendChild($unit_idea_element);
                    # print STDERR "\n appended unit idea \n";
                }
            }
            if ($$row{'moved_lesson_id'} && ! $unit_moved_lessons_hash{$$row{'moved_lesson_id'}}) {
                $unit_moved_lessons_hash{$$row{'moved_lesson_id'}} = 1;
                my $moved_lesson_element = $doc->createElement('movedlesson');
                $moved_lesson_element->setAttribute('id',$$row{'moved_lesson_id'});
                $moved_lesson_element->setAttribute('destunittitle',$$row{'moved_to_unit_title'});
                $moved_lesson_element->setAttribute('destunitgrade',$$row{'moved_to_unit_grade'});
                $moved_lesson_element->setAttribute('title',$$row{'moved_lesson_title'});
                if ($$row{'move_comment'}) {
                    my $move_comment_element = $doc->createElement('comment');
                    my $move_comment_text = $doc->createTextNode($$row{'move_comment'});
                    $move_comment_element->appendChild($move_comment_text);
                    $moved_lesson_element->appendChild($move_comment_element);
                }
                $unit_element->appendChild($moved_lesson_element);
            }
            if ($$row{'hist_unit_change_date'}) {
                my $unit_history_element = $doc->createElement('unithistory');
                my $unit_history_title_element = $doc->createElement('title');
                my $unit_history_text_node = $doc->createTextNode($$row{'hist_unit_title'});
                $unit_history_title_element->appendChild($unit_history_text_node);
                $unit_history_element->appendChild($unit_history_title_element);
                $unit_history_element = &build_unit_history_element($row,$doc);
                $unit_element->appendChild($unit_history_element);
            }
            return($unit_element);
        }
        sub append_lesson_children {
            # called from get_curriculum_changes
            # <history>, <idea>, <material>, <tag> elements appended
            # to $lesson_element
            # %lesson_ideas_hash key=lesson_id value=list of idea_ids
            # %lesson_ideas_text_hash key=idea_id value=list of idea
            # %materials_hash
            # %lesson_ideas_text_hash,%lesson_ideas_hash,
            # %lesson_tags_hash 
            my ($doc, $lesson_element, $lesson) = @_;
            if ($$lesson{'hist_lesson_change_date'}) {
#                my $lesson_history_element = $doc->createElement('lessonhistory');
#                my $lesson_history_title_element = $doc->createElement('title');
#                my $lesson_history_text_node = $doc->createTextNode($$lesson{'hist_lesson_title'});
#                $lesson_history_title_element->appendChild($lesson_history_text_node);
#                $lesson_history_element->appendChild($lesson_history_title_element);
                my $lesson_history_element = &build_lesson_history_element($lesson,$doc);
                $lesson_element->appendChild($lesson_history_element);
            }
            if ($lesson_ideas_hash{$$lesson{lesson_id}}) {
                my @ideas = split(/:/,$lesson_ideas_hash{$$lesson{lesson_id}});
                delete($lesson_ideas_hash{$$lesson{lesson_id}});
                foreach my $idea_id(@ideas) {
                    my $lesson_idea_element = $doc->createElement('idea');
                    $lesson_idea_element->setAttribute('id',$idea_id);
                    my $idea_text_node = $doc->createTextNode($lesson_ideas_text_hash{$idea_id});
                    $lesson_idea_element->appendChild($idea_text_node);
                    $lesson_element->appendChild($lesson_idea_element);
                }
            }
            #   Field                           Index
            # pf_end_id                             0
            # cc_pf_theme_tags.theme_id             1
            # cc_pf_theme_tags.strength             2
            # cc_pf_theme_tags.notes                3
            # framework_id                          4
            if ($lesson_tags_hash{$$lesson{lesson_id}}) {
                my $tags = $lesson_tags_hash{$$lesson{lesson_id}};
                delete($lesson_tags_hash{$$lesson{lesson_id}});
                foreach my $lesson_tag_row(@$tags) {
                    my $lesson_tag_element = $doc->createElement('lessontag');
                    $lesson_tag_element->setAttribute('id',$$lesson_tag_row[0]);
                    $lesson_tag_element->setAttribute('strength',$$lesson_tag_row[2]);
                    $lesson_tag_element->setAttribute('frameworkid',$$lesson_tag_row[4]);
                    if ($$lesson_tag_row[3]) {
                        my $tag_note_element = $doc->createElement('note');
                        my $note_text_node = $doc->createTextNode($$lesson_tag_row[3]);
                        $tag_note_element->appendChild($note_text_node);
                        $lesson_tag_element->appendChild($tag_note_element);
                    }
                    $lesson_element->appendChild($lesson_tag_element);
                }
            }
            #    Field                            Index
            # chunk_id                              0
            # cc_material_chunks.material_id        1
            # cc_themes.id                          2 
            # cc_material_chunks.title              3
            # cc_material_chunks.description        4
            # cc_material_chunks.unused_portion     5
            if ($materials_hash{$$lesson{'lesson_id'}}) {
                my $materials = $materials_hash{$$lesson{'lesson_id'}};
                delete($materials_hash{$$lesson{'lesson_id'}});
                foreach my $material_row(@$materials) {
                    my $lesson_material_element = $doc->createElement('chunk');
                    $lesson_material_element->setAttribute('id',$$material_row[0]);
                    $lesson_material_element->setAttribute('materialid',$$material_row[1]);
                    my $title_element = $doc->createElement('title');
                    my $title_text = $$material_row[3]?$$material_row[3]:'No title';
                    my $title_text_node = $doc->createTextNode($title_text);
                    $title_element->appendChild($title_text_node);
                    $lesson_material_element->appendChild($title_element);
                    my $description_element = $doc->createElement('description');
                    my $description_text_node = $doc->createTextNode($$material_row[4]);
                    $description_element->appendChild($description_text_node);
                    $lesson_material_element->appendChild($description_element);
                    my $unused_element = $doc->createElement('unusedportion');
                    my $unused_text_node = $doc->createTextNode($$material_row[5]);
                    $unused_element->appendChild($unused_text_node);
                    $lesson_material_element->appendChild($unused_element);
                    $lesson_element->appendChild($lesson_material_element);
                }
            }
            return($lesson_element);
        }
    }
    sub build_lesson_history_element {
        # called from append_lesson_children (from get_curriculum_changes)
        # only called if there is $row{history_lesson_change_date} is valid
        my ($row,$doc) = @_;
        my $lesson_history_element = $doc->createElement('lessonhistory');
        $lesson_history_element->setAttribute('date', $$row{'hist_lesson_change_date'});
        $lesson_history_element->setAttribute('lessonid', $$row{'lesson_id'});
        if ($$row{'hist_lesson_comments'}) {
            $lesson_history_element->setAttribute('comments', $$row{'hist_lesson_comments'} . '');
        } else {
            $lesson_history_element->setAttribute('comments', 'No comments.');
        }
        $lesson_history_element = &compare_fields_set_attribute($lesson_history_element, $row,'grade','grade', 'hist_lesson_grade');
        $lesson_history_element = &compare_fields_set_attribute($lesson_history_element, $row,'supportingactivity','supporting_activity', 'hist_lesson_supporting_activity');
        $lesson_history_element = &compare_fields_set_attribute($lesson_history_element, $row,'periods','periods', 'hist_lesson_periods');
        $lesson_history_element = &compare_fields_set_attribute($lesson_history_element, $row,'periodduration','period_duration', 'hist_lesson_period_duration');
        $lesson_history_element = &compare_fields_set_attribute($lesson_history_element, $row,'unitid','unit_id', 'hist_lesson_unit_id');
        $lesson_history_element = &compare_fields_set_attribute($lesson_history_element, $row,'sequence','lesson_sequence', 'hist_lesson_sequence');
        return ($lesson_history_element);
    }
    sub compare_fields_set_attribute {
        # called from build_lesson_history_element (append_lesson_children, get_curriculum_changes)
        my ($element, $row, $attribute_name, $field_1, $field_2) = @_;
        if ($$row{$field_1} eq $$row{$field_2}) {
            $element->setAttribute($attribute_name,'*');
        } else {
            $element->setAttribute($attribute_name,$$row{$field_2});
        }
        return($element);
    }
    sub build_unit_element {
        my ($row,$doc, $peer_id) = @_;
        my $unit_element = $doc->createElement('unit');
        $unit_element->setAttribute('id',$$row{'unit_id'});
        $unit_element->setAttribute('sequence',$$row{'unit_sequence'});
        $unit_element->setAttribute('periods',$$row{'unit_periods'});
        $unit_element->setAttribute('periodduration',$$row{'unit_period_duration'});
        my $unit_title_element = $doc->createElement('title');
        my $unit_text_node = $doc->createTextNode($$row{'unit_title'});
        $unit_title_element->appendChild($unit_text_node);
        $unit_element->appendChild($unit_title_element);
        my $unit_description_element = $doc->createElement('description');
        my $unit_description_text_node = $doc->createTextNode($$row{'unit_description'});
        $unit_description_element->appendChild($unit_description_text_node);
        $unit_element->appendChild($unit_description_element);
        return($unit_element)
    }
    sub build_unit_history_element {
        my ($row,$doc) = @_;
        my $unit_history_element = $doc->createElement('unithistory');
        my $unit_history_title_element = $doc->createElement('title');
        my $unit_history_text_node = $doc->createTextNode($$row{'hist_unit_title'});
        $unit_history_title_element->appendChild($unit_history_text_node);
        $unit_history_element->appendChild($unit_history_title_element);
        return($unit_history_element);
    }
    sub build_curriculum_lesson {
        my ($lesson, $doc) = @_;
        my $lesson_element = $doc->createElement('lesson');
        $lesson_element->setAttribute('id', $$lesson{'lesson_id'});
        $lesson_element->setAttribute('tagcount', $$lesson{'tag_count'});
        $lesson_element->setAttribute('grade',$$lesson{'grade'});
        $lesson_element->setAttribute('supportingactivity',$$lesson{'supporting_activity'});
        $lesson_element->setAttribute('periods',$$lesson{'periods'});
        $lesson_element->setAttribute('periodduration',$$lesson{'period_duration'});
        $lesson_element->setAttribute('sequence',$$lesson{'lesson_sequence'});
        my $tagged = $$lesson{'lesson_tagged'}?1:0;
        my $eliminated = ($$lesson{'lesson_eliminated'})?'1':'0';
        $lesson_element->setAttribute('tagged',$tagged);
        $lesson_element->setAttribute('eliminated',$eliminated);
        my $lesson_title_element = $doc->createElement('title');
        my $lesson_text_node = $doc->createTextNode($$lesson{'lesson_title'});
        $lesson_title_element->appendChild($lesson_text_node);
        $lesson_element->appendChild($lesson_title_element);
        my $lesson_description = $doc->createElement('description');
        $lesson_text_node = $doc->createTextNode($$lesson{'lesson_description'});
        $lesson_description->appendChild($lesson_text_node);
        $lesson_element->appendChild($lesson_description);
        return($lesson_element);
    }
    sub get_curriculum_templates {
        my ($r) = @_;
        my $qry;
        my $sth;
        my $doc = XML::DOM::Document->new;
        $qry = "SELECT cc_curricula.id as template_id, cc_curricula.subject, 
                cc_curricula.is_template, cc_curricula.title, cc_curricula.description,
                cc_curricula_districts.district_id,  districts.district_name
                FROM cc_curricula
		LEFT JOIN (cc_curricula_districts, districts) ON 
			cc_curricula.id = cc_curricula_districts.curriculum_id AND
			districts.district_id = cc_curricula_districts.district_id
		WHERE cc_curricula.is_template = 1
		ORDER BY cc_curricula.title
		";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $templates_root = $doc->createElement('templates');
        my $template_element;
        my $current_template = -1;
        my $in_template = 0;
        while (my $template = $sth->fetchrow_hashref()) {
            if ($current_template ne $$template{'template_id'}) {
                $current_template = $$template{'template_id'};
                if ($in_template) {
                    $templates_root->appendChild($template_element);
                }
                $template_element = $doc->createElement('template');
                $template_element->setAttribute('id',$$template{'template_id'});
                $template_element->setAttribute('title',$$template{'title'});
                $in_template = 1;
                if ($$template{'district_id'}) {
                    my $district_element = $doc->createElement('district');
                    $district_element->setAttribute('id',$$template{'district_id'});
                    $district_element->setAttribute('name',$$template{'district_name'});
                    $template_element->appendChild($district_element);
                }
            } else {
                # here if template is assigned to another district 
                my $district_element = $doc->createElement('district');
                $district_element->setAttribute('id',$$template{'district_id'});
                $district_element->setAttribute('name',$$template{'district_name'});
                $template_element->appendChild($district_element);
            }
        }
        if ($in_template) {
            $templates_root->appendChild($template_element);
        }
        &xml_header($r);
        $r->print($templates_root->toString());
    }
    sub get_curriculum {
        my ($r) = @_;
        my $curriculum_id = $r->param('curriculumid');
        my $filter_eliminated = '';
        my $eliminated_attribute;
        if ($r->param('action') eq 'geteliminatedthemes') {
            $filter_eliminated = ' AND cc_themes.eliminated = 1 ';
            $eliminated_attribute = 'true';
        } else {
            $eliminated_attribute = 'false';
        }
        my $qry;
        my $sth;
        my $doc = XML::DOM::Document->new;
        $qry = "SELECT cc_units.id as unit_id, cc_units.grade_id as grade, cc_units.description as unit_description, 
                cc_themes.id as lesson_id, cc_themes.description as lesson_description, cc_themes.title as lesson_title,
                cc_units.title as unit_title, cc_themes.supporting_activity,
    	(SELECT count(theme_id)  as tag_count  from cc_pf_theme_tags WHERE cc_pf_theme_tags.theme_id =lesson_id) as 
    	tag_count 
    	FROM cc_units
    	LEFT JOIN cc_themes ON cc_themes.unit_id = cc_units.id
    	WHERE cc_units.id = cc_themes.unit_id AND
    		cc_units.curriculum_id = $curriculum_id
    		$filter_eliminated
    	ORDER BY grade_id, cc_units.sequence, cc_themes.sequence";
    	#&Apache::Promse::logthis($qry);
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $district_curriculum_root = $doc->createElement('curriculum');
        $district_curriculum_root->setAttribute('name', 'lesson');
        $district_curriculum_root->setAttribute('title','District Curriculum');
        $district_curriculum_root->setAttribute('eliminated',$eliminated_attribute);
        my $in_grade = 0;
        my $grade_element;
        my $unit_element;
        my $unit_text_node;
        my $unit_description_element;
        my $unit_title_element;
        my $lesson_element;
        my $lesson_text_node;
        my $lesson_title_element;
        my $current_grade = -1;
        my $current_unit = -1;
        my $lesson_description;
        while (my $lesson = $sth->fetchrow_hashref()) {
            if ($current_grade ne $$lesson{'grade'}) {
                $current_grade = $$lesson{'grade'};
                if ($in_grade) {
                    $grade_element->appendChild($unit_element);
                    $district_curriculum_root->appendChild($grade_element);
                }
                $grade_element = $doc->createElement('grade');
                $in_grade = 1;
                $grade_element->setAttribute('gradelevel', $$lesson{'grade'});
                $unit_element = $doc->createElement('unit');
                $unit_element->setAttribute('id',$$lesson{'unit_id'});
                $unit_title_element = $doc->createElement('title');
                $unit_text_node = $doc->createTextNode($$lesson{'unit_title'});
                $unit_title_element->appendChild($unit_text_node);
                $unit_element->appendChild($unit_title_element);
                $unit_description_element = $doc->createElement('description');
                $unit_text_node = $doc->createTextNode($$lesson{'unit_description'});
                $unit_description_element->appendChild($unit_text_node);
                $lesson_element = $doc->createElement('lesson');
                $lesson_element->setAttribute('id', $$lesson{'lesson_id'});
                $lesson_element->setAttribute('tagcount', $$lesson{'tag_count'});
                $lesson_element->setAttribute('grade',$$lesson{'grade'});
                $lesson_element->setAttribute('supportingactivity',$$lesson{'supporting_activity'});
                $lesson_description = $doc->createElement('description');
                $lesson_text_node = $doc->createTextNode($$lesson{'lesson_description'});
                $lesson_description->appendChild($lesson_text_node);
                $lesson_element->appendChild($lesson_description);
                $unit_element->appendChild($lesson_element);
            }   else {
                if ($current_unit ne $$lesson{'unit_id'}) {
                    $current_unit = $$lesson{'unit_id'};
                    $grade_element->appendChild($unit_element);
                    $unit_element = $doc->createElement('unit');
                    $unit_element->setAttribute('id',$$lesson{'unit_id'});
                    $unit_text_node = $doc->createTextNode($$lesson{'unit_description'});
                    $unit_element->appendChild($unit_text_node);
                    $lesson_element = $doc->createElement('lesson');
                    $lesson_element->setAttribute('id', $$lesson{'lesson_id'});
                    $lesson_element->setAttribute('tagcount', $$lesson{'tag_count'});
                    $lesson_element->setAttribute('grade',$$lesson{'grade'});
                    $lesson_element->setAttribute('supportingactivity',$$lesson{'supporting_activity'});
                    $lesson_title_element = $doc->createElement('title');
                    $lesson_text_node = $doc->createTextNode($$lesson{'lesson_title'});
                    $lesson_title_element->appendChild($lesson_text_node);
                    $lesson_element->appendChild($lesson_title_element);
                    $lesson_description = $doc->createElement('description');
                    $lesson_text_node = $doc->createTextNode($$lesson{'lesson_description'});
                    $lesson_description->appendChild($lesson_text_node);
                    $lesson_element->appendChild($lesson_description);
                    $unit_element->appendChild($lesson_element);
                } else {
                    $lesson_element = $doc->createElement('lesson');
                    $lesson_element->setAttribute('id', $$lesson{'lesson_id'});
                    $lesson_element->setAttribute('tagcount', $$lesson{'tag_count'});
                    $lesson_element->setAttribute('grade',$$lesson{'grade'});
                    $lesson_element->setAttribute('supportingactivity',$$lesson{'supporting_activity'});
                    $lesson_title_element = $doc->createElement('title');
                    $lesson_text_node = $doc->createTextNode($$lesson{'lesson_title'});
                    $lesson_title_element->appendChild($lesson_text_node);
                    $lesson_element->appendChild($lesson_title_element);
                    $lesson_description = $doc->createElement('description');
                    $lesson_text_node = $doc->createTextNode($$lesson{'lesson_description'});
                    $lesson_description->appendChild($lesson_text_node);
                    $lesson_element->appendChild($lesson_description);
                    $unit_element->appendChild($lesson_element);
                }
            }
        }
        if ($in_grade) {
            $grade_element->appendChild($unit_element);
            $district_curriculum_root->appendChild($grade_element);
        }
        &xml_header($r);
        $r->print($district_curriculum_root->toString);
    }

    sub build_theme_xml() {
        my ($xml_doc,$theme_xml,$theme) = @_;
        $theme_xml->setAttribute('unitid',$$theme{'unit_id'});
        $theme_xml->setAttribute('id',$$theme{'theme_id'});
        $theme_xml->setAttribute('supportingactivity',$$theme{'supporting_activity'});
        my $eliminated = $$theme{'eliminated'}?'1':'0';
        $theme_xml->setAttribute('eliminated',$eliminated);
        if ($eliminated) {
            my $lesson_notes_element = $xml_doc->createElement('lessonnotes');
            my $notes_text_node = $xml_doc->createTextNode($$theme{'lesson_notes'});
            $lesson_notes_element->appendChild($notes_text_node);
            $theme_xml->appendChild($lesson_notes_element);
        }
        my $tagged = $$theme{'tagged'}?1:0;
        $theme_xml->setAttribute('tagged',$tagged);
        my $title = $xml_doc->createElement('title');
        my $title_text = $xml_doc->createTextNode($$theme{'theme_title'});
        $title->appendChild($title_text);
        $theme_xml->appendChild($title);
        my $description = $xml_doc->createElement('description');
        my $description_text = $xml_doc->createTextNode($$theme{'theme_description'});
        $description->appendChild($description_text);
        $theme_xml->appendChild($description);
        if ($$theme{'principle_id'}) {
            my $tag_element = $xml_doc->createElement('tag');
            $tag_element->setAttribute('principleid',$$theme{'principle_id'});
            my $tag_text_node = $xml_doc->createTextNode($$theme{'principle'});
            $tag_element->appendChild($tag_text_node);
            $theme_xml->appendChild($tag_element);
        }
        return($theme_xml);
    }
    sub build_lesson_element {
        my($row, $doc) = @_;
        my $lesson_element;
        $lesson_element = $doc->createElement('lesson');
        $lesson_element->setAttribute('id',$$row{'lesson_id'});
        $lesson_element->setAttribute('grade', $$row{'unit_grade'});
        $lesson_element->setAttribute('sequence', $$row{'lesson_sequence'});
        my $supporting_activity = $$row{'supporting_activity'}?1:0;
        $lesson_element->setAttribute('supportingactivity', $supporting_activity);
        my $lesson_title_element = $doc->createElement('title');
        my $lesson_title_text = $doc->createTextNode($$row{'theme_title'});
        $lesson_title_element->appendChild($lesson_title_text);
        $lesson_element->appendChild($lesson_title_element);
        my $lesson_description_element = $doc->createElement('description');
        my $lesson_description_text = $doc->createTextNode($$row{'theme_description'});
        $lesson_description_element->appendChild($lesson_description_text);
        $lesson_element->appendChild($lesson_description_element);
        return ($lesson_element);
    }
    sub build_glce_element {
        my($row, $doc) = @_;
        my $glce_element;
        my $glce_code = $$row{'glce_strand_code'} . "." . $$row{'glce_domain_code'} . "." . $$row{'glce_grade'} . "." . $$row{'glce_order'};
        $glce_element = $doc->createElement('glce');
        $glce_element->setAttribute('id',$$row{'glce_id'});
        $glce_element->setAttribute('code', $glce_code);
        $glce_element->setAttribute('grade', $$row{'glce_grade'});
        my $glce_description_element = $doc->createElement('description');
        my $glce_description_text = $doc->createTextNode($$row{'glce_description'});
        $glce_description_element->appendChild($glce_description_text);
        $glce_element->appendChild($glce_description_element);
        return ($glce_element);
    }
    sub build_subpoint_element {
        my($row, $doc) = @_;
        my $subpoint_element = $doc->createElement('subpoint');
        $subpoint_element->setAttribute('id',$$row{'subpoint_id'});
        $subpoint_element->setAttribute('missingtag','0');
        my $subpoint_description_element = $doc->createElement('description');
        my $subpoint_description_text = $doc->createTextNode($$row{'subpoint_description'});
        $subpoint_description_element->appendChild($subpoint_description_text);
        $subpoint_element->appendChild($subpoint_description_element);
        return($subpoint_element);
    }
    sub build_strand_element {
        my($row, $doc) = @_;
        # $doc is xml object
        my $strand_element = $doc->createElement('strand');
        $strand_element->setAttribute('id',$$row{'strand_id'});
        $strand_element->setAttribute('code',$$row{'strand_id'});
        $strand_element->setAttribute('missingtag','0');
        my $strand_description_element = $doc->createElement('description');
        my $strand_description_text = $doc->createTextNode($$row{'strand_description'});
        $strand_description_element->appendChild($strand_description_text);
        $strand_element->appendChild($strand_description_element);
        return($strand_element);
    }
    sub build_standard_element {
        my($row, $doc) = @_;
        my $standard_element = $doc->createElement('standard');
        $standard_element->setAttribute('id',$$row{'standard_id'});
        $standard_element->setAttribute('missingtag','0');
        my $standard_description_element = $doc->createElement('description');
        my $standard_description_text = $doc->createTextNode($$row{'standard_description'});
        $standard_description_element->appendChild($standard_description_text);
        $standard_element->appendChild($standard_description_element);
        return($standard_element);
    }
    sub get_science_display_by_principle {
        my ($r) = @_;
        my $curriculum_id = $r->param('curriculumid');
        my %params;
        my $qry;
        my $sth;
        $qry = "SELECT cc_themes.id AS lesson_id, cc_themes.title, cc_themes.description,
                cc_themes.id AS lesson_count_id,
                cc_units.grade_id as grade, cc_pf_theme_tags.pf_end_id as pf_end_id,
              cc_pf_theme_tags.theme_id, cc_principles.id AS principle_id, cc_units.id as unit_id,
              cc_units.title as unit_title,
              (select count(cc_lesson_history.lesson_id) AS change_count
               FROM cc_lesson_history WHERE cc_lesson_history.lesson_id = lesson_count_id) as change_count
            FROM cc_principles
    	LEFT JOIN (cc_pf_theme_tags,cc_themes, cc_units)
    	 ON 
    	(cc_pf_theme_tags.pf_end_id = cc_principles.id 
    	AND cc_pf_theme_tags.theme_id IN (SELECT cc_pf_theme_tags.theme_id FROM cc_pf_theme_tags)
    		AND cc_themes.id = cc_pf_theme_tags.theme_id
    		AND cc_units.id = cc_themes.unit_id 
    	AND cc_units.curriculum_id = $curriculum_id)
            ORDER BY cc_principles.id, cc_units.grade_id, cc_units.sequence, cc_themes.sequence
    
    ";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        #&Apache::Promse::logthis($qry);
        my $doc = XML::DOM::Document->new;
        my $root_lessons = $doc->createElement('lessons');
        my $principle_element;
        my $in_principle = 0;
        my $grade_element;
        my $in_grade = 0;
        my $grade = -1;
        my $principle = -1;
        while (my $row = $sth->fetchrow_hashref()) {
            if ($principle ne $$row{'principle_id'}) {
                if ($in_principle) {
                    $principle_element->appendChild($grade_element);
                    $root_lessons->appendChild($principle_element);
                }
                $principle = $$row{'principle_id'};
                $principle_element = $doc->createElement('principle');
                $principle_element->setAttribute('principleid',$$row{'principle_id'});
                $in_principle = 1;
                if ($$row{'grade'} || ($$row{'grade'} eq 0)) {
                    $grade_element = $doc->createElement('grade');
                    $grade_element->setAttribute('gradelevel',$$row{'grade'});
                    $in_grade = 1;
                    $grade = $$row{'grade'};
                    my $lesson_element = $doc->createElement('lesson');
                    $lesson_element->setAttribute('id',$$row{'lesson_id'});
                    $lesson_element->setAttribute('unitid', $$row{'unit_id'});
                    $lesson_element->setAttribute('gradelevel', $$row{'grade'});
                    $lesson_element->setAttribute('changes', $$row{'change_count'});
                    my $unit_title_element = $doc->createElement('unittitle');
                    my $unit_title_text = $doc->createTextNode($$row{'unit_title'});
                    $unit_title_element->appendChild($unit_title_text);
                    $lesson_element->appendChild($unit_title_element);
                    my $description_element = $doc->createElement('description');
                    my $description_text = $doc->createTextNode($$row{'description'});
                    $description_element->appendChild($description_text);
                    my $title_element = $doc->createElement('title');
                    my $title_text = $doc->createTextNode($$row{'title'});
                    $title_element->appendChild($title_text);
                    $lesson_element->appendChild($title_element);
                    $lesson_element->appendChild($description_element);
                    $grade_element->appendChild($lesson_element);
                } else {
                    $root_lessons->appendChild($principle_element);
                    $in_principle = 0;
                }
            } else {
                if ($$row{'grade'}) {
                    if ($grade ne $$row{'grade'}) {
                        if ($in_grade) {
                            $principle_element->appendChild($grade_element);
                        }
                        $grade_element = $doc->createElement('grade');
                        $grade_element->setAttribute('gradelevel',$$row{'grade'});
                        $in_grade = 1;
                        $grade = $$row{'grade'};
                    }
                    my $lesson_element = $doc->createElement('lesson');
                    $lesson_element->setAttribute('id',$$row{'lesson_id'});
                    $lesson_element->setAttribute('gradelevel',$$row{'grade'});
                    $lesson_element->setAttribute('unitid', $$row{'unit_id'});
                    $lesson_element->setAttribute('changes', $$row{'change_count'});
                    my $unit_title_element = $doc->createElement('unittitle');
                    my $unit_title_text = $doc->createTextNode($$row{'unit_title'});
                    $unit_title_element->appendChild($unit_title_text);
                    $lesson_element->appendChild($unit_title_element);
                    my $description_element = $doc->createElement('description');
                    my $description_text = $doc->createTextNode($$row{'description'});
                    $description_element->appendChild($description_text);
                    my $title_element = $doc->createElement('title');
                    my $title_text = $doc->createTextNode($$row{'title'});
                    $title_element->appendChild($title_text);
                    $lesson_element->appendChild($title_element);
                    $lesson_element->appendChild($description_element);
                    $grade_element->appendChild($lesson_element);
                }
            }
        }
        if ($in_grade) {
            $principle_element->appendChild($grade_element);
        }
        if ($in_principle) {
            $root_lessons->appendChild($principle_element);
        }
        &xml_header($r);
        $r->print($root_lessons->toString);
    }
    sub get_lesson_tags {
        my ($r) = @_;
        my $curriculum_id = $r->param('curriculumid');
        my $qry;
        my $sth;
        my $doc = XML::DOM::Document->new;
        $qry = "SELECT cc_pf_theme_tags.theme_id AS lesson_id, cc_pf_theme_tags.standard_flag, cc_pf_theme_tags.pf_end_id,
                        cc_units.grade_id as lesson_grade, cc_themes.supporting_activity, cc_pf_theme_tags.strength
    	FROM cc_pf_theme_tags, cc_themes, cc_units
    	WHERE theme_id IN (SELECT cc_themes.id as theme_id
    					FROM cc_units, cc_themes
    					WHERE cc_units.id = cc_themes.unit_id AND
    					cc_units.curriculum_id = $curriculum_id) AND
    					cc_units.id = cc_themes.unit_id AND
    					cc_pf_theme_tags.theme_id = cc_themes.id
    					ORDER by cc_pf_theme_tags.pf_end_id";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $unit_element;
        my $unit_text_node;
        my $unit_description_element;
        my $unit_title_element;
        my $lesson_text_node;
        my $lesson_title_element;
        my $current_unit = -1;
        my $lesson_description;
        my $current_pf_end_id = -1;
        my $lesson_tags_root = $doc->createElement('lessontags');
        my $first_row = 1;
        my $tag_element;
        my $lesson_element;
        while (my $tag = $sth->fetchrow_hashref()) {
            if ($$tag{'pf_end_id'} ne $current_pf_end_id) {
                $current_pf_end_id = $$tag{'pf_end_id'};
                if (! $first_row) {
                    $lesson_tags_root->appendChild($tag_element);
                } else {
                    $first_row = 0;
                }
                $tag_element = $doc->createElement('tag');
                $tag_element->setAttribute('strength',$$tag{'strength'});
                $tag_element->setAttribute('id',$$tag{'pf_end_id'});
                $tag_element->setAttribute('standardflag',$$tag{'standard_flag'});
            }
            $lesson_element = $doc->createElement('lesson');
            $lesson_element->setAttribute('id',$$tag{'lesson_id'});
            $lesson_element->setAttribute('grade',$$tag{'lesson_grade'});
            $lesson_element->setAttribute('supportingactivity',$$tag{'supporting_activity'});
            $tag_element->appendChild($lesson_element);
        }
        if (! $first_row) {
            $lesson_tags_root->appendChild($tag_element);
        }
        &xml_header($r);
        $r->print($lesson_tags_root->toString);
    }
    sub get_framework {
        my ($r) = @_;
        my $framework_id = $r->param('frameworkid');
        my $curriculum_id = $r->param('curriculumid');
        my $qry = "SELECT framework_levels.depth, framework_levels.title 
                    FROM framework_levels 
                    WHERE framework_levels.framework_id = $framework_id
                    ORDER BY depth";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my %level_names;
        while (my $row = $sth->fetchrow_hashref()) {
            $level_names{$$row{'depth'}} = $$row{'title'};
        }
        $qry = "SELECT framework_items.id, framework_items.parent_id, framework_items.grade, framework_items.code,
                    framework_items.sequence, framework_items.title, framework_items.description,
                    framework_strands.description as strand_description, framework_strands.sequence as strand_sequence
                FROM framework_items
                LEFT JOIN framework_strands ON framework_items.code = framework_strands.code
                WHERE framework_items.framework_id = $framework_id
                ORDER BY framework_items.grade, framework_strands.sequence, framework_items.sequence";
        $sth = $env{'dbh'}->prepare($qry); 
        $sth->execute();
        my @framework;
        while (my $row = $sth->fetchrow_hashref()) {
            push @framework, $row;
        }
        $qry = "SELECT frameworks.title, frameworks.description, framework_levels.depth
                FROM frameworks, framework_levels
                WHERE frameworks.id = $framework_id AND
                    frameworks.id = framework_levels.framework_id
                ORDER BY depth desc";
        $sth = $env{'dbh'}->prepare($qry); 
        $sth->execute();
        my $framework_info = $sth->fetchrow_hashref();
        my $framework_title = $$framework_info{'title'};
        my $framework_description = $$framework_info{'description'};
        my $current_parent = 0;
        my $current_level = 0;
        my %existing_parents;
        my %item_levels;
        my $doc = XML::DOM::Document->new;
        my $framework_root = $doc->createElement('framework');
        $framework_root->setAttribute('title', $framework_title);
        $framework_root->setAttribute('id', $framework_id);
        $framework_root->setAttribute('depth', $$framework_info{'depth'});
        my $framework_description_element = $doc->createElement('description');
        my $framework_text_node = $doc->createTextNode($framework_description);
        $framework_description_element->appendChild($framework_text_node);
        $framework_root->appendChild($framework_description_element);
        my @framework_levels;
        my $current_grade = -1;
        my $current_strand = '';
        # need to wrap strands in a grade
        my $grade_element;
        my $strand_element;
        foreach my $framework_item (@framework) {
            # print STDERR "framework item \n";
            if ($$framework_item{'grade'} ne $current_grade) {
                $current_grade = $$framework_item{'grade'};
                if ($grade_element) { # check if we have a grade in process
                    while ($current_level > 0) {
                        $framework_levels[$current_level - 1] -> appendChild($framework_levels[$current_level]);
                        $current_level --;
                    }
                    $current_level = 1;
                    $grade_element->appendChild($framework_levels[0]);
                    $framework_root->appendChild($grade_element);
                }
                $grade_element = $doc->createElement('grade');
                $grade_element->setAttribute('gradelevel',$current_grade);
				my $displayGrade = $current_grade eq 0?'K':$current_grade;
				$displayGrade = $current_grade eq 9?'HS':$current_grade;
				$grade_element->setAttribute('id', 'Grade '.$displayGrade);
                $strand_element = $doc->createElement('node');
                $strand_element->setAttribute('id', $$framework_item{'code'});
                $strand_element->setAttribute('title',$level_names{'0'});
                $strand_element->setAttribute('sequence',$$framework_item{'strand_sequence'});
                $strand_element->setAttribute('code',$$framework_item{'code'});
                $strand_element->setAttribute('depth','0');
                my $strand_description_element = $doc->createElement('description');
                my $strand_text_node = $doc->createTextNode($$framework_item{'strand_description'});
                $strand_description_element->appendChild($strand_text_node);
                $strand_element->appendChild($strand_description_element);
                $current_strand = $$framework_item{'code'};
                $framework_levels[0] = $strand_element;
                $current_level = 1;
                my $node_element = &build_framework_node($framework_item, \%level_names, $current_level, $doc);
                $item_levels{$$framework_item{'id'}} = $current_level;
                $framework_levels[$current_level] = $node_element;
            } elsif ($$framework_item{'code'} ne $current_strand) {
                $current_strand = $$framework_item{'code'};
                # close the nodes and append to strand
                while ($current_level > 0) {
                    $framework_levels[$current_level - 1] -> appendChild($framework_levels[$current_level]);
                    $current_level --;
                }
                $current_level = 1;
                $grade_element->appendChild($framework_levels[0]);
                $strand_element = $doc->createElement('node');
                $strand_element->setAttribute('id',$$framework_item{'code'});
                $strand_element->setAttribute('title',$level_names{'0'});
                $strand_element->setAttribute('sequence',$$framework_item{'strand_sequence'});
                $strand_element->setAttribute('code',$$framework_item{'code'});
                $strand_element->setAttribute('depth','0');
                my $strand_description_element = $doc->createElement('description');
                my $strand_text_node = $doc->createTextNode($$framework_item{'strand_description'});
                $strand_description_element->appendChild($strand_text_node);
                $strand_element->appendChild($strand_description_element);
                $framework_levels[0] = $strand_element;
                my $node_element = &build_framework_node($framework_item, \%level_names, $current_level, $doc);
                $item_levels{$$framework_item{'id'}} = $current_level;
                $framework_levels[$current_level] = $node_element;
            } elsif ($$framework_item{'parent_id'} eq 0) {
                # top level of hierarchy, so have dispense with lower levels under construction
                while ($current_level > 0) {
                    $framework_levels[$current_level - 1] -> appendChild($framework_levels[$current_level]);
                    $current_level --;
                }
                $current_level = 1;
                # we save this so if this becomes a parent we know its level
                $item_levels{$$framework_item{'id'}} = $current_level;
                my $node_element = &build_framework_node($framework_item, \%level_names, $current_level, $doc);
                #build the rest of the element here
                $item_levels{$$framework_item{'id'}} = $current_level;
                $framework_levels[$current_level] = $node_element;
                
            } else {
                if ($current_parent eq $$framework_item{'parent_id'}) {
                    # making a node that is a sibling to node that is 
                    # currently stored in $framework_levels[$current_level]
                    # so need to take the earlier sibling and append to parent
                    $framework_levels[$current_level - 1]->appendChild($framework_levels[$current_level]);
                    # now create new sibling
                    my $node_element = &build_framework_node($framework_item, \%level_names, $current_level, $doc);
                    $item_levels{$$framework_item{'id'}} = $current_level;
                    # and store in $framework_levels
                    $framework_levels[$current_level] = $node_element;
                } else {
                    # we're changing parent - need to know if we've already created any children
                    # of that parent
                    if ($existing_parents{$$framework_item{'parent_id'}}) {
                        # here if we've seen this parent before it means we're 
                        # creating a node at a higher level 
                        while ($current_level > $item_levels{$$framework_item{'parent_id'}} + 1) {
                            $framework_levels[$current_level - 1]->appendChild($framework_levels[$current_level]);
                            $current_level --;
                        }
                        $framework_levels[$current_level - 1]->appendChild($framework_levels[$current_level]);
                        my $node_element = &build_framework_node($framework_item, \%level_names, $current_level, $doc);
                        $item_levels{$$framework_item{'id'}} = $current_level;
                        $framework_levels[$current_level] = $node_element;
                    } else {
                        # save this item in lists of parents
                        $existing_parents{$$framework_item{'parent_id'}} = 1;
                        $current_level ++;
                        my $node_element = &build_framework_node($framework_item, \%level_names, $current_level, $doc);
                        $item_levels{$$framework_item{'id'}} = $current_level;
                        $framework_levels[$current_level] = $node_element;
                        # deeper into the hierarchy
                    }
                    # print STDERR $framework_levels[$current_level]->toString();
                    $current_parent = $$framework_item{'parent_id'};
                }
            }
        }
        while ($current_level > 0) {
            $framework_levels[$current_level - 1] -> appendChild($framework_levels[$current_level]);
            $current_level --;
        } 
        $grade_element->appendChild($framework_levels[0]);
        $framework_root->appendChild($grade_element);
        &xml_header($r);
        $r->print($framework_root->toString);
    }
    sub build_framework_node {
        my ($framework_item, $level_names, $current_level, $doc) = @_;
        my $node = $doc->createElement('node');
        $node->setAttribute('title',$$level_names{$current_level});
        $node->setAttribute('depth',$current_level);
        $node->setAttribute('id',$$framework_item{'id'});
        $node->setAttribute('grade',$$framework_item{'grade'});
        my $text_node = $doc->createTextNode($$framework_item{'description'});
        my $description_element = $doc->createElement('description');
        $description_element->appendChild($text_node);
        $node->appendChild($description_element);
        return($node);
    }
    sub get_math_display_by_strand {
        my ($r) = @_;
        my $curriculum_id = $r->param('curriculumid');
        my %params;
        my $qry;
        my $sth;
        my @mcm;
        my @curriculum;
        my @tags;
        my @mcm_to_glce;
        my @glces;
        # retrieving 5 record sets to build three XML structures
        # first one retrieves the MCM (math framework);
        my $test_condition1 = ' AND cc_pf_standards.grade = 3 ';
        $test_condition1 = '';
        my $test_condition = ' AND cc_units.grade = 3 ';
        $test_condition = '';
        $qry = "SELECT glce_mcm.glce_id, glce_mcm.mcm_id, glce_mcm.mcm_standard_flag 
    	FROM glce_mcm";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        while (my $row = $sth->fetchrow_hashref()) {
            push(@mcm_to_glce, {%$row});
        }
        $qry = "SELECT glces.id, glces.glce_order, glces.description, glces.strand_code as strand_id, glces.domain_code, 
                glces.grade, glce_strands.description as strand_description, glces.domain_code as standard_id,
                glce_domains.description as standard_description, glces.id as subpoint_id, 
                glces.description as subpoint_description
    	FROM glces, glce_strands, glce_domains
    	WHERE glces.strand_code = glce_strands.code AND
    		glces.domain_code = glce_domains.code
    	ORDER BY glces.grade, glces.strand_code, glces.domain_code, glces.glce_order";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        while (my $row = $sth->fetchrow_hashref()) {
            push(@glces, {%$row});
        }
    
        # all data retrieved from database, now prepare for building XML
        # this creates a lookup using pf_end_id and standard_flag to get an array of lessons
        # now we create a similar lookup for glces
        my $doc = XML::DOM::Document->new;
        my $curriculum_root = $doc->createElement('modelcurriculum');
        $curriculum_root->setAttribute('title',"Math Coherence Model");
        my $link_element = $doc->createElement('linkelement');
        $link_element->setAttribute('name', 'lesson');
        $link_element->setAttribute('title', 'District Curriculum');
        $curriculum_root->appendChild($link_element);
        $link_element = $doc->createElement('linkelement');
        $link_element->setAttribute('name', 'glce');
        $link_element->setAttribute('title', 'Michigan GLCEs');
        $curriculum_root->appendChild($link_element);
        # finishes the first of three xml structures
        # now start the GLCEs so we can look up GLCE based on glce.id
        my $glce_root = $doc->createElement('lookup');
        $glce_root->setAttribute('title','Michigan GLCEs');
        $glce_root->setAttribute('name','glce');
        # following variable names established when doing only MCM
        # GLCE uses domain for standard and glce for subpoint but we use legacy names so far
        my $current_grade = -1;
        my $in_standard;
        my $in_strand = 0;
        my $in_grade = 0;
        my $strand_element;
        my $grade_element;
        my $lesson_element;
        my $standard_element;
        my $subpoint_element;
        my $current_strand = 0;
        my $current_standard = 0;
        my $current_subpoint = 0;
        my $tracer = 0;
        foreach my $glce(@glces) {
            if ($$glce{'subpoint_id'} eq 32) {
                $tracer = 1;
            }
            if ($current_grade ne $$glce{'grade'}) {
                $current_grade = $$glce{'grade'};
                $current_strand = $$glce{'strand_code'};
                $current_standard = $$glce{'standard_id'};
                if ($in_grade) {
                    # must be in strand and standard
                    $grade_element->appendChild($strand_element);
                    $strand_element->appendChild($standard_element);
                    $glce_root->appendChild($grade_element);
                }
                $grade_element = $doc->createElement('grade');
                $grade_element->setAttribute('gradelevel', $$glce{'grade'});
                $in_grade = 1;
                $strand_element = &build_strand_element($glce,$doc);
                $in_strand = 1;
                $standard_element = &build_standard_element($glce, $doc);
                $in_standard = 1;
                $subpoint_element = &build_subpoint_element($glce, $doc);
                $standard_element->appendChild($subpoint_element);
            } else {
                if ($current_strand ne $$glce{'strand_code'}) {
                    $current_strand = $$glce{'strand_code'};
                    $strand_element->appendChild($standard_element);
                    $grade_element->appendChild($strand_element);
                    $strand_element = &build_strand_element($glce,$doc);
                    $in_strand = 1;
                    $standard_element = &build_standard_element($glce, $doc);
                    $in_standard = 1;
                    $subpoint_element = &build_subpoint_element($glce, $doc);
                    $standard_element->appendChild($subpoint_element);
                } else {
                    if ($current_standard ne $$glce{'standard_id'}) {
                        $strand_element->appendChild($standard_element);
                        $current_standard = $$glce{'standard_id'};
                        $standard_element = &build_standard_element($glce, $doc);
                        $in_standard = 1;
                        $subpoint_element = &build_subpoint_element($glce, $doc);
                        $standard_element->appendChild($subpoint_element);
                    } else {
                        $subpoint_element = &build_subpoint_element($glce, $doc);
                        $standard_element->appendChild($subpoint_element);
                    }
                }
            }
        }
        if ($in_standard) {
            $strand_element->appendChild($standard_element);
        }
        if ($in_strand) {
            $grade_element->appendChild($strand_element);
        }
        $glce_root->appendChild($grade_element);
        # finishes the glce lookup
        my $district_curriculum_root = $doc->createElement('lookup');
        $district_curriculum_root->setAttribute('name', 'lesson');
        $district_curriculum_root->setAttribute('title','District Curriculum');
        $in_grade = 0;
        my $unit_element;
        my $unit_text_node;
        my $unit_description_element;
        my $unit_title_element;
        my $lesson_text_node;
        my $lesson_title_element;
        my $current_unit = -1;
        my $lesson_description;
        my $current_lesson_id = -1;
        my $lesson_tags_element = $doc->createElement('tags');
        my $first_row = 1;
        foreach my $tag(@tags) {
            if ($$tag{'lesson_id'} ne $current_lesson_id) {
                $current_lesson_id = $$tag{'lesson_id'};
                if (! $first_row) {
                    $lesson_tags_element->appendChild($lesson_element);
                } else {
                    $first_row = 0;
                }
                $lesson_element = $doc->createElement('lesson');
                $lesson_element->setAttribute('id',$$tag{'lesson_id'});
                $lesson_element->setAttribute('grade',$$tag{'lesson_grade'});
            }
            my $tag_element = $doc->createElement('tag');
            $tag_element->setAttribute('standardflag',$$tag{'standard_flag'});
            $tag_element->setAttribute('endid',$$tag{'pf_end_id'});
            $lesson_element->appendChild($tag_element);
        }
        $lesson_tags_element->appendChild($lesson_element);
        $curriculum_root->appendChild($district_curriculum_root);
        # $curriculum_root->appendChild($glce_root);
        $curriculum_root->appendChild($lesson_tags_element);
        &xml_header($r);
        $r->print($curriculum_root->toString);
    }
    sub append_linked_lesson {
        my ($element, $mcm_row, $doc) = @_;
        if ($$mcm_row{'theme_id'}) {
            my $lesson_element = $doc->createElement('lesson');
            $lesson_element->setAttribute('id', $$mcm_row{'theme_id'});
            $lesson_element->setAttribute('grade', $$mcm_row{'lesson_grade'});
            $lesson_element->setAttribute('supportingactivity', $$mcm_row{'supporting_activity'});
            # $lesson_element->setAttribute('action', $$mcm_row{'action'});
            # $lesson_element->setAttribute('date', $$mcm_row{'change_date'});
            $element->appendChild($lesson_element);
        }
        return($element);
    }
    sub append_link_elements {
        # needs to be generalized 
        # really really needs to be generalized
        my ($element, $lesson_lookup, $glce_lookup, $tag_lookup, $mcm_glce_lookup, $key, $doc) = @_;
        # key is pf_end_id and standard flag - identifies mcm node
        if (exists $$tag_lookup{$key}) {
            my $lesson_list = $$tag_lookup{$key};
            foreach my $lesson (@$lesson_list) {
                my $lesson_info = $$lesson_lookup{$$lesson{'lesson_id'}};
                my $link_element = $doc->createElement('linkelement');
                $link_element->setAttribute('name','lesson');
                $link_element->setAttribute('id',$$lesson{'lesson_id'});
                $link_element->setAttribute('grade',$$lesson_info{'grade'});
                $link_element->setAttribute('glceorder',$$lesson_info{'glce_order'});
                my $supporting_activity_flag = $$lesson_info{'supporting_activity'}?1:0;
                $link_element->setAttribute('supportingactivity',$supporting_activity_flag);
                $element->appendChild($link_element);
            }
        }
        if (exists $$mcm_glce_lookup{$key}) {
            my $glce_list = $$mcm_glce_lookup{$key};
            foreach my $glce (@$glce_list) {
                my $glce_item = $$glce_lookup{$$glce{'glce_id'}};
                my $link_element = $doc->createElement('linkelement');
                $link_element->setAttribute('name','glce');
                $link_element->setAttribute('id',$$glce{'glce_id'});
                $link_element->setAttribute('grade',$$glce_item{'grade'});
                $link_element->setAttribute('supportingactivity','0');
                $element->appendChild($link_element);
            }
        }
        return($element);
    }
    sub get_math_display {
        my ($r) = @_;
        my $curriculum_id = $r->param('curriculumid');
        my %params;
        my $qry;
        my $sth;
        my @untagged_lessons;
        $params{'doc'} = XML::DOM::Document->new;
        $params{'current_grade'} = 0;
        $params{'current_strand'} = 0;
        $params{'current_standard'} = 0;
        $params{'in_grade'} = 0;
        $params{'in_strand'} = 0;
        $params{'in_standard'} = 0;
        $params{'framework_element'} = $params{'doc'}->createElement("framework");
        $qry = "SELECT cc_units.grade_id as grade, cc_themes.id AS lesson_id, cc_themes.title as theme_title, 
                cc_themes.description as theme_description
                FROM cc_themes, cc_units
                WHERE cc_units.curriculum_id = $curriculum_id AND
                    cc_themes.unit_id = cc_units.id AND
                    cc_themes.id NOT IN (SELECT cc_pf_theme_tags.theme_id FROM cc_pf_theme_tags)
                ORDER BY cc_units.grade_id, cc_units.sequence, cc_themes.sequence";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        while (my $row = $sth->fetchrow_hashref()) {
            push(@untagged_lessons, {%$row});
        }
        $qry = "SELECT cc_pf_standards.grade, cc_pf_strands.strand as strand_description, cc_pf_strands.id as strand_id, 
                    cc_pf_standards.id as standard_id, cc_pf_standards.standard as standard_description, 
                    cc_pf_subpoints.subpoint as subpoint_description, cc_pf_subpoints.id as subpoint_id,
                    cc_pf_theme_tags.standard_flag, cc_pf_theme_tags.theme_id, cc_themes.title as theme_title,
                    cc_themes.description as theme_description, cc_units.id as unit_id
                    FROM (cc_pf_strands, cc_pf_standards)
                    LEFT JOIN cc_pf_subpoints ON cc_pf_subpoints.standard_id = cc_pf_standards.id
                    LEFT JOIN (cc_pf_theme_tags) ON  ((cc_pf_theme_tags.pf_end_id = cc_pf_standards.id) OR 
                              (cc_pf_theme_tags.pf_end_id = cc_pf_subpoints.id))
                    LEFT JOIN (cc_themes, cc_units) ON (cc_themes.id = cc_pf_theme_tags.theme_id AND 
                                         cc_themes.unit_id = cc_units.id AND  
                                        cc_units.grade_id = cc_pf_standards.grade AND
                                         cc_units.curriculum_id = $curriculum_id)
                WHERE cc_pf_strands.id = cc_pf_standards.strand_id";
                # ORDER BY cc_pf_standards.grade, cc_pf_strands.id";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $doc = XML::DOM::Document->new;
        my $curriculum_root = $doc->createElement("curriculum");
        $curriculum_root->setAttribute('id',$curriculum_id);
        my $current_grade = - 1;
        my $current_strand = - 1;
        my $current_standard = - 1;
        my $current_subpoint = - 1;
        my $in_grade = 0;
        my $in_strand = 0;
        my $in_standard = 0;
        my $in_subpoint = 0;
        my $grade_element;
        my $strand_element;
        my $standard_element;
        my $subpoint_element;
        my $lesson_element;
        while (my $row = $sth->fetchrow_hashref()) {
            if ($current_grade ne $$row{'grade'}) {
                if ($in_grade) {
                    if ($in_subpoint) {
                        $standard_element->appendChild($subpoint_element);
                        $in_subpoint = 0;
                    }
                    $strand_element->appendChild($standard_element);
                    $in_standard = 0;
                    $grade_element->appendChild($strand_element);
                    my $next_lesson = $untagged_lessons[0];
                    while ($$next_lesson{'grade'} eq $current_grade) {
                        my $untagged_lesson = shift(@untagged_lessons);
                        $lesson_element = $doc->createElement('lesson');
                        $lesson_element->setAttribute('lessonid',$$untagged_lesson{'lesson_id'});
                        my $lesson_title_element = $doc->createElement('title');
                        my $lesson_title_text = $doc->createTextNode($$untagged_lesson{'theme_title'});
                        $lesson_title_element->appendChild($lesson_title_text);
                        $lesson_element->appendChild($lesson_title_element);
                        my $lesson_description_element = $doc->createElement('description');
                        my $lesson_description_text = $doc->createTextNode($$untagged_lesson{'theme_description'});
                        $lesson_description_element->appendChild($lesson_description_text);
                        $lesson_element->appendChild($lesson_description_element);
                        $grade_element->appendChild($lesson_element);
                        $next_lesson = $untagged_lessons[0];
                    }
                    $curriculum_root->appendChild($grade_element);
                    $grade_element = $doc->createElement('grade');
                    $grade_element->setAttribute('gradelevel', $$row{'grade'});
                }
                $grade_element = $doc->createElement('grade');
                $grade_element->setAttribute('gradelevel', $$row{'grade'});
                $in_grade = 1;
                $strand_element = &build_strand_element($row, $doc);
                $in_strand = 1;
                $standard_element = &build_standard_element($row, $doc);
                $in_standard = 1;
                if ($$row{'subpoint_id'}) {
                    $subpoint_element = &build_subpoint_element($row, $doc);
                    $in_subpoint = 1;
                    if ($$row{'theme_id'}) {
                        $lesson_element = &build_lesson_element($row, $doc);
                        $subpoint_element->appendChild($lesson_element);
                     } else {
                        $standard_element->appendChild($subpoint_element);
                        $in_subpoint = 0;
                     }
                } else {
                    if ($$row{'theme_id'}) {
                        $lesson_element = &build_lesson_element($row, $doc);
                        $standard_element->appendChild($lesson_element);
                    }  else {
                        $strand_element->appendChild($standard_element);
                        $in_standard = 0;
                    }
                }
                $current_grade = $$row{'grade'};
                $current_strand = $$row{'strand_id'};
                $current_standard = $$row{'standard_id'};
                $current_subpoint = $$row{'subpoint_id'};
            } else {
                if ($current_strand ne $$row{'strand_id'}) {
                    if ($in_subpoint) {
                        $standard_element->appendChild($subpoint_element);
                    }
                    $strand_element->appendChild($standard_element);
                    $grade_element->appendChild($strand_element);
                    $strand_element = &build_strand_element($row, $doc);
                    $in_strand = 1;
                    $standard_element = &build_standard_element($row, $doc);
                    $in_standard = 1;
                    if ($$row{'subpoint_id'}) {
                        $subpoint_element = &build_subpoint_element($row, $doc);
                        $in_subpoint = 1;
                        if ($$row{'theme_id'}) {
                            $lesson_element = &build_lesson_element($row, $doc);
                            $subpoint_element->appendChild($lesson_element);
                        } else {
                            $standard_element->appendChild($subpoint_element);
                        }
                    } else {
                        if ($$row{'theme_id'}) {
                            $lesson_element = &build_lesson_element($row, $doc);
                            $standard_element->appendChild($lesson_element);
                        } else {
                            $strand_element->appendChild($standard_element);
                            $in_standard = 0;
                        }
                    }
                    $current_strand = $$row{'strand_id'};
                    $current_standard = $$row{'standard_id'};
                    $current_subpoint = $$row{'subpoint_id'};
                } else {
                    if ($current_standard ne $$row{'standard_id'}) {
                        if ($in_subpoint) {
                            $standard_element->appendChild($subpoint_element);
                            $in_subpoint = 0;
                        }
                        $strand_element->appendChild($standard_element);
                        $standard_element = &build_standard_element($row, $doc);
                        $in_standard = 1;
                        if ($$row{'subpoint_id'}) { # subpoint?
                            $subpoint_element = &build_subpoint_element($row, $doc);
                            $in_subpoint = 1;
                            if ($$row{'theme_id'}) {
                                $lesson_element = &build_lesson_element($row, $doc);
                                $subpoint_element->appendChild($lesson_element, $doc);
                            } else {
                                $standard_element->appendChild($subpoint_element);
                                $in_subpoint = 0;
                            }
                            
                        } else {
                            if ($$row{'theme_id'}) {
                                $lesson_element = &build_lesson_element($row, $doc);
                                $standard_element->appendChild($lesson_element);
                            } else {
                                $strand_element->appendChild($standard_element);
                                $in_standard = 0;
                            }
                        }
                        $current_standard = $$row{'standard_id'};
                        $current_subpoint = $$row{'subpoint_id'};
                    } else {
                        if ($$row{'subpoint_id'} && ($current_subpoint ne $$row{'subpoint_id'})) { #not new grade, strand, standard
                            if ($in_subpoint) {
                                $standard_element->appendChild($subpoint_element);
                            }
                            $subpoint_element = &build_subpoint_element($row, $doc);
                            $in_subpoint = 1;
                            if ($$row{'theme_id'}) {
                                $lesson_element = &build_lesson_element($row, $doc);
                                $subpoint_element->appendChild($lesson_element);
                            } else {
                                $standard_element->appendChild($subpoint_element);
                                $in_subpoint = 0;
                            }
                            $current_subpoint = $$row{'subpoint_id'};
                        } else {
                            $lesson_element = &build_lesson_element($row, $doc);
                            $subpoint_element->appendChild($lesson_element);
                        }
                    }
                }
            }
        }
        # have to finish off
        if ($in_grade) {
            if ($in_strand){
                if ($in_standard) {
                    if ($in_subpoint) {
                        $standard_element->appendChild($subpoint_element);
                    }
                    $strand_element->appendChild($standard_element);
                }
                $grade_element->appendChild($strand_element);
            }
            $curriculum_root->appendChild($grade_element);
        }
        &xml_header($r);
        $r->print($curriculum_root->toString);
    }
    sub xml_header {
        my($r) = @_;
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n");
    }
    sub get_promse_math_framework_xml {
        my($r) = @_;
        my %params;
        my $row;
        $params{'doc'} = XML::DOM::Document->new;
        $params{'current_grade'} = 0;
        $params{'current_strand'} = 0;
        $params{'current_standard'} = 0;
        $params{'in_grade'} = 0;
        $params{'in_strand'} = 0;
        $params{'in_standard'} = 0;
        $params{'framework_element'} = $params{'doc'}->createElement("framework");
        my $grade_converted;
        my $qry = "SELECT grade, strand, cc_pf_strands.id as strand_id, cc_pf_standards.id as standard_id, cc_pf_subpoints.id as subpoint_id , standard, subpoint 
                   FROM cc_pf_strands, cc_pf_standards
                   LEFT JOIN cc_pf_subpoints on cc_pf_subpoints.standard_id = cc_pf_standards.id
                   WHERE cc_pf_strands.id = cc_pf_standards.strand_id ";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        while ($row = $sth->fetchrow_hashref()) {
            $grade_converted = !$$row{'grade'}?'K':$$row{'grade'};
            $grade_converted = $$row{'grade'} eq 9?'HS':$$row{'grade'};
            $params{'grade_converted'} = $grade_converted;
            if ($grade_converted ne $params{'current_grade'}) {
                $params{'current_grade'} = $grade_converted;
                if ($params{'in_grade'}) {
                    &close_grade($row,\%params);
                }
                &open_grade($row,\%params);
            } else {
                if ($$row{'strand_id'} && ($params{'current_strand'} ne $$row{'strand_id'})) {
                    $params{'current_strand'} = $$row{'strand_id'};
                    if($params{'in_strand'}) {
                        &close_strand($row,\%params);
                    }
                    &open_strand($row,\%params);
                } else {
                    if ($params{'current_standard'} ne $$row{'standard_id'}) {
                        if ($params{'in_standard'}) {
                            &close_standard($row,\%params);
                        }
                        &open_standard($row,\%params)
                    } else {
                        if ($$row{'subpoint_id'}) {
                            &open_subpoint($row,\%params);
                        }
                    }
                }
            }
        }
        &close_grade($row,\%params);
    #    $params{'strand_element'}->appendChild($params{'standard_element'});
    #    $params{'grade_element'}->appendChild($params{'strand_element'});
    #    $params{'framework_element'}->appendChild($params{'grade_element'});
        &xml_header($r);
        $r->print($params{'framework_element'}->toString);
    }
    sub close_grade {
        my ($row,$params) = @_;
        &close_strand($row,$params);
        $$params{'framework_element'}->appendChild($$params{'grade_element'});
        $$params{'in_grade'} = 0
    }
    sub open_grade {
        my ($row,$params) = @_;
        $$params{'grade_element'} = $$params{'doc'}->createElement("grade");
        $$params{'grade_element'}->setAttribute('gradelevel',$$params{'grade_converted'});
        $$params{'in_grade'} = 1;
        &open_strand($row,$params);
    }
    sub close_strand {
        my ($row,$params) = @_;
        &close_standard($row,$params);
        $$params{'strand_element'}->appendChild($$params{'standard_element'});
        $$params{'grade_element'}->appendChild($$params{'strand_element'});
        $$params{'in_strand'} = 0;
    }
    sub open_strand {
        my ($row,$params) = @_;
        $$params{'strand_element'} = $$params{'doc'}->createElement('strand');
        $$params{'strand_element'}->setAttribute('strandid',$$row{'strand_id'});
        my $strand_text_node = $$params{'doc'}->createTextNode($$row{'strand'});
        $$params{'strand_element'}->appendChild($strand_text_node);
        $$params{'current_strand'} = $$row{'strand_id'};
        $$params{'in_strand'} = 1;
        &open_standard($row,$params);
    }
    sub close_standard {
        my ($row,$params) = @_;
        $$params{'strand_element'}->appendChild($$params{'standard_element'});
        $$params{'in_standard'} = 0;
    }
    sub open_standard {
        my ($row,$params) = @_;
        $$params{'standard_element'} = $$params{'doc'}->createElement("standard");
        $$params{'standard_element'}->setAttribute('standardid',$$row{'standard_id'});
        my $standard_text_node = $$params{'doc'}->createTextNode($$row{'standard'});
        $$params{'standard_element'}->appendChild($standard_text_node);
        if ($$row{'subpoint_id'}) {
            &open_subpoint($row,$params);
        }
        $$params{'current_standard'} = $$row{'standard_id'};
        $$params{'in_standard'} = 1;
    }
    sub open_subpoint {
        my ($row,$params) = @_;
        my $subpoint_element = $$params{'doc'}->createElement("subpoint");
        $subpoint_element->setAttribute('subpointid',$$row{'subpoint_id'});
        my $subpoint_text_node = $$params{'doc'}->createTextNode($$row{'subpoint'});
        $subpoint_element->appendChild($subpoint_text_node);
        $$params{'standard_element'}->appendChild($subpoint_element);
    }
    sub get_timss_math_framework_xml {
        my ($r) = @_;
        my $qry = "select * from math_framework order by id";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<root>");
        my $current_level = 0;
        my $row_level;
        my $children = 0;
        while (my $row = $sth->fetchrow_hashref()) {
            my @dots = $$row{'code'} =~ /\./g;
            $row_level = (scalar @dots) + 1;
            if ($row_level > $current_level) {
                $r->print('<child id="'.$$row{'code'}.'">'.&Apache::Promse::text_to_html($$row{'description'}));
                $children = 1;
                $current_level ++;  
            } elsif ($row_level eq $current_level) {
                $r->print('</child>');
                $r->print('<child id="'.$$row{'code'}.'">'.&Apache::Promse::text_to_html($$row{'description'}));
            } else {
                $r->print("</child>");
                while ($row_level < $current_level) {
                    $r->print("</child>");
                    $current_level --;
                }
                $r->print('<child id="'.$$row{'code'}.'">'.&Apache::Promse::text_to_html($$row{'description'}));
            }
        }
        $row_level = 0;
        if ($children) {
            #$r->print("</child>");
        }
        while ($row_level < $current_level) {
            $r->print("</child>");
            $current_level --;
        } 
        $r->print("</root>");
    }
    sub link_curriculum_district {
        my ($r) = @_;
        my $curriculum_id = $r->param('curriculumid');
        my $district_id = $r->param('districtid');
        my $return_message;
        my $qry = "SELECT curriculum_id FROM cc_curricula_districts 
                    WHERE curriculum_id = $curriculum_id AND district_id = $district_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $link_flag = $rst->fetchrow_hashref()?1:0;
        if (!$link_flag) {
           $qry = "INSERT INTO cc_curricula_districts (district_id, curriculum_id) VALUES ($district_id, $curriculum_id)";
           $return_message = $env{'dbh'}->do($qry)?"linked":"linkfailure";
        } else {
           $qry = "DELETE FROM cc_curricula_districts WHERE district_id = $district_id AND curriculum_id = $curriculum_id";
           $return_message = $env{'dbh'}->do($qry)?"unlinked":"unlinkfailure";
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<root>'."\n");
        $r->print('<linkmessage>');
        $r->print($return_message);
        $r->print('</linkmessage>'."\n");
        $r->print('</root>'."\n");
        return('ok');   
    }
    sub link_material_district {
        # toggles linkage
        my ($r) = @_;
        my $district_id = $r->param('districtid');
        my $material_id = $r->param('materialid');
        my $qry = "select material_id from cc_district_materials where material_id = $material_id and district_id = $district_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $link_flag = $rst->fetchrow_hashref()?1:0;
        # first check
        my $return_message;
        if (!$link_flag) {
            $qry = "insert into cc_district_materials (district_id, material_id) values ($district_id, $material_id)";
            $return_message = $env{'dbh'}->do($qry)?"linked":"linkfailure";
            $qry = "select grades from cc_materials where id = $material_id";
            $rst = $env{'dbh'}->prepare($qry);
            $rst->execute();
            my $row = $rst->fetchrow_hashref();
            my $current_grades = $$row{'grades'};
            my $source_grade = $r->param('grade');
            if (! ($current_grades =~ m/$source_grade/)) {
                my $new_grades = $current_grades . $source_grade;
                $qry = "update cc_materials set grades = '$new_grades' where id = $material_id";
                $env{'dbh'}->do($qry);
            } else {
            }
        } else {
           $qry = "DELETE FROM cc_district_materials WHERE district_id = $district_id AND material_id = $material_id";
           $return_message = $env{'dbh'}->do($qry)?"unlinked":"unlinkfailure";
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<root>'."\n");
        $r->print('<linkmessage>');
        $r->print($return_message);
        $r->print('</linkmessage>'."\n");
        $r->print('</root>'."\n");
        return('ok');   
    }
    sub return_location_record {
        my ($r) = @_;
        my $location_record = &Apache::Promse::get_location_record($r->param('locationid'));
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<locationRecord>'."\n");
        my @field_names = (keys(%$location_record));
        foreach my $field_name(@field_names) {
            $r->print("<$field_name>\n");
            if($$location_record{$field_name}) {
                $r->print($$location_record{$field_name}."\n");
            }
            $r->print("</$field_name>\n");
        }
        $r->print('</locationRecord>');
        return ('ok');
    }
    sub return_district_record {
        my ($r) = @_;
        my $district_record = &Apache::Promse::get_district_record($r->param('districtid'));
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print('<districtRecord>'."\n");
        my @field_names = (keys(%$district_record));
        foreach my $field_name(@field_names) {
            $r->print("<$field_name>\n");
            if($$district_record{$field_name}) {
                $r->print($$district_record{$field_name}."\n");
            }
            $r->print("</$field_name>\n");
        }
        # record must include altered partners pulldown
        my @partners = &Apache::Promse::get_partners();
        my $partner_id = $$district_record{'partner_id'};
        my $partners_pulldown = &Apache::Promse::build_select('partnerid',\@partners,$partner_id,'');
        $r->print('</districtRecord>');
        return ('ok');
    }
    sub promse_admin_code_html {
        my ($r) = @_;
        my $row = &Apache::Promse::get_user_location();
        my $district_id = $$row{'district_id'};
        my $district_name = $$row{'district_name'};
        my $token = $env{'token'};
        my $path = &get_URL_path($r);
        my $subject = $env{'subject'};
        my $roles = $env{'user_roles'};
        my $output = qq~
    <script language="javascript">AC_FL_RunContent = 0;</script>
    <script src="../flash/AC_RunActiveContent.js" language="javascript"></script>
    </head>
    <body bgcolor="#ffffff">
    <!--url's used in the movie-->
    <!--text used in the movie-->
    <!-- saved from url=(0013)about:internet -->
    <script language="javascript">
        function getToken() {
            return "$token";
        }
        function getDistrict() {
            return "$district_id";
        }
        function getRoles() {
            return "$roles";
        }
        function getDistrictName() {
            return "$district_name";
        }
        function getPath() {
            return "$path";
        }
        function getSubject() {
            return "$subject";
        }
    	if (AC_FL_RunContent == 0) {
    		alert("This page requires AC_RunActiveContent.js.");
    	} else {
    		AC_FL_RunContent(
    			'codebase', 'http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0',
    			'width', '1024',
    			'height', '768',
    			'src', '../flash/lessonLinker',
    			'quality', 'high',
    			'pluginspage', 'http://www.macromedia.com/go/getflashplayer',
    			'align', 'middle',
    			'play', 'true',
    			'loop', 'true',
    			'scale', 'showall',
    			'wmode', 'window',
    			'devicefont', 'false',
    			'id', 'lessonLinker',
    			'bgcolor', '#ffffff',
    			'name', 'lessonLinker',
    			'menu', 'true',
    			'allowFullScreen', 'false',
    			'allowScriptAccess','sameDomain',
    			'movie', '../flash/lessonLinker',
    			'salign', ''
    			); //end AC code
    	}
    </script>
    <noscript>
    	<object classid="clsid:d27cdb6e-ae6d-11cf-96b8-444553540000" codebase="http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0" width="1024" height="768" id="lessonLinker" align="middle">
    	<param name="allowScriptAccess" value="sameDomain" />
    	<param name="allowFullScreen" value="false" />
    	<param name="movie" value="lessonLinker.swf" /><param name="quality" value="high" /><param name="bgcolor" value="#ffffff" />	<embed src="http://vpddev.educ.msu.edu/flash/lessonLinker.swf" quality="high" bgcolor="#ffffff" width="1024" height="768" name="lessonLinker" align="middle" allowScriptAccess="sameDomain" allowFullScreen="false" type="application/x-shockwave-flash" pluginspage="http://www.macromedia.com/go/getflashplayer" />
    	</object>
    </noscript>
    </body>
    </html>
    ~;    
        $r->print($output);
        return('ok'); 
        
    }
    sub return_districts {
        my ($r, $districts) = @_;
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<districts>\n");
        foreach my $district(@$districts) {
            my @key = keys(%$district);
            $r->print("<district>\n");
            $r->print("<name>\n");
            $r->print(&Apache::Promse::text_to_html($key[0]));
            $r->print("</name>\n");
            $r->print("<id>\n");
            $r->print($$district{$key[0]});
            $r->print("</id>\n");
            $r->print("</district>\n");
        }
        $r->print("</districts>\n");
        return ('ok');
    }
    
    sub save_unit_return_units {
        my($r) = @_;
        my $output;
        my %fields = ('grade_id'=>$r->param('grade'),
                    'title'=>&Apache::Promse::fix_quotes($r->param('title')),
                    'description'=>&Apache::Promse::fix_quotes($r->param('description')),
                    'curriculum_id'=>$r->param('curriculumid'));
        &Apache::Promse::save_record('cc_units',\%fields);
        my $units = &Apache::Promse::get_units($r->param('curriculumid'),$r->param('grade'));
        $output .= '<units>';
        foreach my $unit(@$units) {
            $output .= '<unit grade="'.$r->param('grade').'" curriculumid="'.$r->param('curriculumid').'">';
            $output .= '<title>';
            $output .= &Apache::Promse::text_to_html($$unit{'title'});
            $output .= '</title>';
            $output .= '<description>';
            $output .= &Apache::Promse::text_to_html($$unit{'description'});
            $output .= '</description>';
            $output .= '</unit>';
        }
        $output .= '</units>';
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($output);
        return ('ok');
    }
    sub return_agency_types_select {
        my($r) = @_;
        my @agency_types = &Apache::Promse::get_agency_types();
        my $agency_id = $r->param('agencyid');
        my $agencies_pulldown = &Apache::Promse::build_select('agencytypeid',\@agency_types,$agency_id,'');
        print $r->header(-type => 'text/plain');
        $r->print($agencies_pulldown);
        return ('ok');
    }
    sub return_district_schools_by_grade_select {
        my($r) = @_;
        my $district_id = $r->param('districtid');
        my $grade = $r->param('grade');
        my $year = $r->param('year');
        my $school_id = $r->param('schoolid');
        # $year = 2004;
        my @schools = &Apache::Promse::get_district_schools_by_grade($district_id, $grade, $year);
        unshift (@schools,{'District Wide'=>'0'});
        my $schools_pulldown = &Apache::Promse::build_select('schoolid',\@schools,$school_id,'');
        print $r->header(-type => 'text/plain');
        $r->print($schools_pulldown);
    }
    
    sub return_partners_select {
        my($r) = @_;
        my @partners = &Apache::Promse::get_partners();
        my $partner_id = $r->param('partnerid');
        my $partners_pulldown = &Apache::Promse::build_select('partnerid',\@partners,$partner_id,'');
        print $r->header(-type => 'text/plain');
        $r->print($partners_pulldown);
        return ('ok');
    }
    sub return_district_schools_select {
        my($r) = @_;
        my $javascript = $r->param('nojavascript')?"":' onchange="retrieveLocationRecord()" ';
        my $district_id = $r->param('districtid');
        my @district_schools = &Apache::Promse::get_schools($district_id);
        if ($r->param('includenone')) {
            unshift(@district_schools,{'None'=>0});
        }
        my $output = &Apache::Promse::build_select('locationid',\@district_schools,'',$javascript);
        print $r->header(-type => 'text/plain');
        $r->print($output);
        return ('ok');
    }
    sub get_graphic_list {
        my($r) = @_;
        my $output = qq ~
            <files>
                <file>
                    Some file name
                </file>
            </files>
        ~;
        print $r->header(-type => 'text/xml');
        $r->print($output);
        return ('ok');
    }
    sub get_notebook_page {
        my($r) = @_;
        my $page_num = $r->param('pagenum');
        my $resource_id = $r->param('resourceid');
        my $user_id = $Apache::Promse::env{'user_id'};
        my $output;
        my $dbh = $Apache::Promse::env{'dbh'};
        my $qry = "select count(*) as numpages from notebook where user_id = $user_id and resource_id = $resource_id";
        my $sth = $dbh->prepare($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        my $num_pages = $$row{'numpages'};
        if ($num_pages == 0) {
            # no page found, so create first blank page
            $qry = "insert into notebook (user_id, page_num, resource_id) values ($user_id, 1, $resource_id)";
            $dbh->do($qry);
            $page_num = 1;
            $num_pages = 1;
        }
        $qry = "select content from notebook where user_id = $user_id and page_num = $page_num and resource_id = $resource_id";
        $sth = $dbh->prepare($qry);
        $sth->execute();
        $output = "<notebook numpages=\"$num_pages\">\n";
        $output .= "<page pagenumber=\"$page_num\">\n";
        $output .= "<text>\n";
        if ($row = $sth->fetchrow_hashref) {
            my $content = $$row{'content'};
            # $content =~ s/<//g;
            # $content =~ s/>//g;
            $output .= $content;
        } else {
        }
        $output .= "</text>\n";
        $output .= "</page>\n";
        $output .= "</notebook>\n";
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($output);
        return ('ok');
    }
    sub add_notebook_page {
        my($r) = @_;
        my $resource_id = $r->param('resourceid');
        my $dbh = $Apache::Promse::env{'dbh'};
        my $output;
        my $user_id = $Apache::Promse::env{'user_id'};
        my $qry = "select count(*) as numpages from notebook where user_id = $user_id and resource_id = $resource_id";
        my $sth = $dbh->prepare($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        my $num_pages = $$row{'numpages'};
        $num_pages ++;
        $qry = "insert into notebook (user_id, page_num, resource_id) values ($user_id, $num_pages, $resource_id)";
        $dbh->do($qry);
        $output = "<notebook numpages=\"$num_pages\">\n";
        $output .= "<page pagenumber=\"$num_pages\">\n";
        $output .= "<text>\n";
        $output .= "</text>\n";
        $output .= "</page>\n";
        $output .= "</notebook>\n";
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($output);
        return ('ok');
    }
    sub save_notebook {
        my($r) = @_;
        my $resource_id = $r->param('resourceid');
        my $page_num = $r->param('pagenum');
        my $user_id = $Apache::Promse::env{'user_id'};
        my $notes = &Apache::Promse::fix_quotes($r->param('notes'));
        #$notes =~ s/<//g;
        #$notes =~ s/>//g;
        my $dbh = $Apache::Promse::env{'dbh'};
        # need to figure out if page is new or update of existing page
        my $qry = "select id from notebook where page_num = $page_num and user_id = $user_id and resource_id = $resource_id";
        my $sth = $dbh->prepare($qry);
        my $msg;
        $sth->execute();
        if (my $row = $sth->fetchrow_hashref) {
            # we found an existing page, so update
            my $id = $$row{'id'};
            $qry = "update notebook set content = $notes where id = $id";
            #&Apache::Promse::logthis($qry);
            $dbh->do($qry);
            $msg = "ok";
        } else {
            # no record found, so create a new one
             my %fields = ('page_num' => $page_num,
                      'resource_id' => $resource_id,
                      'user_id' => $user_id,
                      'content' => $notes);
            &Apache::Promse::save_record('notebook',\%fields);
            $msg = "ok";
        }
        # need to return confirmation that notebook was saved
        my $output = "<notebook page=\"$page_num\">\n";
        $output .= "<status>\n";
        $output .= "$msg\n";
        $output .= "</status>\n";
        $output .= "</notebook>";
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($output);
        return ('ok');
    }
    sub pf_tag_theme {
        my ($r) = @_;
        my $theme_id = $r->param('themeid');
        my $node_id = $r->param('nodeid');
        my $reason = $r->param('reason')?$r->param('explanation'):'';
        my $qry = "SELECT * from cc_pf_theme_tags WHERE theme_id = $theme_id 
                            AND pf_end_id = $node_id 
                         ";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $return_message;
        if (! $rst->fetchrow_hashref()) {
            # no existing tag on this 
            my %fields = ('theme_id'=>$theme_id,
                          'pf_end_id'=>$node_id);
            &Apache::Promse::save_record('cc_pf_theme_tags',\%fields);
            %fields = ('theme_id'=>$theme_id,
                          'change_date'=>'NOW()',
                          'pf_end_id'=>$node_id,
                          'action'=>"'add'",
                          'reason'=>&Apache::Promse::fix_quotes($reason));
            &Apache::Promse::save_record('cc_pf_theme_tag_history',\%fields);
            $return_message = 'added';
        } else {
            $qry = "DELETE FROM cc_pf_theme_tags 
                        WHERE theme_id = $theme_id AND pf_end_id = $node_id";
            $env{'dbh'}->do($qry);
            my %fields = ('theme_id'=>$theme_id,
                          'change_date'=>' NOW() ',
                          'pf_end_id'=>$node_id,
                          'action'=>"'remove'",
                          'reason'=>&Apache::Promse::fix_quotes($reason));
            &Apache::Promse::save_record('cc_pf_theme_tag_history',\%fields);
            $return_message = 'removed';
        }
        &xml_header($r);        
        $r->print("<response>$return_message</response>");    
    }
    sub return_nodes {
        my ($r) = @_;
        my $district = $r->param('district');
        my $grade = $r->param('grade');
        my $year = $r->param('year');
        my $node_scores = &get_all_scores($district,$year);
        my $doc = XML::DOM::Document->new;
        my $gfw_root = $doc->createElement('gfw');
        &xml_header($r);
        foreach my $coord (@$node_scores) {
            my $cell_element = $doc->createElement('cell');
            my ($x,$y) = split(/_/,$$coord{'coord'});
            my $score = $$coord{'score'};
            $grade = $$coord{'grade'};
            $cell_element->setAttribute('x',$x);
            $cell_element->setAttribute('y',$y);
            $cell_element->setAttribute('grade',$grade);
            $cell_element->setAttribute('score',$score); 
            $gfw_root->appendChild($cell_element);
        }
        $r->print($gfw_root->toString);
        return (1);
    }
    
    sub return_district_intended {
        # return XML with grade and coord
        my ($r) = @_;
        my $district = $r->param('district');
        my $year = $r->param('year');
        my $grade = $r->param('grade');
        my $qry = "select grade, coord from dist_intended_curriculum, math_framework
                    where district_id = $district and
                    grade = $grade and
                    year = $year and (code = framework_code or code like concat(framework_code, '.%')) and
                    coord <> 0";
        my $sth = $Apache::Promse::env{'dbh'}->prepare($qry);
        $sth->execute();
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<districtintended>\n");
        while (my $row = $sth->fetchrow_hashref) {
            my ($x,$y) = split(/_/,$$row{'coord'});
            $grade = $$row{'grade'};
            print '<cell  x="'.$x.'" y="'.$y.'" grade="'.$grade.'" />'."\n";
        }
        $r->print("</districtintended>\n");
        return ('ok');
    }
    sub move_sequence {
        my ($r) = @_;
        my $direction = $r->param('direction');
        my $sequence = $r->param('sequence');
        my $unit_id = $r->param('unitid');
        my $grade_id = ($r->param('gradeid')eq'K')?0:$r->param('gradeid');
        $grade_id = $grade_id eq 'HS'?9:$grade_id;
        my $curriculum_id = $r->param('curriculumid');
        my $unit_or_lesson = $r->param('unitorlesson');
        my $unit_or_lesson_id = $r->param('unitorlessonid');
        my $qry;
        my $query_sort_direction;
        my $query_comparative;
        my $table_name;
        if ($direction eq "up") { # "up" is a lower number
            $query_comparative = " <= ";
            $query_sort_direction = " DESC ";
        } else {
            $query_comparative = " >= ";
            $query_sort_direction = " ASC ";
        }
        if ($unit_or_lesson eq "unit") {
            $table_name = "cc_units";
            $qry = "SELECT id, sequence FROM cc_units 
                    WHERE curriculum_id = $curriculum_id AND
                            grade_id = $grade_id AND
                            sequence $query_comparative $sequence
                    ORDER BY sequence $query_sort_direction
                    LIMIT 2"
        } else {
            $table_name = "cc_themes";
            $qry = "SELECT id, sequence FROM cc_themes 
                    WHERE unit_id = $unit_id AND
                            sequence $query_comparative $sequence
                    ORDER BY sequence $query_sort_direction
                    LIMIT 2"
        }
        print STDERR "\n\n $qry \n\n";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $row = $rst->fetchrow_hashref();
        my $id_1 = $$row{'id'};
        my $seq_1 = $$row{'sequence'};
        $row = $rst->fetchrow_hashref();
        my $id_2 = $$row{'id'};
        my $seq_2 = $$row{'sequence'};
        $qry = "UPDATE $table_name SET sequence = $seq_2 WHERE id = $id_1";
        $env{'dbh'}->do($qry);
        $qry = "UPDATE $table_name SET sequence = $seq_1 WHERE id = $id_2";
        $env{'dbh'}->do($qry);
        my $doc = XML::DOM::Document->new;
        my $responseElement = $doc->createElement('response');
        $responseElement->setAttribute('sourceid',$id_1);
        $responseElement->setAttribute('destinationid',$id_2);
        $responseElement->setAttribute('sourcesequence',$seq_1);
        $responseElement->setAttribute('destinationsequence',$seq_2);
        &xml_header($r);
        $r->print($responseElement->toString());
    }
    sub get_locations {
        my ($r) = @_;
        my $district_id = $r->param('districtid');
        my $qry = "SELECT location_id, Grade_range, NCES_ID, State_school_id, State_agency_id,
                          district_id, school, address, city, zip, principal, elem, middle,
                          high, phone
                   FROM locations 
                   WHERE district_id = $district_id
                   ORDER by school";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $doc = XML::DOM::Document->new;
        my $locations_root = $doc->createElement('locations');
        while (my $row = $sth->fetchrow_hashref()) {
            my $location_element = $doc->createElement('location');
            $location_element->setAttribute('id',$$row{'location_id'});
            $location_element->setAttribute('graderange',$$row{'Grade_range'});
            $location_element->setAttribute('ncesid',$$row{'location_id'});
            $location_element->setAttribute('stateschoolid',$$row{'State_school_id'});
            $location_element->setAttribute('stateagencyid',$$row{'State_agency_id'});
            $location_element->setAttribute('districtid',$$row{'district_id'});
            $location_element->setAttribute('school',$$row{'school'});
            $location_element->setAttribute('address',$$row{'address'});
            $location_element->setAttribute('city',$$row{'city'});
            $location_element->setAttribute('zip',$$row{'zip'});
            $location_element->setAttribute('city',$$row{'city'});
            $location_element->setAttribute('principal',$$row{'principal'});
            $location_element->setAttribute('elem',$$row{'elem'});
            $location_element->setAttribute('middle',$$row{'middle'});
            $location_element->setAttribute('high',$$row{'high'});
            $location_element->setAttribute('phone',$$row{'phone'});
            $locations_root->appendChild($location_element);
        }
        &xml_header($r);
        $r->print($locations_root->toString);
    }
    sub save_lesson_history {
        my ($r) = @_;
        my %fields;
        my $theme_id = $r->param('themeid');
        my $qry = "SELECT unit_id, sequence, supporting_activity, tagged, periods, period_duration, 
                        title, eliminated, description
                        FROM cc_themes WHERE id = $theme_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my $lesson = $rst->fetchrow_hashref();
        my $tagged = $$lesson{'tagged'}?1:0;
        my $periods = $$lesson{'periods'}?$$lesson{'periods'}:0;
        my $eliminated = $$lesson{'eliminated'}?$$lesson{'eliminated'}:0;
        my $period_duration = $$lesson{'periods'}?$$lesson{'period_duration'}:0;
        # need to insert lesson in sequence if we are changing the unit_id
        # might arrive without a sequence, so put at end of unit
        %fields = ('unit_id'=>$$lesson{'unit_id'},
                    'change_date' => ' NOW() ',
                    'lesson_id'=>$theme_id,
                    'sequence'=>$$lesson{'sequence'},
                    'supporting_activity'=>$$lesson{'supporting_activity'},
                    'tagged'=>$tagged,
                    'user_id'=>$env{'user_id'},
                    'eliminated'=>$eliminated,
                    'periods'=>$periods,
                    'period_duration'=>$period_duration,
                    'title'=>&Apache::Promse::fix_quotes($$lesson{'title'}),
                    'comment'=>&Apache::Promse::fix_quotes($r->param('comments')),
                    'description'=>&Apache::Promse::fix_quotes($$lesson{'description'}));
        &Apache::Promse::save_record('cc_lesson_history',\%fields);
    }
    sub assign_template {
        my ($r) = @_;
        my $template_id = $r->param('templateid');
        my $district_id = $r->param('districtid');
        my $qry;
        my $sth;
        $qry = "SELECT subject, title, description FROM cc_curricula WHERE id = $template_id";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $template_row = $sth->fetchrow_hashref();
        my $template_subject =  $$template_row{'subject'};
        my $template_title =  $$template_row{'title'};
        my $template_description =  $$template_row{'description'};
        # first insert new Curriculum
        my %fields = ('subject'=>&Apache::Promse::fix_quotes($template_subject),
                        'is_template'=>0,
                        'from_template'=>$template_id,
                        'title'=>&Apache::Promse::fix_quotes($template_title),
                        'description'=>&Apache::Promse::fix_quotes($template_description));
        my $curriculum_id = &Apache::Promse::save_record('cc_curricula',\%fields,1);
        # now assign in cc_curricula_districts
        %fields = ('district_id'=>$district_id,
                    'curriculum_id'=>$curriculum_id);
        &Apache::Promse::save_record('cc_curricula_districts',\%fields);
        $qry = "SELECT cc_units.curriculum_id, cc_units.id as unit_id, cc_units.title as unit_title, cc_units.grade_id, 
                cc_units.description as unit_description,
                cc_units.sequence as unit_sequence, 
                cc_units.periods as unit_periods, cc_units.period_duration as unit_period_duration,
            	cc_themes.id as theme_id, cc_themes.description as theme_description, cc_themes.supporting_activity, 
            	cc_themes.period_duration as theme_period_duration, cc_themes.title as theme_title,
            	cc_themes.sequence as theme_sequence,
            	cc_themes.tagged, cc_pf_theme_tags.notes, 
            	cc_pf_theme_tags.pf_end_id,
            	cc_pf_theme_tags.standard_flag, cc_pf_theme_tags.strength, cc_material_chunks.description as material_chunk_description,
            	cc_material_chunks.id as material_chunk_id,
            	cc_material_chunks.material_id, cc_material_chunks.title as material_chunk_title, cc_material_chunks.unused_portion
            FROM cc_units
            LEFT JOIN cc_themes ON cc_units.id = cc_themes.unit_id
            LEFT JOIN cc_pf_theme_tags ON cc_pf_theme_tags.theme_id = cc_themes.id
            LEFT JOIN cc_material_chunks ON cc_material_chunks.theme_id = cc_themes.id
			LEFT JOIN cc_lesson_history ON cc_lesson_history.lesson_id = cc_themes.id AND cc_lesson_history.comment > ''
            WHERE cc_units.curriculum_id = $template_id 
            ORDER BY grade_id, unit_sequence, theme_sequence, pf_end_id, material_chunk_id ";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $current_unit = -1;
        my $current_theme = -1;
        my $current_tag = -1;
        my $theme_id;
        my $unit_id;
        my %materials_hash;
        while (my $row = $sth->fetchrow_hashref) {
            if ($current_unit ne $$row{'unit_id'}) {
                # new unit, so insert the unit
				my $unit_period_duration = $$row{'unit_period_duration'}?$$row{'unit_period_duration'}:0;
                %fields = ('curriculum_id'=>$curriculum_id,
                            'grade_id'=>$$row{'grade_id'},
                            'sequence'=>$$row{'unit_sequence'},
                            'periods'=>$$row{'unit_periods'},
                            'period_duration'=>$unit_period_duration,
                            'title'=>&Apache::Promse::fix_quotes($$row{'unit_title'}),
                            'description'=>&Apache::Promse::fix_quotes($$row{'unit_description'}));
                $unit_id = &Apache::Promse::save_record('cc_units',\%fields,1);
                $current_unit = $$row{'unit_id'};
                if ($$row{'theme_id'}) {
                    $current_theme = $$row{'theme_id'};
                    $theme_id = &clone_theme($row, $unit_id);
                    if ($$row{'pf_end_id'}) {
                        &clone_theme_tag($row, $theme_id);
                    }
                    if ($$row{'material_chunk_id'}) {
                        &clone_material_chunk($row, $theme_id);
                    }
                }
            } else { #continuing unit
                if ($current_theme ne $$row{'theme_id'}) {
                    $current_theme = $$row{'theme_id'};
                    $theme_id = &clone_theme($row, $unit_id);
                } else { #working on same theme
                    if ($$row{'pf_end_id'}) {
                        &clone_theme_tag($row, $theme_id);
                    }
                    if ($$row{'material_chunk_id'}) {
                        &clone_material_chunk($row, $theme_id);
                    }
                }
            }
        }
        &assign_district_material($district_id, $template_id);
        &xml_header($r);
        $r->print('<response>ok</response>');
    }
    sub import_unit {
        my ($r) = @_;
        my $qry;
        my $sth;
        my $rst;
        my $unit_id = $r->param('unitid');
        my $curriculum_id = $r->param('curriculumid');
        my $grade_level = $r->param('gradelevel');
        my $return_message;
        my $doc = XML::DOM::Document->new;
        my $unit_element = $doc->createElement('unit');
        my $did_one = 0;
        my $peer_id = $r->param('peerid');
        $grade_level = $grade_level eq 'K'?0:$grade_level;
        $grade_level = $grade_level eq 'HS'?9:$grade_level;
        # Following checks if the unit has already been imported
        $qry = "SELECT cc_template_imports.template_unit_id 
                    FROM cc_template_imports, cc_curricula, cc_units
                    WHERE cc_curricula.id = $curriculum_id AND
                            cc_curricula.id = cc_units.curriculum_id AND
                            cc_template_imports.template_unit_id = $unit_id AND
                            cc_units.grade_id = $grade_level AND
                            cc_units.id = cc_template_imports.curriculum_unit_id";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        if ($sth->fetchrow_hashref()) {
            $return_message = 'Already Imported';
        } else {
            # retrieve the unit that is going to be imported
            $qry = "SELECT cc_units.id, cc_units.curriculum_id, cc_units.grade_id, cc_units.sequence,
                        cc_units.periods, cc_units.title, cc_units.description
                        FROM cc_units 
                        WHERE cc_units.id = $unit_id";
            $sth = $env{'dbh'}->prepare($qry);
            $sth->execute();
            my $template_unit = $sth->fetchrow_hashref();
            # will append unit to existing units in the grade_level
            # so find what the next in sequence is
            $qry = "SELECT max(cc_units.sequence) as max_seq from cc_units WHERE
                     cc_units.curriculum_id = $curriculum_id AND
                     cc_units.grade_id = $grade_level";
            $sth = $env{'dbh'}->prepare($qry);
            $sth->execute();
            my $max_row = $sth->fetchrow_hashref();
            my $new_sequence = $max_row?$$max_row{'max_seq'} + 1:1;
            # build the fields for the new unit in the destination curriculum
            my %fields = ('curriculum_id'=>$curriculum_id,
                          'grade_id'=>$grade_level,
                          'sequence'=>$new_sequence,
                          'periods'=>$$template_unit{'periods'},
                          'title'=>&Apache::Promse::fix_quotes($$template_unit{'title'}),
                          'description'=>&Apache::Promse::fix_quotes($$template_unit{'description'}));
            # insert the record
            my $new_unit_id = &Apache::Promse::save_record('cc_units',\%fields,1);
            $did_one = 1;
            $fields{'unit_id'} = $new_unit_id;
            $fields{'unit_sequence'} = $$template_unit{'sequence'};
            $fields{'unit_title'} = $$template_unit{'title'};
            $fields{'unit_description'} = $$template_unit{'description'};
            $unit_element = &build_unit_element(\%fields,$doc,$peer_id);
            # get the lessons (themes) contained in the unit
            $qry = "SELECT cc_themes.id, cc_themes.unit_id, cc_themes.sequence, cc_themes.supporting_activity,
                            cc_themes.tagged, cc_themes.periods, cc_themes.period_duration, cc_themes.eliminated,
                            cc_themes.title, cc_themes.lesson_notes, cc_themes.description,
                            cc_material_chunks.material_id, cc_material_chunks.title as chunk_title, 
                            cc_material_chunks.description as chunk_description,
                            cc_material_chunks.unused_portion, cc_lesson_history.comment
                    FROM cc_themes
                    LEFT JOIN cc_material_chunks on cc_material_chunks.theme_id = cc_themes.id
					LEFT JOIN cc_lesson_history on cc_lesson_history.lesson_id = cc_themes.id AND cc_lesson_history.comment IS NOT NULL
                    WHERE cc_themes.unit_id = $unit_id";
            my $sth_themes = $env{'dbh'}->prepare($qry);
            $sth_themes->execute();
            my $current_theme = 0;
            my $new_lesson_id;
            my $did_lesson = 0;
            my $lesson_element;
            my $first_one = 1;
            while (my $template_theme = $sth_themes->fetchrow_hashref()) {
                my $tagged = $$template_theme{'tagged'}?$$template_theme{'tagged'}:0;
                if ($current_theme ne $$template_theme{'id'}) {
                    $did_lesson = 1;
                    if (! $first_one) {
                        # if this is the first row, then we haven't yet made the
                        # lesson element
                        $unit_element->appendChild($lesson_element);
                    }
                    $first_one = 0;
                    $current_theme = $$template_theme{'id'};
                    %fields = ('unit_id'=>$new_unit_id,
                               'sequence'=>$$template_theme{'sequence'},
                               'supporting_activity'=>$$template_theme{'supporting_activity'},
                               'tagged'=>$tagged,
                               'periods'=>$$template_theme{'periods'},
                               'period_duration'=>$$template_theme{'period_duration'},
                               'title'=>&Apache::Promse::fix_quotes($$template_theme{'title'}),
                               'description'=>&Apache::Promse::fix_quotes($$template_theme{'description'}));
                    $new_lesson_id = &Apache::Promse::save_record('cc_themes',\%fields, 1);
                    $fields{'lesson_id'} = $new_lesson_id;
                    $fields{'unit_grade'} = $grade_level;
                    $fields{'theme_title'} = $$template_theme{'title'};
                    $fields{'theme_description'} = $$template_theme{'description'};
                    $lesson_element = &build_lesson_element(\%fields, $doc);
					if ($$template_theme{'comment'}) {
						%fields = ('lesson_id'=>$new_lesson_id,
								'unit_id'=>$new_unit_id,
								'sequence'=>$$template_theme{'sequence'},
								'supporting_activity'=>$$template_theme{'supporting_activity'},
								'tagged'=>$tagged,
								'periods'=>$$template_theme{'periods'},
								'period_duration'=>$$template_theme{'period_duration'},
								'title'=>&Apache::Promse::fix_quotes($$template_theme{'title'}),
								'description'=>&Apache::Promse::fix_quotes($$template_theme{'description'}),
								'comment'=>$$template_theme{'comment'});
						&Apache::Promse::save_record('cc_lesson_history',\%fields, 0);
					}
                }
                if ($$template_theme{'material_id'}) {
                    my $material_id = $$template_theme{'material_id'};
                    my $district_id = $r->param('districtid');
                    %fields = ('theme_id'=>$new_lesson_id,
                                'material_id'=>$$template_theme{'material_id'},
                                'title'=>&Apache::Promse::fix_quotes($$template_theme{'chunk_title'}),
                                'description'=>&Apache::Promse::fix_quotes($$template_theme{'chunk_description'}),
                                'unused_portion'=>&Apache::Promse::fix_quotes($$template_theme{'unused_portion'}));
                    my $new_chunk_id = &Apache::Promse::save_record('cc_material_chunks',\%fields, 1);
                    # Now need to be sure material is assigned to district
                    $qry = "SELECT count(*) as count FROM cc_district_materials WHERE 
                            material_id = $material_id and district_id = $district_id";
                    $sth = $env{'dbh'}->prepare($qry);
                    $sth->execute();
                    my $count_row = $sth->fetchrow_hashref();
                    if (! $$count_row{'count'}) {
                        %fields = ('material_id'=>$material_id,
                                    'district_id'=>$district_id);
                        &Apache::Promse::save_record('cc_district_materials',\%fields);
                    }
                    my $lesson_material_element = $doc->createElement('chunk');
                    $lesson_material_element->setAttribute('id',$new_chunk_id);
                    $lesson_material_element->setAttribute('materialid',$$template_theme{'material_id'});
                    my $title_element = $doc->createElement('title');
                    my $title_text = $$template_theme{'chunk_title'}?$$template_theme{'chunk_title'}:'No title';
                    my $title_text_node = $doc->createTextNode($title_text);
                    $title_element->appendChild($title_text_node);
                    $lesson_material_element->appendChild($title_element);
                    my $description_element = $doc->createElement('description');
                    my $description_text_node = $doc->createTextNode($$template_theme{'chunk_description'});
                    $description_element->appendChild($description_text_node);
                    $lesson_material_element->appendChild($description_element);
                    my $unused_element = $doc->createElement('unusedportion');
                    my $unused_text_node = $doc->createTextNode($$template_theme{'unused_portion'});
                    $unused_element->appendChild($unused_text_node);
                    $lesson_material_element->appendChild($unused_element);
                    $lesson_element->appendChild($lesson_material_element);
                }
            }
            if ($did_one) {
                $unit_element->appendChild($lesson_element);
            }
            %fields = ('template_unit_id'=>$unit_id,
                        'curriculum_unit_id'=>$new_unit_id);
            &Apache::Promse::save_record('cc_template_imports',\%fields);
            $return_message = 'Unit Imported';
        }
        &xml_header($r);
        if ($return_message ne 'Already Imported') {
            $r->print($unit_element->toString);
        } else {
            $r->print("<response>Already Imported</response>");
        }
    }
    sub assign_district_material {
        my ($district_id, $template_id) = @_;
        my $qry = "SELECT material_id, district_id FROM cc_district_materials WHERE district_id = $template_id";
        # &Apache::Promse::logthis("\n $qry \n");
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        my @template_materials;
        while (my $template_material = $rst->fetchrow_hashref()) {
            push(@template_materials,{%$template_material});
        }
        foreach my $district_material(@template_materials) {
            my $material_id = $$district_material{'material_id'};
            $qry = "SELECT district_id, material_id FROM cc_district_materials WHERE
                    district_id = $district_id AND material_id = $material_id";
            $rst = $env{'dbh'}->prepare($qry);
            $rst->execute();
            if (!(my $row = $rst->fetchrow_hashref()) ) {
                my %fields = ('district_id'=>$district_id,
                            'material_id'=>$material_id);
                &Apache::Promse::save_record('cc_district_materials',\%fields);
            }
        }
    }
    sub clone_theme {
        my($row,$unit_id) = @_;
        my $tagged = $$row{'tagged'}?$$row{'tagged'}:0;
        my $periods = $$row{'theme_periods'}?$$row{'theme_periods'}:0;
        my $period_duration = $$row{'theme_period_duration'}?$$row{'theme_period_duration'}:0;
        my %fields = ('unit_id'=>$unit_id,
                    'sequence'=>$$row{'theme_sequence'},
                    'title'=>&Apache::Promse::fix_quotes($$row{'theme_title'}),
                    'description'=>&Apache::Promse::fix_quotes($$row{'theme_description'}),
                    'supporting_activity'=>$$row{'supporting_activity'},
                    'tagged'=>$tagged,
                    'periods'=>$periods,
                    'period_duration'=>$period_duration,
                    'eliminated'=>0);
        my $new_lesson_id = &Apache::Promse::save_record('cc_themes',\%fields,1);
		if ($$row{'comment'}) {
			my $qry = "SELECT change_date, unit_id, sequence, supporting_activity, user_id, tagged, eliminated, 
							periods, period_duration, title, description, comment
						FROM cc_lesson_history
						WHERE cc_lesson_history.lesson_id = $$row{'theme_id'} AND
							comment NOT NULL
						ORDER BY change_date DESC
						LIMIT 1";
			my $rst = $env{'dbh'}->prepare($qry);
			$rst->execute();
			if (my $history_row = $rst->fetchrow_hashref()) {
				# here when the lesson was moved
				%fields = ('lesson_id'=>$new_lesson_id,
					'unit_id'=>$unit_id,
					'sequence'=>$$history_row{'sequence'},
					'supporting_activity'=>$$history_row{'supporting_activity'},
					'tagged'=>$$history_row{'tagged'},
					'periods'=>$$history_row{'periods'},
					'period_duration'=>$$history_row{'period_duration'},
					'title'=>&Apache::Promse::fix_quotes($$history_row{'title'}),
					'description'=>&Apache::Promse::fix_quotes($$history_row{'description'}),
					'comment'=>$$history_row{'comment'});
				&Apache::Promse::save_record('cc_lesson_history',\%fields);
			}
		}
		return($new_lesson_id);
    }
    sub clone_theme_tag {
        my ($row, $theme_id) = @_;
        my $strength = $$row{'strength'}?$$row{'strength'}:0;
        my %fields = ('theme_id'=>$theme_id,
                    'pf_end_id'=>$$row{'pf_end_id'},
                    'standard_flag'=>$$row{'standard_flag'},
                    'strength'=>$strength,
                    'notes'=>&Apache::Promse::fix_quotes($$row{'notes'}));
        &Apache::Promse::save_record('cc_pf_theme_tags',\%fields);
    }
    sub clone_material_chunk {
        my ($row, $theme_id) = @_;
        my %fields = ('theme_id'=>$theme_id,
                    'material_id'=>$$row{'material_id'},
                    'unused_portion'=>&Apache::Promse::fix_quotes($$row{'unused_portion'}),
                    'title'=>&Apache::Promse::fix_quotes($$row{'material_chunk_title'}),
                    'description'=>&Apache::Promse::fix_quotes($$row{'material_chunk_description'}));
        &Apache::Promse::save_record('cc_material_chunks',\%fields);
    }
    sub get_districts {
        # gets either all districts or gets a partner's districts and their assigned curricula
        my ($r) = @_;
        my $partner_id = $r->param('partnerid');
        my $curriculum_id = $r->param('curriculumid')?$r->param('curriculumid'):'0';
        my $qry;
        if ($r->param('action') eq 'getalldistricts') {
            # districts for assigning templates
            $qry = "SELECT districts.district_id, partner_id, district_name, county, county_num,
                              agency_type, students, free_lunch, reduced_lunch, district_alt_name,
                              templates.id as curriculum_id
                       FROM districts
                       LEFT JOIN (cc_curricula_districts, cc_curricula, cc_curricula AS templates  ) ON cc_curricula_districts.district_id = districts.district_id AND
                                	templates.id = cc_curricula.from_template AND cc_curricula_districts.curriculum_id = cc_curricula.id AND
                                	templates.id = $curriculum_id
                       ORDER by district_name";
        } else {
            $qry = "SELECT districts.district_id, partner_id, district_name, county, county_num,
                              agency_type, students, free_lunch, reduced_lunch, district_alt_name,
                              cc_curricula_districts.curriculum_id
                       FROM districts
                       LEFT JOIN cc_curricula_districts ON cc_curricula_districts.district_id = districts.district_id
                         AND $curriculum_id = cc_curricula_districts.curriculum_id 
                       WHERE partner_id = $partner_id 
                       ORDER by district_name";
        }
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $doc = XML::DOM::Document->new;
        my $districts_root = $doc->createElement('districts');
        while (my $row = $sth->fetchrow_hashref()) {
            $curriculum_id = $$row{'curriculum_id'}?$$row{'curriculum_id'}:0;
            my $district_element = $doc->createElement('district');
            $district_element->setAttribute('id',$$row{'district_id'});
            $district_element->setAttribute('county',$$row{'county'});
            $district_element->setAttribute('curriculumid',$curriculum_id);
            $district_element->setAttribute('county_num',$$row{'county_num'});
            $district_element->setAttribute('agency_type',$$row{'agency_type'});
            $district_element->setAttribute('students',$$row{'students'});
            $district_element->setAttribute('name',$$row{'district_name'});
            $district_element->setAttribute('free_lunch',$$row{'free_lunch'});
            $district_element->setAttribute('reduced_lunch',$$row{'reduced_lunch'});
            $district_element->setAttribute('district_alt_name',$$row{'district_alt_name'});
            $districts_root->appendChild($district_element);
            if ($$row{'curriculum_id'}) {
                my $curriculum_element = $doc->createElement('curriculum');
                $curriculum_element->setAttribute('id',$$row{'curriculum_id'});
                $district_element->appendChild($curriculum_element);
            }
        }
        &xml_header($r);
        $r->print($districts_root->toString);
    }
    sub get_partners {
        my ($r) = @_;
        my $qry = "SELECT partner_id, partner_name, state FROM partners order by partner_name";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $doc = XML::DOM::Document->new;
        my $partners_root = $doc->createElement('partners');
        while (my $row = $sth->fetchrow_hashref()) {
            my $partner_element = $doc->createElement('partner');
            $partner_element->setAttribute('id', $$row{'partner_id'});
            my $partner_name_element = $doc->createElement('name');
            my $partner_name_text = $doc->createTextNode($$row{'partner_name'});
            $partner_name_element->appendChild($partner_name_text);
            $partner_element->appendChild($partner_name_element);
            my $partner_state_element = $doc->createElement('state');
            my $partner_state_text = $doc->createTextNode($$row{'state'});
            $partner_state_element->appendChild($partner_state_text);
            $partner_element->appendChild($partner_state_element);
            $partners_root->appendChild($partner_element);
        }
        &xml_header($r);
        $r->print($partners_root->toString);
    }
    sub get_units {
        my ($curriculum_id, $grade) = @_;
        my @units;
        my $qry = "SELECT id, title, periods, period_duration, sequence, description, grade_id 
                    FROM cc_units 
                    WHERE curriculum_id = $curriculum_id and grade_id = $grade
                    ORDER BY sequence";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @units,{%$row};
        }
        return(\@units);
    }
    sub get_coded_themes {
        my ($r) = @_;
        my @themes;
        my $qry = "SELECT cc_themes.id as theme_id, cc_themes.title, cc_themes.description, cc_themes.periods,
                     cc_themes.period_duration, cc_themes.sequence 
                    FROM cc_themes 
    		LEFT JOIN cc_units on cc_themes.unit_id = cc_units.id
    		LEFT JOIN cc_curricula on cc_units.curriculum_id = cc_curricula.id
                    WHERE cc_themes.id IN (SELECT DISTINCT theme_id FROM cc_pf_theme_tags) AND
                    cc_curricula.subject = 'Math'";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @themes,{%$row};
        }
        my $doc = XML::DOM::Document->new;
        my $themes_xml = $doc->createElement("themes");
        foreach my $theme(@themes) {
            my $theme_element = $doc->createElement("theme");
            $theme_element->setAttribute('id', $$theme{'theme_id'});
            my $title_element = $doc->createElement("title");
            my $title_text_node = $doc->createTextNode($$theme{'title'});
            $title_element->appendChild($title_text_node);
            $theme_element->appendChild($title_element);
            my $description_element = $doc->createElement('description');
            my $description_text_node = $doc->createTextNode($$theme{'description'});
            $description_element->appendChild($description_text_node);
            $theme_element->appendChild($description_element);
            $themes_xml->appendChild($theme_element);
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($themes_xml->toString);
    }
    sub get_uncoded_themes {
        my ($r) = @_;
        my $curriculum_id = $r->param('curriculumid');
        my @themes;
        my $qry = "SELECT cc_units.id as unit_id, cc_units.title as unit_title, cc_themes.id as theme_id, cc_themes.title as theme_title,
                    cc_themes.description as theme_description, cc_units.grade_id as grade_id, cc_themes.supporting_activity
                    FROM cc_units, cc_themes WHERE cc_themes.id NOT IN 
                  (select cc_pf_theme_tags.theme_id from cc_pf_theme_tags) AND
    		cc_units.id = cc_themes.unit_id AND
    		cc_units.curriculum_id = $curriculum_id 
    		 ORDER BY cc_units.grade_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @themes,{%$row};
        }
        my $current_grade = -1;
        my $in_grade = 0;
        my $grade_element;
        my $doc = XML::DOM::Document->new;
        my $themes_xml = $doc->createElement("themes");
        foreach my $theme(@themes) {
            if ($current_grade ne $$theme{'grade_id'}) {
                if ($in_grade) {
                    $themes_xml->appendChild($grade_element);
                }
                $grade_element = $doc->createElement("grade");
                $grade_element->setAttribute('gradelevel',$$theme{'grade_id'});
                $in_grade = 1;
            }
            my $theme_element = $doc->createElement("theme");
            $theme_element->setAttribute('id', $$theme{'theme_id'});
            $theme_element->setAttribute('unitid', $$theme{'unit_id'});
            $theme_element->setAttribute('unittitle', $$theme{'unit_title'});
            $theme_element->setAttribute('supportingactivity', $$theme{'supporting_activity'});
            my $title_element = $doc->createElement("title");
            my $title_text_node = $doc->createTextNode($$theme{'theme_title'});
            $title_element->appendChild($title_text_node);
            $theme_element->appendChild($title_element);
            my $description_element = $doc->createElement('description');
            my $description_text_node = $doc->createTextNode($$theme{'theme_description'});
            $description_element->appendChild($description_text_node);
            $theme_element->appendChild($description_element);
            $grade_element->appendChild($theme_element);
            $current_grade = $$theme{'grade_id'};
        }
        if ($in_grade) {
            $themes_xml->appendChild($grade_element);
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($themes_xml->toString);
    }
    sub get_print_science_by_curriculum {
        my ($r) = @_;
        my $file_name = 'temp' . $env{'token'} . 'printcurric' . '.xml';
        my $pid = fork();
        if ($pid) {
            &get_print_science_by_curriculum_thread($r,$file_name);
        } else {
            my ($dev, $ino, $mode, $nlink) = stat($file_name);
            if (stat ("/var/www/html/images/userpics/". $file_name)) {
                unlink("/var/www/html/images/userpics/". $file_name);
            }
            &xml_header($r);
            $r->print('<response filename="'. $file_name . '">working</response>');
        }
    }
    sub get_print_science_by_curriculum_thread {
        my ($r, $file_name) = @_;
        # &Apache::Promse::logthis(" ******  file name is $file_name  ********");
        my $curriculum_id = $r->param('curriculumid');
        my $qry = "SELECT cc_curricula.title as curriculum_title, cc_units.title as unit_title, cc_units.grade_id as grade, 
                    cc_themes.title AS lesson_title, cc_themes.id as lesson_id, cc_themes.description as lesson_description,
                    cc_units.description AS unit_description, cc_pf_theme_tags.notes AS tag_description, 
                    cc_pf_theme_tags.pf_end_id AS principle_id, 
                    cc_units.id as unit_id, cc_principles.principle
                FROM (cc_curricula, cc_units, cc_themes)
                LEFT JOIN
    	            (cc_principles, cc_pf_theme_tags) ON (cc_pf_theme_tags.theme_id = cc_themes.id AND
                        cc_pf_theme_tags.pf_end_id = cc_principles.id)
                WHERE 
    	        cc_curricula.id = cc_units.curriculum_id AND
    	        cc_themes.unit_id = cc_units.id AND
    	        cc_curricula.id = $curriculum_id 
                ORDER BY cc_units.grade_id, cc_units.sequence, cc_themes.sequence";
        my $dbh = Apache::Promse::db_connect();
        my $rst = $dbh->prepare($qry);
        $rst->execute();
        my $current_grade = -1;
        my $current_principle = -1;
        my $current_lesson = -1;
        my $current_unit = -1;
        my $unit_text_node;
        my $lesson_text_node;
        my $principle_element;
        my $principle_text_node;
        my $grade_element;
        my $lesson_element;
        my $unit_element;
        my $doc = XML::DOM::Document->new;
        my $curriculum_root = $doc->createElement('curriculum');
        my $first_row = 1;
        while (my $row = $rst->fetchrow_hashref()) {
            if ($first_row) {
                $current_grade = $$row{'grade'};
                $current_unit = $$row{'unit_id'};
                $current_lesson = $$row{'lesson_id'};
                $curriculum_root->setAttribute('id', $curriculum_id);
                $curriculum_root->setAttribute('title', $$row{'curriculum_title'});
                $first_row = 0;
                $grade_element = $doc->createElement('grade');
                $grade_element->setAttribute('grade',$$row{'grade'});
                $unit_element = $doc->createElement('unit');
                $unit_element->setAttribute('id',$$row{'unit_id'});
                $unit_element->setAttribute('title',$$row{'unit_title'});
                $unit_text_node = $doc->createTextNode($$row{'unit_description'});
                $unit_element->appendChild($unit_text_node);
                $lesson_element = $doc->createElement('lesson');
                $lesson_element->setAttribute('id',$$row{'lesson_id'});
                $lesson_element->setAttribute('title',$$row{'lesson_title'});
                $lesson_text_node = $doc->createTextNode($$row{'lesson_description'});
                $lesson_element->appendChild($lesson_text_node);
                if ($$row{'principle_id'}) {
                    $principle_element = &build_principle_element($doc, $row);
                    $lesson_element->appendChild($principle_element);
                }
            } else {
                if ($current_grade ne $$row{'grade'}) {
                    $current_grade = $$row{'grade'};
                    $current_unit = $$row{'unit_id'};
                    $current_lesson = $$row{'lesson_id'};
                    $unit_element->appendChild($lesson_element);
                    $grade_element->appendChild($unit_element);
                    $curriculum_root->appendChild($grade_element);
                    $grade_element = $doc->createElement('grade');
                    $grade_element->setAttribute('grade',$$row{'grade'});
                    $unit_element = $doc->createElement('unit');
                    $unit_element->setAttribute('id',$$row{'unit_id'});
                    $unit_element->setAttribute('title',$$row{'unit_title'});
                    $unit_text_node = $doc->createTextNode($$row{'unit_description'});
                    $unit_element->appendChild($unit_text_node);
                    $lesson_element = $doc->createElement('lesson');
                    $lesson_element->setAttribute('id',$$row{'lesson_id'});
                    $lesson_element->setAttribute('title',$$row{'lesson_title'});
                    $lesson_text_node = $doc->createTextNode($$row{'lesson_description'});
                    $lesson_element->appendChild($lesson_text_node);
                    if ($$row{'principle_id'}) {
                        $principle_element = &build_principle_element($doc, $row);
                        $lesson_element->appendChild($principle_element);
                    }
                } else {
                    if($current_unit ne $$row{'unit_id'}) {
                        $current_unit = $$row{'unit_id'};
                        $current_lesson = $$row{'lesson_id'};
                        $unit_element->appendChild($lesson_element);
                        $grade_element->appendChild($unit_element);
                        $unit_element = $doc->createElement('unit');
                        $unit_element->setAttribute('id',$$row{'unit_id'});
                        $unit_element->setAttribute('title',$$row{'unit_title'});
                        $unit_text_node = $doc->createTextNode($$row{'unit_description'});
                        $unit_element->appendChild($unit_text_node);
                        $lesson_element = $doc->createElement('lesson');
                        $lesson_element->setAttribute('id',$$row{'lesson_id'});
                        $lesson_element->setAttribute('title',$$row{'lesson_title'});
                        $lesson_text_node = $doc->createTextNode($$row{'lesson_description'});
                        $lesson_element->appendChild($lesson_text_node);
                        if ($$row{'principle_id'}) {
                            $principle_element = &build_principle_element($doc, $row);
                            $lesson_element->appendChild($principle_element);
                        }
                    } else {
                        if($current_lesson ne $$row{'lesson_id'}) {
                            $current_lesson = $$row{'lesson_id'};
                            $unit_element->appendChild($lesson_element);
                            $lesson_element = $doc->createElement('lesson');
                            $lesson_element->setAttribute('id',$$row{'lesson_id'});
                            $lesson_element->setAttribute('title',$$row{'lesson_title'});
                            $lesson_text_node = $doc->createTextNode($$row{'lesson_description'});
                            $lesson_element->appendChild($lesson_text_node);
                            if ($$row{'principle_id'}) {
                                $principle_element = &build_principle_element($doc, $row);
                                $lesson_element->appendChild($principle_element);
                            }
                        } else {
                            $principle_element = &build_principle_element($doc, $row);
                            $lesson_element->appendChild($principle_element);
                        }
                    }
                }
            }
        }
        if ($unit_element) {
            $unit_element->appendChild($lesson_element);
            $grade_element->appendChild($unit_element);
            $curriculum_root->appendChild($grade_element);
        }
        &Apache::Promse::queue_file_for_pickup($file_name, $curriculum_root->toString);
#        print $r->header(-type => 'text/xml');
#        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
#        $r->print($curriculum_root->toString);
    }
    sub build_principle_element {
        my($doc, $row) = @_;
        my $principle_element = $doc->createElement('principle');
        $principle_element->setAttribute('id',$$row{'principle_id'});
        $principle_element->setAttribute('principle',$$row{'principle'});
        if ($$row{'tag_description'}) {
            my $principle_text_node = $doc->createTextNode($$row{'tag_description'});
            $principle_element->appendChild($principle_text_node);
        }
        return($principle_element);
    }
    sub get_themes {
        my ($unit_id) = @_;
        my @standards;
        my $qry = "(SELECT cc_themes.id, cc_themes.title, cc_themes.description, cc_themes.periods,
                    cc_themes.period_duration, cc_themes.sequence, cc_themes.supporting_activity,
                    cc_themes.unit_id, 0 as ghost,'' as comment, -1 as grade, '' as unit_title, 0 as cd,
                    cc_themes.eliminated, cc_themes.sequence as force_sort
                FROM cc_themes
                WHERE cc_themes.unit_id = $unit_id)
                UNION
               (SELECT cc_lesson_history.lesson_id AS id, cc_lesson_history.title as title,
                    cc_lesson_history.description, cc_lesson_history.periods,cc_lesson_history.period_duration,
                    cc_lesson_history.sequence, cc_lesson_history.supporting_activity, cc_themes.unit_id,
                    1 AS ghost, cc_lesson_history.comment, cc_units.grade_id as grade, cc_units.title as unit_title,
			MAX(cc_lesson_history.change_date) as cd, cc_lesson_history.eliminated, 999 as force_sort
                FROM cc_lesson_history
                LEFT JOIN (cc_units, cc_themes) ON cc_themes.id = cc_lesson_history.lesson_id AND
                                                cc_themes.unit_id = cc_units.id
                WHERE cc_lesson_history.unit_id = $unit_id AND (cc_themes.eliminated IS NULL OR cc_themes.eliminated = 0)
		GROUP BY lesson_id)
                ORDER BY force_sort ASC";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @standards,{%$row};
        }
        return(\@standards);
    }
    sub get_themes_by_tag {
        # retrieves themes (lessons) to be returned to flash for display
        # selects by grade and curriculum need to permit filter by tag
        my ($r) = @_;
        my $pf_end_id = $r->param('pfendid');
        my $standard_flag = $r->param('standardflag');
        my @themes;
        my $qry = "SELECT cc_themes.id AS theme_id, cc_themes.title as theme_title, cc_themes.description AS theme_description,
                          cc_themes.periods AS theme_periods, cc_themes.period_duration as theme_period_duration, 
                          cc_themes.supporting_activity,
                          cc_themes.sequence as theme_sequence, cc_units.id as unit_id, cc_units.sequence as unit_sequence,
                          cc_units.title as unit_title, cc_units.description as unit_description,
                          cc_principles.principle as principle, cc_principles.id as principle_id, cc_themes.tagged as tagged
                    FROM cc_themes
    		LEFT JOIN cc_units ON cc_units.id = cc_themes.unit_id
                    WHERE cc_themes.id IN 
    			(SELECT cc_pf_theme_tags.theme_id FROM cc_pf_theme_tags WHERE
    				cc_pf_theme_tags.pf_end_id = $pf_end_id AND
    				cc_pf_theme_tags.standard_flag = $standard_flag)";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @themes,{%$row};
        }
        return(\@themes);
    }
    sub get_themes_for_coding {
        # retrieves themes (lessons) to be returned to flash for display
        # selects by grade and curriculum need to permit filter by tag
        # need different query for math and science
        my ($subject, $curriculum_id, $grade) = @_;
        my @themes;
        my $qry;
        if ($subject eq 'Science') {
             $qry = "SELECT cc_themes.id AS theme_id, cc_themes.title as theme_title, cc_themes.description AS theme_description,
                          cc_themes.periods AS theme_periods, cc_themes.period_duration as theme_period_duration,
                          cc_themes.supporting_activity,cc_themes.eliminated, cc_themes.lesson_notes,
                          cc_themes.sequence as theme_sequence, cc_units.id as unit_id, cc_units.sequence as unit_sequence,
                          cc_units.title as unit_title, cc_units.description as unit_description,
                          cc_principles.principle as principle, cc_principles.id as principle_id, cc_themes.tagged as tagged
                    FROM cc_themes
                    LEFT JOIN cc_units ON cc_units.id = cc_themes.unit_id
                    LEFT JOIN (cc_pf_theme_tags, cc_principles) ON cc_pf_theme_tags.theme_id = cc_themes.id AND
                                     cc_pf_theme_tags.pf_end_id = cc_principles.id
                    WHERE cc_units.curriculum_id = $curriculum_id AND
                          cc_units.grade_id = $grade
                    ORDER BY unit_sequence, theme_sequence, principle_id";
        } else {
            $qry = "SELECT cc_themes.id AS theme_id, cc_themes.title as theme_title, cc_themes.description AS theme_description,
                          cc_themes.periods AS theme_periods, cc_themes.period_duration as theme_period_duration,
                          cc_themes.tagged as tagged, cc_themes.supporting_activity, cc_themes.eliminated,
                          cc_themes.sequence as theme_sequence, cc_units.id as unit_id, cc_units.sequence as unit_sequence,
                          cc_units.description as unit_description, cc_units.title as unit_title
                    FROM cc_themes, cc_units
                    WHERE cc_units.curriculum_id = $curriculum_id AND
                          cc_units.grade_id = $grade AND
                          cc_units.id = cc_themes.unit_id
                    ORDER BY unit_sequence, theme_sequence"
        }
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @themes,{%$row};
        }
        return(\@themes);
    }
    sub get_standards {
        my ($district_id) = @_;
        my @standards;
        my $qry = "select id, standard, description, sequence from cc_district_standards where district_id = $district_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @standards,{%$row};
        }
        return(\@standards);
    }
    sub get_district_materials {
        my($r) = @_;
        my $district_id = $r->param('districtid');
        my $subject = $env{'subject'};
        my @materials;
        my $qry = "SELECT id, grades, title, author, year, edition, isbn, notes, district_id 
                    FROM cc_materials t1
                    JOIN  cc_district_materials t2 on t1.id = t2.material_id 
    		        WHERE t2.district_id  = $district_id AND
    		              t1.subject = '$subject'
    		        ORDER BY title";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @materials, {%$row};
        }
        return(\@materials);
    }
    sub chunk_node {
        my ($row) = @_;
        my $chunk_node;
        if ($$row{'chunk_id'}) {
            $chunk_node .= '<chunk chunkid="'.$$row{'chunk_id'}.'">';
            $chunk_node .= '<title>';
            $chunk_node .= $$row{'chunk_title'};
            $chunk_node .= '</title>';
            $chunk_node .= '<description>';
            $chunk_node .= $$row{'description'};
            $chunk_node .= '</description>';
            $chunk_node .= '</chunk>';
        }
        return ($chunk_node);
    }
    sub get_theme_chunks {
        my ($theme_id) = @_;
        my @material_chunks;
        my $qry = "SELECT cc_material_chunks.id, material_id, cc_material_chunks.title, 
                    cc_materials.title as material_title, description, unused_portion 
                   FROM cc_material_chunks
    		LEFT JOIN cc_materials on cc_materials.id = cc_material_chunks.material_id
                   WHERE theme_id = $theme_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @material_chunks,{%$row};
        }
        return(\@material_chunks);
    }
    sub get_chunk_principles {
        my ($chunk_id) = @_;
        my @chunk_principles;
        my $qry = "select chunk_id, principle_id, principle, notes FROM cc_chunk_principle t1 
                    LEFT JOIN cc_principles t2 on t2.id = t1.principle_id
                    WHERE chunk_id = $chunk_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @chunk_principles,{%$row};
        }
        return(\@chunk_principles);
    }
    sub get_chunk_standards {
        my ($chunk_id) = @_;
        my @chunk_standards;
        my $qry = "select chunk_id, standard_id, standard, notes from cc_chunk_standard t1
                    LEFT JOIN cc_district_standards t2 on t1.standard_id = t2.id
                    WHERE chunk_id = $chunk_id";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @chunk_standards,{%$row};
        }
        return(\@chunk_standards);
    }
    sub return_implemented {
        # return XML with grade and coord
        my ($r) = @_;
        my $district = $r->param('district');
        my $year = $r->param('year');
        my $grade = $r->param('grade');
        my $qry = "SELECT t1.time_spent, t1.topic_code, t3.coord, t3.code 
                    FROM (implemented_curriculum t1, topic_framework t2)
                    LEFT join math_framework t3 ON ( (t3.code = t2.framework_code) or 
                                (t2.framework_code like concat(t3.code,'.%')) )
                    WHERE t1.grade = $grade and t1.location_id = $district and t3.coord <> 0 
                                       and t1.topic_code = t2.topic_code  
                                       and t1.year = $year
                    ORDER BY t3.coord";
                 
        my $sth = $Apache::Promse::env{'dbh'}->prepare($qry);
        $sth->execute();
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print("<implemented>\n");
        while (my $row = $sth->fetchrow_hashref) {
            my ($x,$y) = split(/_/,$$row{'coord'});
            my $time_spent = $$row{'time_spent'};
            print '<cell  x="'.$x.'" y="'.$y.'" timespent="'.$time_spent.'" />'."\n";
        }
        $r->print("</implemented>\n");
        return ('ok');
    }
    sub get_next_theme_seq {
        my ($r) = @_;
        my $unit_id = $r->param('unitid');
        my $qry = "SELECT max(sequence) as sequence FROM cc_themes 
                        WHERE unit_id = $unit_id";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        my $next_id;
        if ($$row{'sequence'}) {
            $next_id = $$row{'sequence'};
        } else {
            $next_id = 1;
        }
        return($next_id + 1);
    }
    
    sub get_next_unit_seq {
        my ($r) = @_;
        my $curriculum_id = $r->param('curriculumid');
        my $grade_id = $r->param('grade');
        $grade_id = ($grade_id eq 'K')?0:$grade_id;
        $grade_id = ($grade_id eq 'HS')?9:$grade_id;
        my $qry = "SELECT max(sequence) as sequence FROM cc_units 
                        WHERE curriculum_id = $curriculum_id
                        AND grade_id = $grade_id";
        my $sth = $env{'dbh'}->prepare($qry);
        # &Apache::Promse::logthis($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        my $next_id;
        if ($$row{'sequence'} > 0) {
            $next_id = $$row{'sequence'};
            $next_id ++;
        } else {
            $next_id = 1;
        }
        return($next_id);
    }
    sub get_materials {
        my ($district_id, $subject, $grade) = @_;
        my $grade_filter;
        if ($grade) {
            if ($grade eq "K") {
                $grade_filter = "AND ((grades LIKE '%K%') OR (grades LIKE '%1%')) ";
            } elsif ($grade eq "1"){
                $grade_filter = "AND ((grades LIKE '%K%') OR (grades LIKE '%1%') OR (grades LIKE '%2%')) ";
            } elsif ($grade eq "8") {
                $grade_filter = "AND ((grades LIKE '%7%') OR (grades LIKE '%8%')) ";
            } else {
                my $bottom = $grade - 1;
                my $top = $grade + 1;
                $grade_filter = "AND ((grades LIKE '%$bottom%') OR (grades LIKE '%$grade%') OR (grades LIKE '%$top%')) ";
            }
        } else {
            $grade_filter = "";
        }
        # retrieves materials 
        my @materials;
        my $qry = "SELECT * FROM cc_materials
                    LEFT JOIN cc_district_materials ON 
                    ((district_id = $district_id) AND (cc_materials.id = cc_district_materials.material_id))
                     
                    $grade_filter
                    ORDER BY title";
        # WHERE cc_materials.subject = '$subject'    REMOVED for test
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        while (my $row = $rst->fetchrow_hashref()) {
            push @materials, {%$row};
        }
        return(\@materials);
    }
    sub get_existing_tags {
        my ($r) = @_;
        my $theme_id = $r->param('themeid');
        my $doc = XML::DOM::Document->new;
        my $tags_root = $doc->createElement("tags");
        my $qry;
        my $rst;
        my $row;
        my $tagXML;
        my $tag_name_element;
        my $tag_text;
        my $notes_text;
        my $notes_element;
        $tags_root->setAttribute("themeid", $theme_id);
        if ($r->param('subject') eq 'Math') {
            $qry = "SELECT cc_pf_standards.standard, cc_pf_subpoints.subpoint, cc_pf_theme_tags.pf_end_id, 
                            cc_pf_theme_tags.standard_flag, cc_pf_theme_tags.notes, cc_pf_theme_tags.strength,
                            cc_pf_standards.grade
        	        FROM cc_pf_theme_tags 
                        LEFT JOIN cc_pf_standards on cc_pf_standards.id = cc_pf_theme_tags.pf_end_id AND cc_pf_theme_tags.standard_flag = 1
                        LEFT JOIN cc_pf_subpoints on cc_pf_subpoints.id = cc_pf_theme_tags.pf_end_id AND  cc_pf_theme_tags.standard_flag = 0
                        WHERE cc_pf_theme_tags.theme_id = $theme_id";
            $rst = $env{'dbh'}->prepare($qry);
            $rst->execute();
            while ($row = $rst->fetchrow_hashref()) {
                $tagXML = $doc->createElement("tag");
                $tagXML->setAttribute('standardflag',$$row{'standard_flag'});
                $tagXML->setAttribute('grade',$$row{'grade'});
                $tagXML->setAttribute('pfendid',$$row{'pf_end_id'});
                $tagXML->setAttribute('strength',$$row{'strength'});
                my $tag_text;
                if ($$row{'standard_flag'}) {
                    $tag_text = $doc->createTextNode($$row{'standard'});
                } else {
                    $tag_text = $doc->createTextNode($$row{'subpoint'});
                }
                $tag_name_element = $doc->createElement('tagname');
                $tag_name_element->appendChild($tag_text);
                $tagXML->appendChild($tag_name_element);
                $notes_element = $doc->createElement('note');
                $notes_text = $doc->createTextNode($$row{'notes'});
                $notes_element->appendChild($notes_text);
                $tagXML->appendChild($notes_element);
                $tags_root->appendChild($tagXML);
            }
        } else {
            $qry = "SELECT cc_principles.principle, cc_principles.id AS pf_end_id, cc_pf_theme_tags.notes,
                        cc_pf_theme_tags.strength
                        FROM cc_principles, cc_pf_theme_tags
                        WHERE cc_pf_theme_tags.theme_id = $theme_id AND
                              cc_principles.id = cc_pf_theme_tags.pf_end_id
                              ORDER BY pf_end_id";
            $rst = $env{'dbh'}->prepare($qry);
            $rst->execute();
            while ($row = $rst->fetchrow_hashref()) {
                $tagXML = $doc->createElement("tag");
                $tagXML->setAttribute('standardflag',$$row{'standard_flag'});
                $tagXML->setAttribute('pfendid',$$row{'pf_end_id'});
                $tagXML->setAttribute('strength',$$row{'strength'});
                $tag_name_element = $doc->createElement('tagname');
                $tag_text = $doc->createTextNode($$row{'principle'});
                $tag_name_element->appendChild($tag_text);
                $tagXML->appendChild($tag_name_element);
                $notes_element = $doc->createElement('note');
                $notes_text = $doc->createTextNode($$row{'notes'});
                $notes_element->appendChild($notes_text);
                $tagXML->appendChild($notes_element);
                $tags_root->appendChild($tagXML);
            }
        }
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
        $r->print($tags_root->toString());
    }
    sub get_curricula {
        my($district_id, $subject) = @_;
        my @curricula;
        my $qry = "SELECT id, title, description, district_name
                   FROM cc_curricula, cc_curricula_districts, districts 
                   WHERE cc_curricula_districts.district_id = $district_id 
                   AND cc_curricula_districts.curriculum_id = cc_curricula.id
                   AND cc_curricula.subject = '$subject'
                   AND districts.district_id = $district_id
                   ORDER BY cc_curricula.title";
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        #&Apache::Promse::logthis('******');
        #&Apache::Promse::logthis($qry);
        while (my $curriculum = $rst->fetchrow_hashref()) {
            push @curricula,{%$curriculum};
        }
        return(\@curricula);
    }
    sub build_material_item_element {
        my ($item, $doc) = @_;
        my $title = $$item{'title'}?$$item{'title'}:'';
        my $author = $$item{'author'}?$$item{'author'}:'';
        my $edition = $$item{'title'}?$$item{'edition'}:'';
        my $grades = $$item{'grades'}?$$item{'grades'}:'';
        my $year = $$item{'year'}?$$item{'year'}:'';
        my $publisher = $$item{'publisher'}?$$item{'publisher'}:'';
        my $isbn = $$item{'isbn'}?$$item{'isbn'}:'';
        my $organization = $$item{'organization'}?$$item{'organization'}:'';
        my $notes = $$item{'notes'}?$$item{'notes'}:'';
        my $district_id = $$item{'district_id'}?$$item{'district_id'}:'';
        # FIX ME  XML has elements that should be attributes requires 
        # fixing the client side to really be right
        my $item_element = $doc->createElement('item');
        $item_element->setAttribute('id',$$item{'id'});
        $item_element->setAttribute('isbn',$isbn);
        $item_element->setAttribute('districtid',$district_id);
        $item_element->setAttribute('year',$year);
        my $title_element = $doc->createElement('title');
        my $title_text_node = $doc->createTextNode($title);
        $title_element->appendChild($title_text_node);
        $item_element->appendChild($title_element);
        my $author_element = $doc->createElement('author');
        my $author_text_node = $doc->createTextNode($author);
        $author_element->appendChild($author_text_node);
        $item_element->appendChild($author_element);
        my $edition_element = $doc->createElement('edition');
        my $edition_text_node = $doc->createTextNode($edition);
        $edition_element->appendChild($edition_text_node);
        $item_element->appendChild($edition_element);
        my $grades_element = $doc->createElement('grades');
        my $grades_text_node = $doc->createTextNode($grades);
        $grades_element->appendChild($grades_text_node);
        $item_element->appendChild($grades_element);
        my $publisher_element = $doc->createElement('publisher');
        my $publisher_text_node = $doc->createTextNode($publisher);
        $publisher_element->appendChild($publisher_text_node);
        $item_element->appendChild($publisher_element);
        my $organization_element = $doc->createElement('organization');
        my $organization_text_node = $doc->createTextNode($organization);
        $organization_element->appendChild($organization_text_node);
        $item_element->appendChild($organization_element);
        my $notes_element = $doc->createElement('notes');
        my $notes_text_node = $doc->createTextNode($notes);
        $notes_element->appendChild($notes_text_node);
        $item_element->appendChild($notes_element);
        return($item_element);
    }
    sub getCurriculaJSON {
        my($r) = @_;
        my $location_info = Apache::Promse::get_user_location();
        my $district_id = $$location_info{'district_id'};
        print STDERR "location is $district_id";
        # returns all curricula owned by a district within the supplied partner_id
        # each curriculum is associated with particular partner
        my $qry = "SELECT distinct cc_curricula.title, cc_curricula.id
                   FROM cc_curricula, partners, districts,  cc_curricula_districts
                   WHERE cc_curricula.id =  cc_curricula_districts.curriculum_id  
                        AND cc_curricula_districts.district_id = districts.district_id
                        AND districts.district_id = ?
                        AND cc_curricula.subject = ?
                   ORDER BY cc_curricula.title";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute($district_id, $env{'subject'});
        my @curricula;
        while (my $curriculum = $sth->fetchrow_hashref()){
            push @curricula, {%$curriculum};
        }
        my %output;
        $output{'curricula'} = [@curricula];
	    $r->print(JSON::XS::->new->pretty(1)->encode( \%output));
        
    }
    sub get_activity_report {
        my($r) = @_;
        my $qry = "SELECT users.id, users.LastName, users.FirstName, users.username, users.active, tj_user_info.default_curriculum,
        cc_curricula.title, tj_user_classes.class_id, tj_classes.class_name, user_locs.loc_id, locations.location_id, 
		all_schools.district_name
        FROM users
        LEFT JOIN tj_user_info ON tj_user_info.user_id = users.id
        LEFT JOIN cc_curricula ON cc_curricula.id = tj_user_info.default_curriculum
        LEFT JOIN tj_user_classes ON tj_user_classes.user_id = users.id
        LEFT JOIN tj_classes ON tj_classes.class_id = tj_user_classes.class_id
        LEFT JOIN user_locs ON user_locs.user_id = users.id
        LEFT JOIN locations ON locations.location_id = user_locs.loc_id
        LEFT JOIN all_schools ON user_locs.loc_id = all_schools.id
        WHERE users.id > 9720
        ORDER BY users.id";
        my @users;
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        while (my $userRow = $sth->fetchrow_hashref()){
            push @users, {%$userRow};
        }
        my %output;
        $output{'users'} = [@users];
        
        $r->print(JSON::XS::->new->pretty(1)->encode( \%output));
    }
    sub get_all_curricula {
        my($r) = @_;
        # gets curricula that are associated with a PROM/SE partner, that is all
        # districts in selected partner
        my $partner_id = $r->param('partnerid');
        # returns all curricula owned by a district within the supplied partner_id
        # each curriculum is associated with particular partner
        my $qry = "SELECT distinct cc_curricula.title, cc_curricula.id
                   FROM cc_curricula, partners, districts,  cc_curricula_districts
                   WHERE cc_curricula.id =  cc_curricula_districts.curriculum_id  
                        AND cc_curricula_districts.district_id = districts.district_id
                        AND districts.partner_id = $partner_id";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $doc = XML::DOM::Document->new();
        my $curricula_root = $doc->createElement('curricula');
        while (my $curriculum = $sth->fetchrow_hashref()){
            my $curriculum_element = $doc->createElement('curriculum');
            $curriculum_element->setAttribute('id',$$curriculum{'id'});
            my $in_district = $$curriculum{'district_id'}?1:0;
            $curriculum_element->setAttribute('indistrict',$in_district);
            my $title_element = $doc->createElement('title');
            my $title_text_node = $doc->createTextNode($$curriculum{'title'});
            $title_element->appendChild($title_text_node);
            $curriculum_element->appendChild($title_element);
            my $description_element = $doc->createElement('description');
            my $description_text_node = $doc->createTextNode($$curriculum{'description'});
            $description_element->appendChild($description_text_node);
            $curriculum_element->appendChild($description_element);
            $curricula_root->appendChild($curriculum_element);
        }
        &xml_header($r);
        $r->print($curricula_root->toString());
    }
    sub get_all_scores { 
        # returns nodes and scores for feeding to make_gfw
        my ($district,$year) = @_;
        my $level;
        my @district_scores;
        my $qry = "SELECT * FROM school_performance 
                    WHERE school_performance.school IN 
                        (SELECT location_id FROM locations WHERE district_id = $district ) AND 
                        year = $year";
        my $sth = $Apache::Promse::env{'dbh'}->prepare($qry);
        $sth->execute();
        while (my $row = $sth->fetchrow_hashref()) {
            my $grade = $$row{'grade'};
            if ($grade =~ /[3|4|5]/) {
                $level = 'ES';
            } elsif ($grade =~ /[6|7|8]/) {
                $level = 'MS';
            }
            
            my $coords = &Apache::Promse::strand_to_coords($$row{'strand'},$level);
            foreach my $coord(@$coords) {
                push (@district_scores,({'coord' => $coord,
                                        'grade' => $grade,
                                        'score' => $$row{'score'}}));
            }
        }
        return (\@district_scores);   
    }
    
    sub test {
        # &Apache::Promse::logthis("in the test");
    }
    
    sub get_URL_path {
        my ($r) = @_;
        my $path = $r->self_url();
        $path =~ /(.+)(\/\/)(.+?)(\/)(.+$)/ ;
        $path = $1.$2.$3.$4;
        return ($path);
    }
    sub promse_admin_html {
        my($r) = @_;
        my $row = &Apache::Promse::get_user_location();
        my $district_id = $$row{'district_id'};
        my $district_name = $$row{'district_name'};
        my $token = $env{'token'};
        my $path = &get_URL_path($r);
        my $subject = $env{'subject'};
    #<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
    #<head>
    #<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
    #<title>curriculum_coherence</title>
        my $output = qq~
    <script language="javascript">AC_FL_RunContent = 0;</script>
    <script src="../flash/AC_RunActiveContent.js" language="javascript"></script>
    </head>
    <body bgcolor="#ffffff">
    <!--url's used in the movie-->
    <!--text used in the movie-->
    <!-- saved from url=(0013)about:internet -->
    <script language="javascript">
        function getToken() {
            return "$token";
        }
        function getDistrict() {
            return "$district_id";
        }
        function getDistrictName() {
            return "$district_name";
        }
        function getPath() {
            return "$path";
        }
        function getSubject() {
            return "$subject";
        }
    	if (AC_FL_RunContent == 0) {
    		alert("This page requires AC_RunActiveContent.js.");
    	} else {
    		AC_FL_RunContent(
    			'codebase', 'http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0',
    			'width', '1024',
    			'height', '768',
    			'src', '../flash/promseAdmin',
    			'quality', 'high',
    			'pluginspage', 'http://www.macromedia.com/go/getflashplayer',
    			'align', 'middle',
    			'play', 'true',
    			'loop', 'true',
    			'scale', 'showall',
    			'wmode', 'window',
    			'devicefont', 'false',
    			'id', 'promseAdmin',
    			'bgcolor', '#ffffff',
    			'name', 'promseAdmin',
    			'menu', 'true',
    			'allowFullScreen', 'false',
    			'allowScriptAccess','sameDomain',
    			'movie', '../flash/promseAdmin',
    			'salign', ''
    			); //end AC code
    	}
    </script>
    <noscript>
    	<object classid="clsid:d27cdb6e-ae6d-11cf-96b8-444553540000" codebase="http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0" width="1024" height="768" id="promseAdmin" align="middle">
    	<param name="allowScriptAccess" value="sameDomain" />
    	<param name="allowFullScreen" value="false" />
    	<param name="movie" value="promseAdmin.swf" /><param name="quality" value="high" /><param name="bgcolor" value="#ffffff" />	<embed src="http://vpddev.educ.msu.edu/flash/curriculum_coherence.swf" quality="high" bgcolor="#ffffff" width="1024" height="768" name="promseAdmin" align="middle" allowScriptAccess="sameDomain" allowFullScreen="false" type="application/x-shockwave-flash" pluginspage="http://www.macromedia.com/go/getflashplayer" />
    	</object>
    </noscript>
    </body>
    </html>
    ~;    
        $r->print($output);
        return('ok'); 
    }
    sub teacher_message_html {
        my($r) = @_;
        my $row = &Apache::Promse::get_user_location();
        my $district_id = $$row{'district_id'};
        my $district_name = $$row{'district_name'};
        my $token = $env{'token'};
        my $path = &get_URL_path($r);
        my $subject = $env{'subject'};
        my $roles = $env{'user_roles'};
    #<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
    #<head>
    #<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
    #<title>curriculum_coherence</title>
        my $output = qq~
    <script language="javascript">AC_FL_RunContent = 0;</script>
    <script src="../flash/AC_RunActiveContent.js" language="javascript"></script>
    </head>
    <body bgcolor="#ffffff">
    <!--url's used in the movie-->
    <!--text used in the movie-->
    <!-- saved from url=(0013)about:internet -->
    <script language="javascript">
        function getToken() {
            return "$token";
        }
        function getDistrict() {
            return "$district_id";
        }
        function getRoles() {
            return "$roles";
        }
        function getUserID() {
            return "$env{'user_id'}";
        }
        function getUserPhoto() {
            return "$env{'photo'}";
        }
        function getDistrictName() {
            return "$district_name";
        }
        function getPath() {
            return "$path";
        }
        function getSubject() {
            return "$subject";
        }
    	if (AC_FL_RunContent == 0) {
    		alert("This page requires AC_RunActiveContent.js.");
    	} else {
    		AC_FL_RunContent(
    			'codebase', 'http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0',
    			'width', '1024',
    			'height', '768',
    			'src', '../flash/teacherMessage',
    			'quality', 'high',
    			'pluginspage', 'http://www.macromedia.com/go/getflashplayer',
    			'align', 'middle',
    			'play', 'true',
    			'loop', 'true',
    			'scale', 'showall',
    			'wmode', 'window',
    			'devicefont', 'false',
    			'id', 'teacherMessage',
    			'bgcolor', '#ffffff',
    			'name', 'teacherMessage',
    			'menu', 'true',
    			'allowFullScreen', 'false',
    			'allowScriptAccess','sameDomain',
    			'movie', '../flash/teacherMessage',
    			'salign', ''
    			); //end AC code
    	}
    </script>
    <noscript>
    	<object classid="clsid:d27cdb6e-ae6d-11cf-96b8-444553540000" codebase="http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0" width="1024" height="768" id="teacherMessage" align="middle">
    	<param name="allowScriptAccess" value="sameDomain" />
    	<param name="allowFullScreen" value="false" />
    	<param name="movie" value="teacherMessage.swf" /><param name="quality" value="high" /><param name="bgcolor" value="#ffffff" />	<embed src="http://vpddev.educ.msu.edu/flash/teacherMessage.swf" quality="high" bgcolor="#ffffff" width="1024" height="768" name="teacherMessage" align="middle" allowScriptAccess="sameDomain" allowFullScreen="false" type="application/x-shockwave-flash" pluginspage="http://www.macromedia.com/go/getflashplayer" />
    	</object>
    </noscript>
    </body>
    </html>
    ~;    
        $r->print($output);
        return('ok'); 
    }
    
    sub curriculum_coherence_html {
        my($r) = @_;
        my $row = &Apache::Promse::get_user_location();
        my $district_id = $$row{'district_id'};
        my $district_name = $$row{'district_name'};
        my $token = $env{'token'};
        my $path = &get_URL_path($r);
        my $subject = $env{'subject'};
        my $roles = $env{'user_roles'};
    #<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
    #<head>
    #<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
    #<title>curriculum_coherence</title>
        my $output = qq~
    <script language="javascript">AC_FL_RunContent = 0;</script>
    <script src="../flash/AC_RunActiveContent.js" language="javascript"></script>
    </head>
    <body bgcolor="#ffffff">
    <!--url's used in the movie-->
    <!--text used in the movie-->
    <!-- saved from url=(0013)about:internet -->
    <script language="javascript">
        function getToken() {
            return "$token";
        }
        function getDistrict() {
            return "$district_id";
        }
        function getRoles() {
            return "$roles";
        }
        function getDistrictName() {
            return "$district_name";
        }
        function getPath() {
            return "$path";
        }
        function getSubject() {
            return "$subject";
        }
    	if (AC_FL_RunContent == 0) {
    		alert("This page requires AC_RunActiveContent.js.");
    	} else {
    		AC_FL_RunContent(
    			'codebase', 'http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0',
    			'width', '1024',
    			'height', '768',
    			'src', '../flash/curriculum_coherence',
    			'quality', 'high',
    			'pluginspage', 'http://www.macromedia.com/go/getflashplayer',
    			'align', 'middle',
    			'play', 'true',
    			'loop', 'true',
    			'scale', 'showall',
    			'wmode', 'window',
    			'devicefont', 'false',
    			'id', 'curriculum_coherence',
    			'bgcolor', '#ffffff',
    			'name', 'curriculum_coherence',
    			'menu', 'true',
    			'allowFullScreen', 'false',
    			'allowScriptAccess','sameDomain',
    			'movie', '../flash/curriculum_coherence',
    			'salign', ''
    			); //end AC code
    	}
    </script>
    <noscript>
    	<object classid="clsid:d27cdb6e-ae6d-11cf-96b8-444553540000" codebase="http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0" width="1024" height="768" id="curriculum_coherence" align="middle">
    	<param name="allowScriptAccess" value="sameDomain" />
    	<param name="allowFullScreen" value="false" />
    	<param name="movie" value="curriculum_coherence.swf" /><param name="quality" value="high" /><param name="bgcolor" value="#ffffff" />	<embed src="http://vpddev.educ.msu.edu/flash/curriculum_coherence.swf" quality="high" bgcolor="#ffffff" width="1024" height="768" name="curriculum_coherence" align="middle" allowScriptAccess="sameDomain" allowFullScreen="false" type="application/x-shockwave-flash" pluginspage="http://www.macromedia.com/go/getflashplayer" />
    	</object>
    </noscript>
    </body>
    </html>
    ~;  
        $r->print($output);
    }
    
    sub gfw_flash_html {
        my ($r) = @_;
        my $profile_hashref = &Apache::Promse::get_user_profile($Apache::Promse::env{'user_id'});
        my $grade;
        my $year;
        my $path = &get_URL_path($r);
        my $district_id = $$profile_hashref{'district_id'};
        my $partner_id = $$profile_hashref{'partner_id'};
        if ($r->param('grade')) {
            $grade = $r->param('grade');
        } else {
            $grade = 5;
        }
        if ($r->param('year')) {
            $year = $r->param('year');
        } else {
            $year = 2004;
        }
        my $token = $Apache::Promse::env{'token'};
        my $output = <<ENDHTML;
    <script language="javascript" type="text/javascript">AC_FL_RunContent = 0;</script>
    <script src="../flash/AC_RunActiveContent.js" language="javascript" type="text/javascript"></script>
    <!--url's used in the movie-->
    <!--text used in the movie-->
    <!-- saved from url=(0013)about:internet -->
    <script language="javascript" type="text/javascript">
        function getToken() {
            return "$token";
        }
        function getPartner() {
            return "$partner_id";
        }
        function getDistrict() {
            return "$district_id";
        }
        function getGrade() {
            return "$grade";
        }
        function getYear() {
            return "$year";
        }
        function getPath() {
            return "$path";
        }
    	if (AC_FL_RunContent == 0) {
    		alert("This page requires AC_RunActiveContent.js.");
    	} else {
    		AC_FL_RunContent(
    			'codebase', 'http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0',
    			'width', '550',
    			'height', '400',
    			'src', '../flash/graphic_framework',
    			'quality', 'high',
    			'pluginspage', 'http://www.macromedia.com/go/getflashplayer',
    			'align', 'middle',
    			'play', 'true',
    			'loop', 'true',
    			'scale', 'showall',
    			'wmode', 'window',
    			'devicefont', 'false',
    			'id', 'graphic_framework',
    			'bgcolor', '#ffffff',
    			'name', 'graphic_framework',
    			'menu', 'true',
    			'allowFullScreen', 'false',
    			'allowScriptAccess','sameDomain',
    			'movie', '../flash/graphic_framework',
    			'salign', ''
    			); //end AC code
    	}
    </script>
    <noscript>
    	<object classid="clsid:d27cdb6e-ae6d-11cf-96b8-444553540000" codebase="http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0" width="550" height="400" id="graphic_framework" align="middle">
    	<param name="allowScriptAccess" value="sameDomain" />
    	<param name="allowFullScreen" value="false" />
    	<param name="movie" value="graphic_framework.swf" />
    	<param name="quality" value="high" />
    	<param name="bgcolor" value="#ffffff" />	
    	<embed src="http://vpddev.educ.msu.edu/flash/graphic_framework.swf" quality="high" bgcolor="#ffffff" width="550" height="400" name="graphic_framework" align="middle" allowScriptAccess="sameDomain" allowFullScreen="false" type="application/x-shockwave-flash" pluginspage="http://www.macromedia.com/go/getflashplayer" />
    	</object>
    </noscript>
    
ENDHTML
        $r->print($output);
        return('ok');
    }
    sub vid_slide_html {
        my ($r) = @_;
        my $resource_id = $r->param('resourceid');
        my $url_path = &get_URL_path($r);
        my $path = $r->param('showname');
        my $page_num = 1;
        my $current_page = 1;
        my $token = $Apache::Promse::env{'token'};
        my $output = <<ENDHTML;
    <script language="javascript" type="text/javascript">AC_FL_RunContent = 0;</script>
    <script src="../flash/AC_RunActiveContent.js" language="javascript" type="text/javascript"></script>
        
        <script language="javascript" type="text/javascript">
        function getToken() {
            return "$token";
        }
        function getPath() {
            return "../video/$path/";
        }
        function getResourceid() {
            return "$resource_id";
        }
        function getURLPath() {
            return "$url_path";
        }
        function getPageNum() {
            return "$page_num";
        }
        function getCurrentPage() {
            return "$current_page";
        }
    	if (AC_FL_RunContent == 0) {
    		alert("This page requires AC_RunActiveContent.js.");
    	} else {
    		AC_FL_RunContent(
    			'codebase', 'http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0',
    			'width', '640',
    			'height', '440',
    			'src', '../flash/videoslide',
    			'quality', 'high',
    			'pluginspage', 'http://www.macromedia.com/go/getflashplayer',
    			'align', 'middle',
    			'play', 'true',
    			'loop', 'true',
    			'scale', 'showall',
    			'wmode', 'window',
    			'devicefont', 'false',
    			'id', 'videoslide',
    			'bgcolor', '#ffffff',
    			'name', 'videoslide',
    			'menu', 'true',
    			'allowFullScreen', 'false',
    			'allowScriptAccess','sameDomain',
    			'movie', '../flash/videoslide',
    			'salign', ''
    			); //end AC code
    	}
    </script>
    <noscript>
    	<object classid="clsid:d27cdb6e-ae6d-11cf-96b8-444553540000" codebase="http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0" width="640" height="440" id="videoslide" align="middle">
    	<param name="allowScriptAccess" value="sameDomain" />
    	<param name="allowFullScreen" value="false" />
    	<param name="movie" value="videoslide.swf" />
    	<param name="quality" value="high" />
    	<param name="bgcolor" value="#ffffff" />	
    	<embed src="http://vpddev.educ.msu.edu/flash/videoslide.swf" quality="high" bgcolor="#ffffff" width="640" height="440" name="videoslide" align="middle" allowScriptAccess="sameDomain" allowFullScreen="false" type="application/x-shockwave-flash" pluginspage="http://www.macromedia.com/go/getflashplayer" />
    	</object>
    </noscript>
ENDHTML
        $r->print($output);
        return('ok');
    }
    
    1;
    
}
    

1;
__END__

