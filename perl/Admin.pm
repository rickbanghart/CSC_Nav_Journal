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
package Apache::Admin;
# File: Apache/Admin.pm 
use CGI;
use Date::Manip;
use Date::Calc;
use Apache::Journal;
use Apache::Promse;
use Apache::Flash;
use vars qw(%env);
use strict;
use DBI;
sub add_class {
	my ($r) = @_;
	my $button_message = "Add Class";
    my $output;
	my %fields;
    $output = qq ~
    <div class="vpdRecordForm">
    <form method="post">
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
           Class Name
        </div>
        <div class="vpdRecordInput">
            <input class="vpdRecord" type="text" size="30" name="classname" value="" />
        </div>
    </div>
    <div class="vpdRecordInputRow">
        <div class="vpdRecordTitle">
            Grade
        </div>
        <div class="vpdRecordInput">
        <div class="vpdRecordInput">
            <input class="vpdRecord" type="text" size="30" name="grade" value="" />
        </div>
        </div>
    </div>
    <input class="vpdRecordButton" type="submit" value="$button_message" />
    
    ~;
    $r->print($output);
    %fields = ('menu' => 'tj',
               'submenu' => 'classes',
               'action' => "insertclass");
    $r->print(&Apache::Promse::hidden_fields(\%fields));
    $r->print('</form></div>');
    return 'ok';
	
}
sub admin_messages {
    my ($r) = @_;
    my $messages = &get_admin_messages;
    my $jscript = qq~
    <script type="JavaScript">
    <!--
    function confirmDelete()
    {
        var agree=confirm("Are you sure you wish to delete this announcement?");
        if (agree)
        return true ;
        else
        return false ;
    }
    // -->
    </script>
    ~;
    $r->print($jscript);
    
    $r->print('<form method="post" action="admin">');
    print '<table ><caption>Scheduled Messages</caption>';
    $r->print('<thead>');
    print '<tr><th>&nbsp;</th><th>Start Date</th><th>End Date</th><th>Subject</th></tr>';
    $r->print('</thead><tbody>');
    foreach my $message (@$messages) {
        $$message{'start_date'} =~ s/ 00:00:00//;
        $$message{'end_date'} =~ s/ 00:00:00//;
        print '<tr >';
        print '<td><input type="checkbox" name="messageid" value="'.$$message{'id'}.'" /></td>';
        print '<td>'.$$message{'start_date'}.'</td>';
        print '<td>'.$$message{'end_date'}.'</td>';
        my $url_subject = $$message{'subject'};
        $url_subject =~ s/ /%20/g;
        print '<td><a href="admin?token='.$env{'token'}.';menu=messages;submenu=editannouncement;messageid='.$$message{'id'}.'">'.$$message{'subject'}.'</a></td>';
        print '</tr>';
    }
    $r->print('</tbody>');
    print '</table>';
    print '<input type="submit" value="Delete" onClick="return confirmDelete()"/>';
    my %fields = ('menu' => 'messages',
                  'submenu' => 'announcements',
                  'action' => 'delete');
    $r->print(&Apache::Promse::hidden_fields(\%fields));
    print '</form>';
    return 'ok';
}
sub admin_sub_tabs {
    my @sub_tabs;
    my %tab_info;
    my $tab_info_hashref;
    my $active = 1;
    my %fields;
    if ($env{'menu'} eq 'users') {
        $active = ($env{'submenu'} eq 'roles')?1:0;
        $tab_info_hashref = &users_roles_submenu($active);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'add')?1:0;
        $tab_info_hashref = &users_add_submenu($active);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'domains')?1:0;
        $tab_info_hashref = &users_domains_submenu($active);
        push(@sub_tabs,{%$tab_info_hashref});
        if ($env{'submenu'} eq 'edituser') {
            $active = ($env{'submenu'} eq 'edituser')?1:0;
            $tab_info_hashref = &users_edituser_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
        }
    } elsif ($env{'menu'} eq 'tj') {
        $active = ($env{'submenu'} eq 'classes')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','Classes','tj','classes',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'add')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','Add Class','tj','add',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'stats')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','Stats','tj','stats',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'summaries')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','Summaries','tj','summaries',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'comms')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','Comms','tj','comms',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
	} elsif ($env{'menu'} eq 'code') {
        $active = ($env{'submenu'} eq 'flash')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','Flash','code','flash',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'cc')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','Grid','code','grid',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'spell')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','Spell','code','spell',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
	} elsif ($env{'menu'} eq 'stats') {
        $active = ($env{'submenu'} eq 'system')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','System','stats','system',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'cc')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','CC','stats','cc',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'tj')?1:0;
        $tab_info_hashref = &Apache::Promse::tabbed_menu_item('admin','TJ','stats','tj',$active,'tabBottom',undef);
        push(@sub_tabs,{%$tab_info_hashref});
    } elsif ($env{'menu'} eq 'messages') {
        $active = ($env{'submenu'} eq 'announcements')?1:0;
        $tab_info_hashref = &messages_announcements_submenu($active);
        push(@sub_tabs,{%$tab_info_hashref});
        $active = ($env{'submenu'} eq 'addannouncement')?1:0;
        $tab_info_hashref = &messages_addannouncement_submenu($active);
        push(@sub_tabs,{%$tab_info_hashref});
        if ($env{'submenu'} eq 'editannouncement') {
            $active = ($env{'submenu'} eq 'editannouncement')?1:0;
            $tab_info_hashref = &messages_editannouncement_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
        }
        $active = ($env{'submenu'} eq 'rss')?1:0;
        $tab_info_hashref = &messages_rss_submenu($active);
        push(@sub_tabs,{%$tab_info_hashref});
    } elsif ($env{'menu'} eq 'print') {
#        $active = ($env{'submenu'} eq 'print')?1:0;
#        $tab_info_hashref = &partners_partners_submenu($active);
#        push(@sub_tabs,{%$tab_info_hashref});
#        $active = ($env{'submenu'} eq 'districts')?1:0;
#        $tab_info_hashref = &partners_districts_submenu($active);
#        push(@sub_tabs,{%$tab_info_hashref});
#        $active = ($env{'submenu'} eq 'locations')?1:0;
#        $tab_info_hashref = &partners_locations_submenu($active);
#        push(@sub_tabs,{%$tab_info_hashref});
#        $active = ($env{'submenu'} eq 'associates')?1:0;
#        $tab_info_hashref = &partners_associates_submenu($active);
#        push(@sub_tabs,{%$tab_info_hashref});
    }
    return(\@sub_tabs);
}
sub admin_tabs_menu {
    my @tabs_info;
    my $tab_info;
    my %fields;
    my $active;
    $active = ($env{'menu'} eq 'users')?1:0;
    %fields = ('secondary'=>&admin_sub_tabs());
    $tab_info = &Apache::Promse::tabbed_menu_item('admin','Users','users','roles',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});

    $active = ($env{'menu'} eq 'tj')?1:0;
    %fields = ('secondary'=>&admin_sub_tabs());
    $tab_info = &Apache::Promse::tabbed_menu_item('admin','Journal','tj','classes',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});


    $active = ($env{'menu'} eq 'partners')?1:0;
    %fields = ('secondary'=>&admin_sub_tabs());
    $tab_info = &Apache::Promse::tabbed_menu_item('admin','Partners','partners','districts',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});


    $active = ($env{'menu'} eq 'messages')?1:0;
    %fields = ('secondary'=>&admin_sub_tabs());
    $tab_info = &Apache::Promse::tabbed_menu_item('admin','Messages','messages','announcements',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'stats')?1:0;
    %fields = ('secondary'=>&admin_sub_tabs());
    $tab_info = &Apache::Promse::tabbed_menu_item('admin','Stats','stats','system',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'code')?1:0;
    %fields = ('secondary'=>&admin_sub_tabs());
    $tab_info = &Apache::Promse::tabbed_menu_item('admin','Code','code','grid',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'print')?1:0;
    %fields = ('secondary'=>'');
    $tab_info = &Apache::Promse::tabbed_menu_item('admin','Print','print','',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    return(&Apache::Promse::tabbed_menu_start(\@tabs_info));
}
sub build_journal_entry {
	my ($row) = @_;
	my %entry;
	$entry{'a'} = $$row{'date_taught'};
	$entry{'b'} = $$row{'class_duration'};
	$entry{'c'} = $$row{'percent_duration'};
	return (\%entry);
}
sub build_district_stats {
	my $rst;	
	my $reporting_days;
	my $qry = "SELECT users.FirstName, users.LastName, users.id, count(tj_journal.journal_id) AS entry_count,
					districts.district_name, districts.district_id, tj_journal.journal_id, locations.school,
					districts.date
					FROM users
					INNER JOIN user_locs ON user_locs.user_id = users.id
					INNER JOIN locations ON locations.location_id = user_locs.loc_id
					INNER JOIN districts ON districts.district_id = locations.district_id
					LEFT JOIN (tj_journal) ON tj_journal.user_id = users.id 
					WHERE users.id NOT IN (SELECT distinct userroles.user_id FROM userroles WHERE
								userroles.role_id = 6) AND
							users.id IN (SELECT DISTINCT userroles.user_id from userroles WHERE
									userroles.role_id = 7) AND
						districts.district_id = locations.district_id AND
						(districts.district_id = user_locs.loc_id OR
						user_locs.loc_id = locations.location_id )
						AND
						DAYOFWEEK(tj_journal.date_taught) <> 1 AND
						DAYOFWEEK(tj_journal.date_taught) <> 7 AND
						tj_journal.date_taught >= districts.date AND
						users.id = user_locs.user_id AND
						tj_journal.deleted = 0 
					GROUP BY district_id, users.id
					ORDER BY district_name, school, users.LastName, users.FirstName
	";
	$rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	my $date;
	my $max_entry_count = 0;
	my @entry_counts;
	my @district_summaries;
	my $district_name = '';
	my $district_id = 0;
	my $district_entries = 0;
	my $district_teachers = 0;
	my $district_active_teachers = 0;
	my $dead_beats = 0;
	my $need_work = 0;
	my $good_guys = 0;
	my $current_district = 0;
	my $first_row = 1;
	my %district_summary;
	while (my $row = $rst->fetchrow_hashref()) {
		if ($first_row) {
			$current_district = $$row{'district_id'};
			$district_name = $$row{'district_name'};
			$date = $$row{'date'};
			$district_id = $current_district;
			$first_row = 0;
		}
		if ($current_district ne $$row{'district_id'}) {
			%district_summary = ('total_entries'=>$district_entries,
								'total_teachers'=>$district_teachers,
								'active_teachers'=>$district_active_teachers,
								'dead_beats'=>$dead_beats,
								'need_work'=>$need_work,
								'date'=>$date,
								'good_guys'=>$good_guys,
								'district_name'=>$district_name,
								'district_id'=>$district_id);
			push @district_summaries, {%district_summary};
			$current_district = $$row{'district_id'};
			$district_name = $$row{'district_name'};
			$date = $$row{'date'};
			$district_id = $current_district;
			$district_entries = 0;
			$district_teachers = 0;
			$district_active_teachers = 0;
			$dead_beats = 0;
			$need_work = 0;
			$good_guys = 0;
		}
		$district_entries += $$row{'entry_count'};
		$district_teachers ++;
		if ($$row{'entry_count'} gt 0 ) {
			$reporting_days  = &compute_reporting_days($$row{'date'});
			$district_active_teachers ++;
			if ($$row{'entry_count'} / $reporting_days lt .1) {
				$dead_beats ++;
			} elsif ($$row{'entry_count'} / $reporting_days lt .75) {
				$need_work ++;
			} else {
				$good_guys ++;
			}
		} else {
			$dead_beats ++;
		}
		push @entry_counts, {%$row};
		$max_entry_count = ($max_entry_count < $$row{'entry_count'})?$$row{'entry_count'}:$max_entry_count;
	}
	%district_summary = ('total_entries'=>$district_entries,
						'total_teachers'=>$district_teachers,
						'active_teachers'=>$district_active_teachers,
						'dead_beats'=>$dead_beats,
						'need_work'=>$need_work,
						'good_guys'=>$good_guys,
						'district_name'=>$district_name,
						'date'=>$date,
						'district_id'=>$district_id);
	push @district_summaries, {%district_summary};
	
		$qry = "SELECT users.id, count(tj_journal.user_id) as user_count, tj_invoices.invoice_id,
						districts.district_name, tj_invoices.entries_required, tj_user_invoice.`status` as submitted,
						districts.district_id, temp_invoice_user_list.user_id as invoice2_ok
				FROM (users, tj_invoices, districts, user_locs)
				LEFT JOIN tj_journal ON tj_journal.user_id = users.id AND
					tj_journal.date_taught >= tj_invoices.work_start AND
					tj_journal.date_taught <= tj_invoices.work_end
				LEFT JOIN tj_user_invoice ON tj_user_invoice.user_id = users.id AND tj_user_invoice.invoice_id = tj_invoices.invoice_id
				LEFT JOIN temp_invoice_user_list ON users.id = temp_invoice_user_list.user_id AND tj_invoices.invoice_id = 2
				WHERE users.id IN 
					(SELECT userroles.user_id FROM userroles WHERE userroles.role_id = 7) AND
					users.id NOT IN (SELECT userroles.user_id FROM userroles WHERE userroles.role_id = 6) AND
					districts.district_id = user_locs.loc_id AND
					user_locs.user_id = users.id 
				GROUP BY districts.district_name, tj_invoices.invoice_id, users.id
				ORDER BY district_name, users.LastName";
		$rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my %invoice_stats;
		my %dstats = ('invoice1_ok' => 0,
				'invoice2_ok' => 0,
				'invoice1_submitted' => 0,
				'invoice2_submitted' => 0);
		my $invoice1_submitted = 0;
		my $invoice2_submitted = 0;
		my $invoice1_ok = 0;
		my $invoice2_ok = 0;
		$current_district = 0;
		my $done_one = 0;
		my $row;
		while ($row = $rst->fetchrow_hashref()) {
			if ($current_district ne $$row{'district_id'}) {
				if ($done_one) {
					$dstats{'invoice1_ok'} = $invoice1_ok;
					$dstats{'invoice2_ok'} = $invoice2_ok;
					$dstats{'invoice1_submitted'} = $invoice1_submitted;
					$dstats{'invoice2_submitted'} = $invoice2_submitted;
					$invoice_stats{$current_district} = {%dstats};
				} else {
					$done_one = 1;
				}
				$invoice1_ok = 0;
				$invoice2_ok = 0;
				$invoice1_submitted = 0;
				$invoice2_submitted = 0;
				%dstats = ('invoice1_ok' => 0,
						'invoice2_ok' => 0,
						'invoice1_submitted' => 0,
						'invoice2_submitted' => 0);
				$current_district = $$row{'district_id'};
			}
			if ($$row{'user_count'} > ($$row{'entries_required'} - 1)) {
				$invoice1_ok ++;
			}
			if ($$row{'invoice2_ok'}) {
				$invoice2_ok ++;
			}
			if ($$row{'submitted'}) {
				if ($$row{'invoice_id'} eq 1) {
					$invoice1_submitted ++;
				} elsif ($$row{'invoice_id'} eq 2) {
					$invoice2_submitted ++;
				}
			}
		}
		if ($done_one) {
			$dstats{'invoice1_ok'} = $invoice1_ok;
			$dstats{'invoice2_ok'} = $invoice2_ok;
			$dstats{'invoice1_submitted'} = $invoice1_submitted;
			$dstats{'invoice2_submitted'} = $invoice2_submitted;
			$invoice_stats{$current_district} = {%dstats};
		}
	return (\@district_summaries, \%invoice_stats, \@entry_counts);
}
sub cc_report {
    my ($r) = @_;
    $r->print("CC Report Here");
    my $qry = "SELECT cc_curricula.id AS curriculum_id, 
		cc_curricula.title as curriculum_title, cc_curricula.subject as subject
		FROM cc_curricula
		ORDER BY cc_curricula.subject, cc_curricula.title";
    my $rst = $env{'dbh'}->prepare($qry);
    $rst->execute();
    my @curricula;
    while (my $row = $rst->fetchrow_hashref()) {
        push (@curricula, $row);
    }
    # the row container 
    $r->print('<div style="text-align: left;
                           float: left;
                           padding: 0px;
                           margin: 0px;
                           overflow: hidden;
                           background-color: #ffdddd;
                           display: block;
                           width: 1200px;"
                           >');
    # Curriculum name column header
    $r->print('<div style="float: left;
                    display: block;
                    border-style: solid;
                    border-width: 1px;
                    border-color: #444444;
                    background-color: #ddffdd;
                    padding-top: 5px;
                    padding-left: 5px;
                    width: 200px;
                    height: 20px;">');
    $r->print('Curriculum');
    $r->print('</div>');
    # Column header for tagged lesson column
    $r->print('<div style="float: left;
                    display: block;
                    border-right-style: solid;
                    border-top-style: solid;
                    border-bottom-style: solid;
                    border-right-width: 1px;
                    border-top-width: 1px;
                    border-bottom-width: 1px;
                    border-right-color: #444444;
                    border-top-color: #444444;
                    border-bottom-color: #444444;
                    text-align: right;
                    background-color: #ddffdd;
                    padding-top: 5px;
                    padding-right: 5px;
                    width: 40px;
                    height: 20px;">');
    $r->print('#');
    $r->print('</div>');
    # Column header for percentage tagged column
    $r->print('<div style="float: left;
                    display: block;
                    border-right-style: solid;
                    border-top-style: solid;
                    border-bottom-style: solid;
                    border-right-width: 1px;
                    border-top-width: 1px;
                    border-bottom-width: 1px;
                    border-right-color: #444444;
                    border-top-color: #444444;
                    border-bottom-color: #444444;
                    text-align: right;
                    background-color: #ddffff;
                    padding-top: 5px;
                    padding-right: 5px;
                    width: 40px;
                    height: 20px;">');
    $r->print('%');
    $r->print('</div>');
    my $displayGrade;
    for (my $g = 0;$g < 9;$g++) {
        if ($g eq 0) {
            $displayGrade = 'K';
        } else {
            $displayGrade = $g;
        }
        # Each grade column header
        $r->print('<div style="float: left;
                display: block;
                border-right-style: solid;
                border-top-style: solid;
                border-bottom-style: solid;
                border-right-width: 1px;
                border-top-width: 1px;
                border-bottom-width: 1px;
                border-right-color: #444444;
                border-top-color: #444444;
                border-bottom-color: #444444;
                text-align: right;
                background-color: #ddddff;
                padding-right: 5px;
                padding-top: 5px;
                width: 86px;
                height: 20px;">');
        $r->print($displayGrade);
        $r->print('</div>');
    }
    $r->print('</div>');    
    foreach my $curriculum (@curricula) {
        my $row;
        $qry = "SELECT COUNT(*) as theme_count
                FROM cc_themes, cc_units, cc_curricula
                WHERE cc_curricula.id = cc_units.curriculum_id AND
                      cc_units.id = cc_themes.unit_id and
                      cc_curricula.id = $$curriculum{'curriculum_id'}
                 ";
        $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
        $row = $rst->fetchrow_hashref();
        my $theme_count = $$row{'theme_count'};
        if ($theme_count) {
            $qry = "SELECT COUNT(DISTINCT cc_pf_theme_tags.theme_id) as theme_count
                    FROM cc_pf_theme_tags
                    WHERE cc_pf_theme_tags.theme_id IN (SELECT cc_themes.id from cc_themes, cc_units  
                                            WHERE cc_themes.unit_id = cc_units.id AND
                                            cc_units.curriculum_id = $$curriculum{'curriculum_id'})";
            $rst = $env{'dbh'}->prepare($qry);
            $rst->execute();
            $row = $rst->fetchrow_hashref();
            my $tagged_count = $$row{'theme_count'};                           
            $r->print('<div style="text-align: left;
                                   float: left;
                                   padding: 0px;
                                   margin: 0px;
                                   overflow: hidden;
                                   background-color: #ffdddd;
                                   display: block;
                                   width: 1200px;"
                                   >');
            $r->print('<div style="float: left;
                            display: block;
                            background-color: #ddffdd;
                            border-right-style: solid;
                            border-left-style: solid;
                            border-bottom-style: solid;
                            border-right-width: 1px;
                            border-left-width: 1px;
                            border-bottom-width: 1px;
                            border-right-color: #444444;
                            border-left-color: #444444;
                            border-bottom-color: #444444;
                            padding-top: 5px;
                            padding-left: 5px;
                            width: 200px;
                            height: 25px;">');
            $r->print($$curriculum{'curriculum_title'});
            $r->print('</div>');
            $r->print('<div style="float: left;
                            display: block;
                            border-right-style: solid;
                            border-bottom-style: solid;
                            border-right-width: 1px;
                            border-bottom-width: 1px;
                            border-right-color: #444444;
                            border-bottom-color: #444444;
                            text-align: right;
                            padding-top: 5px;
                            background-color: #ddddff;
                            padding-right: 5px;
                            width: 40px;
                            height: 25px;">');
            $r->print($tagged_count);
            $r->print('</div>');
            $r->print('<div style="float: left;
                            display: block;
                            border-right-style: solid;
                            border-bottom-style: solid;
                            border-right-width: 1px;
                            border-bottom-width: 1px;
                            border-right-color: #444444;
                            border-bottom-color: #444444;
                            text-align: right;
                            background-color: #ddffff;
                            padding-top: 5px;
                            padding-right: 5px;
                            width: 40px;
                            height: 25px;">');
            if ($theme_count) {
                $r->print(int(($tagged_count / $theme_count) * 100).'%');
            } else {
                $r->print('N/A');
            }
            $r->print('</div>');
            for (my $grade = 0;$grade < 9;$grade++) {
                $qry = "SELECT COUNT(DISTINCT cc_pf_theme_tags.theme_id) as theme_count
                        FROM cc_pf_theme_tags
                        WHERE cc_pf_theme_tags.theme_id IN (SELECT cc_themes.id from cc_themes, cc_units  
                                                WHERE cc_themes.unit_id = cc_units.id AND
                                                cc_units.curriculum_id = $$curriculum{'curriculum_id'} AND
                                                cc_units.grade_id = $grade)";
                $rst = $env{'dbh'}->prepare($qry);
                $rst->execute();
                $row = $rst->fetchrow_hashref();
                $tagged_count = $$row{'theme_count'};                           
                $qry = "SELECT COUNT(*) as theme_count
                        FROM cc_themes, cc_units, cc_curricula
                        WHERE cc_curricula.id = cc_units.curriculum_id AND
                              cc_units.id = cc_themes.unit_id AND
                              cc_curricula.id = $$curriculum{'curriculum_id'} AND
                              cc_units.grade_id = $grade
                         ";
                $rst = $env{'dbh'}->prepare($qry);
                $rst->execute();
                $row = $rst->fetchrow_hashref();
                my $theme_count = $$row{'theme_count'};
                $r->print('<div style="float: left;
                                display: block;
                                border-right-style: solid;
                                border-bottom-style: solid;
                                border-right-width: 1px;
                                border-bottom-width: 1px;
                                border-right-color: #444444;
                                border-bottom-color: #444444;
                                text-align: right;
                                padding-top: 5px;
                                background-color: #ffffdd;
                                padding-right: 5px;
                                width: 40px;
                                height: 25px;">');
                if ($tagged_count) {
                    $r->print($tagged_count);
                } else {
                    $r->print('&nbsp;');
                }
                $r->print('</div>');
                $r->print('<div style="float: left;
                                display: block;
                                border-right-style: solid;
                                border-bottom-style: solid;
                                border-right-width: 1px;
                                border-bottom-width: 1px;
                                border-right-color: #444444;
                                border-bottom-color: #444444;
                                text-align: right;
                                padding-top: 5px;
                                background-color: #ddffff;
                                padding-right: 5px;
                                width: 40px;
                                height: 25px;">');
                if ($theme_count) {
                    $r->print(int(($tagged_count / $theme_count) * 100).'%');
                } else {
                    $r->print('&nbsp;');
                }
                $r->print('</div>');
            }
            $r->print('</div>');
        }
    }
}
sub compute_reporting_days {
	my ($begin_collection) = @_; 
	$begin_collection =~ s/\-//g;
	my $right_now = ParseDate('today');
	# my $begin_collection = ParseDate($begin_date);
	$begin_collection =~ /(....)(..)(..)/;
	my $year1 = $1;
	my $month1 = $2;
	my $day1 = $3;
	$right_now = ParseDate('today');
	$right_now =~ /(....)(..)(..)/;
	my $year2 = $1;
	my $month2 = $2;
	my $day2 = $3;
	print STDERR "\n Date::Calc::Delta_Days($year1, $month1, $day1, $year2, $month2, $day2) \n";
	my $reporting_days = Date::Calc::Delta_Days($year1, $month1, $day1, $year2, $month2, $day2);
	# rough conversion to remove weekend days
	$reporting_days = $reporting_days * (5/7);
	return ($reporting_days);
}
sub edit_admin_message {
    my ($r) = @_;
    my $message_id = $r->param('messageid');
    my $qry = "select * from messages where id = $message_id";
    my $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $r->print('<form method="post" action="admin">');
    
    $r->print('Start Date: ');
    &Apache::Promse::date_pulldown($r, 'start');
    $r->print('<br />End Date: ');
    &Apache::Promse::date_pulldown($r, 'end');
    $r->print('<br />Subject: <input size="40" type="text" name="subject" value="'.$$row{'subject'}.'" /><br />');
    $r->print('Message: <br /><textarea rows="8" cols="40" name="message">');
    $r->print($$row{'message'});
    $r->print('</textarea><br />');
    my %fields = ('action' => 'saveedit',
                  'menu' =>'messages',
                  'submenu' =>'editannouncement',
                  'messageid' => $message_id);
                  
    $r->print(&Apache::Promse::hidden_fields(\%fields));
    $r->print('<input type="submit" value="Save Edits" />');
    $r->print('</form>'."\n");
    return 'ok';
}
sub edit_lesson_html_framework {
	# This is the right one 11-4-12 (RB)
	my $return_html = qq~
	<div id="editLessonContainer">
		<div id="breadCrumbContainer">
			
		</div>
		<div id="statusMessage">&nbsp</div>
		<div id="confirmationMessage">
			<button onclick='cancelClicked(this)'>Cancel</button>
			<button onclick='confirmClicked(this)'>Delete Tag</button>
		</div>
		<div id="standardDescription" onclick="standardDescriptionClicked(this)">
		 
		</div>

		<div id="lessonDetails">
			<div id="lessonTitleContainer">
			<button id="previousLessonButton" lessonid="none"> <<< </button>
			<button id="nextLessonButton" lessonid="none"> >>> </button>
			<div id="lessonTitleDiv"></div>
			</div>
			<div id="lessonDescriptionContainer">
			</div>
			<div id="showLessonNoteButton" onclick="showLessonNoteButtonClicked(this)">Show Lesson Note</div>
			<div id="lessonNoteContainer" visible="false" onkeyup="setContainerDirty(this); "><textarea class="tagTextInput" placeholder="Enter lesson notes here"></textarea>
			</div>
			<div id="lessonTagContainer">
			</div>
			<button id="saveButton" onclick="saveButtonClicked(this)" >Save Changes</>
		</div>
			<div id="FilterContainer">
			<input id="standardfilter" type="text" value="" placeholder="Filter" onkeyup="filterUpdate()" size=31 />
			</div>
		<div id="selectorContainer">
			<div id="selectorItemsContainer">
			</div>
		</div>
	</div>
	<div id='hiddenContainer'>
	</div>
	~;
	
}
sub backup_routine {
	my ($r) = @_;
	my $qry = "SELECT t1.user_id, t7.class_id, t6.grade as class_grade, t1.duration as class_duration, 
		t8.grade as standard_grade, t1.date_taught, t2.framework_id as standard_id, t8.title as standard_code,
		t2.duration as percent_duration, t3.district_name, t5.loc_id as location_id, t3.district_id
			FROM (tj_journal t1)
			LEFT JOIN (tj_journal_topic t2) ON t1.journal_id = t2.journal_id
			LEFT JOIN (framework_items t8) ON (t8.id = t2.framework_id) 
			LEFT JOIN (tj_classes t6, tj_user_classes t7) ON (t6.class_id = t7.class_id and t7.user_id = t1.user_id )
			LEFT JOIN (districts t3, locations t4, user_locs t5) ON (t5.user_id = t1.user_id AND t3.district_id = t4.district_id AND t4.location_id = t5.loc_id)
			WHERE t2.deleted <> 1 AND t1.date_taught > ? and t1.date_taught < ?
			ORDER BY t2.framework_id, t3.district_name, t1.user_id, t7.class_id
			";
	my $rst = $env{'dbh'}->prepare($qry);
	# $rst->execute($start_date, $end_date);
	if (open OUT, "> /var/www/html/static_queries/tjjournal_summary.csv") {
		print STDERR "opened file for output \n";
	} else {
		print STDERR "unable to open file for output \n";
	}
	my @fields = ('user_id', 'class_id', 'class_grade', 'standard_grade', 'date_taught', 'standard_id','standard_code', 'percent_duration', 'district_id', 'location_id');
	foreach my $field_name(@fields) {
		print OUT $field_name . ',';
	}
	print OUT "\n";
	my %big_bucket;
	my %standards;
	my %districts;
	my %schools;
	my %classes;
	my %teachers;
	my @dates_taught;
	my $current_standard = 0;
	my $current_district = 0;
	my $current_school = 0;
	my $current_class = 0;
	my $current_teacher = 0;
	my $new_entry;
	my @entries;
	while (my $row = $rst->fetchrow_hashref()) {
		if ($$row{'framework_id'} != $current_standard) {
			$current_standard = $$row{'framework_id'};
			$teachers{$current_teacher} = [@entries];
			$classes{$current_class} = {%teachers};
			$schools{$current_school} = {%classes};
			$districts{$current_district} = {%schools}; 
			$big_bucket{$current_standard} = {%districts};
			%districts=();
			%schools=();
			%classes=();
			%teachers=();
			@entries = ();
			$current_district = $$row{'district_id'};
			$current_school = $$row{'location_id'};
			$current_class = $$row{'class_id'};
			$current_teacher = $$row{'user_id'};
			$new_entry = &build_journal_entry($row);
			push (@entries, [\%$new_entry]);
			
		} elsif ($$row{'district_id'} != $current_district) {
			$teachers{$current_teacher} = [@entries];
			$classes{$current_class} = {%teachers};
			$schools{$current_school} = {%classes};
			$districts{$current_district} = {%schools}; 
			%schools=();
			%classes=();
			%teachers=();
			@entries = ();
			$current_district = $$row{'district_id'};
			$current_school = $$row{'location_id'};
			$current_class = $$row{'class_id'};
			$current_teacher = $$row{'user_id'};
			$new_entry = &build_journal_entry($row);
			push (@entries, [\%$new_entry]);
		} elsif ($$row{'location_id'} != $current_school) {
			$teachers{$current_teacher} = [@entries];
			$classes{$current_class} = {%teachers};
			$schools{$current_school} = {%classes};
			%classes=();
			%teachers=();
			@entries = ();
			$current_school = $$row{'location_id'};
			$current_class = $$row{'class_id'};
			$current_teacher = $$row{'user_id'};
			$new_entry = &build_journal_entry($row);
			push (@entries, [\%$new_entry]);
		} elsif ($$row{'class_id'} != $current_class) {
			$teachers{$current_teacher} = [@entries];
			$classes{$current_class} = {%teachers};
			%teachers=();
			@entries = ();
			$current_class = $$row{'class_id'};
			$current_teacher = $$row{'user_id'};
			$new_entry = &build_journal_entry($row);
			push (@entries, [\%$new_entry]);
		} elsif ($$row{'user_id'} != $current_teacher) {
			$teachers{$current_teacher} = [@entries];
			%teachers=();
			@entries = ();
			$current_teacher = $$row{'user_id'};
			$new_entry = &build_journal_entry($row);
			push (@entries, [\%$new_entry]);
		} else {
			$new_entry = &build_journal_entry($row);
			push (@entries, [\%$new_entry]);
			
		}
		foreach my $field_name(@fields) {
			print OUT $$row{$field_name} . ',';
		}
		print OUT "\n";
	}
	$r->print('<a href="/static_queries/tjjournal_summary.csv">Raw data flat file</a><br />');
	$r->print('<a href="/static_queries/tjjournal_summary.json">Processed JSON</a><br />');
	close OUT;
	if (open OUT, "> /var/www/html/static_queries/tjjournal_summary.json") {
		print STDERR "opened file for output \n";
	} else {
		print STDERR "unable to open file for output \n";
	}
	print OUT JSON::XS::->new->pretty(0)->encode( \%big_bucket);
	close OUT;
	
}
sub get_admin_messages {
    my ($r) = @_;
    my $qry = "";
    # my $dbh = &db_connect();
    my $sth;
    my @return_array;
    $qry = "select * from messages where deleted<> 1 order by start_date, end_date";
    $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @return_array, {%$row};
    }
    return \@return_array;
}
sub get_curriculum_grades {
	my ($curriculum_id) = @_;
	my @grades;
	my $qry = "SELECT DISTINCT grade_id FROM cc_units 
			WHERE cc_units.curriculum_id = $curriculum_id
			ORDER BY grade_id";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	while (my $row = $rst->fetchrow_hashref()) {
		push (@grades, {%$row});
	}
	return (\@grades);
}
sub get_curriculum {
    # routine written to retrieve text for spell check
    # 2-14-15
    #
	my($curriculum_id) = @_;
	my @curriculum;
	my $qry = "SELECT cc_curricula.title as curriculum_title, cc_units.id as unit_id, cc_units.title as unit_title, cc_units.grade_id as grade,
	            cc_units.description as unit_description, cc_themes.id as lesson_id,
	            cc_themes.title as lesson_title, cc_themes.description as lesson_description
	            
	            FROM cc_curricula
	            LEFT JOIN cc_units ON cc_units.curriculum_id = cc_curricula.id
	            LEFT JOIN cc_themes ON cc_themes.unit_id = cc_units.id AND (cc_themes.eliminated IS NULL OR cc_themes.eliminated = 0)
				WHERE cc_curricula.id = $curriculum_id
				ORDER BY cc_units.grade_id, cc_units.sequence, cc_themes.sequence";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	while (my $row = $rst->fetchrow_hashref()) {
		push (@curriculum, {%$row});
	}
	# Now build structure for JSON object to be returned to client
	# removes lots of redundant info from database call
	my %curriculum;
	my $in_grade = 0;
	my @grades;
	my %grade;
	my $current_grade = 99;
	my @units;
	my %unit;
	my $current_unit;
	my @lessons;
	my %lesson;
	foreach my $row(@curriculum) {
	    if (! $in_grade) {
	        # do this only the first time through the loop
	        %curriculum = ('id'=> $curriculum_id,
	                    'title'=>$$row{'curriculum_title'});
	    } 
	    if ($current_grade ne $$row{'grade'}) {
	        if ($in_grade) {
	            # put away the old grade
	            $unit{'lessons'} = [@lessons];
	            push @units, {%unit};
	            $grade{'units'} = [@units];
	            push @grades, {%grade};
	            @lessons = ();
	            @units = ()
	        }
	        $in_grade = 1;
	        $current_grade = $$row{'grade'};
	        my $display_grade = $$row{'grade'} eq '0'?'K':$$row{'grade'};
	        $display_grade = $display_grade eq '9'?'HS':$display_grade;
	        %grade = ('id'=>$$row{'grade'},
	                'display'=>$display_grade);
	        %unit = ('id'=>$$row{'unit_id'},
	                 'title'=>$$row{'unit_title'},
	                 'description'=>$$row{'unit_description'});
	        $current_unit = $$row{'unit_id'};
	    } elsif ($current_unit ne $$row{'unit_id'}) {
            #put away old unit
            $unit{'lessons'} = [@lessons];
            push @units, {%unit};
	        %unit = ('id'=>$$row{'unit_id'},
	                 'title'=>$$row{'unit_title'},
	                 'description'=>$$row{'unit_description'});
	        $current_unit = $$row{'unit_id'};
            @lessons = ();
	    }
        %lesson = ('id'=>$$row{'lesson_id'},
                    'title'=>$$row{'lesson_title'},
                    'description'=>$$row{'lesson_description'});
        push @lessons, {%lesson};
       
    } 
    # out of loop, need to finish up
    if ($in_grade) {
        # put away the old grade
        $unit{'lessons'} = [@lessons];
        push @units, {%unit};
        $grade{'units'} = [@units];
        push @grades, {%grade};
        $curriculum{'grades'} = [@grades];
    } else {
        # no lessons returned so problem somewhere (wrong or missing curriculum_id?)
    }
	return(\%curriculum);
}

sub get_curriculum_grade_units {
	my($curriculum_id, $grade_id) = @_;
	my @units;
	my $qry = "SELECT cc_units.id, cc_units.title FROM cc_units
				WHERE cc_units.curriculum_id = $curriculum_id AND
					cc_units.grade_id = $grade_id 
				ORDER BY cc_units.sequence ";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	while (my $row = $rst->fetchrow_hashref()) {
		push (@units, {%$row});
	}
	return(\@units);
}
sub get_entry_counts {
	my ($district_id,$start_date) = @_;
	my $qry;
	my $item_id;
	my $count;
	my $scratch;
	my $sth;
	
	my $reporting_days = &compute_reporting_days($start_date);
	# district_id 107 = JCPS
	# district_id 91 = Erie
	# district_id 110 = Good Schools
	my $qry = "SELECT users.FirstName, users.LastName, users.id, users.username, count(tj_journal.journal_id) AS entry_count,
						districts.district_name, districts.district_id, tj_journal.journal_id, locations.school,
						districts.date
						FROM users
						INNER JOIN user_locs ON user_locs.user_id = users.id
						INNER JOIN locations ON locations.location_id = user_locs.loc_id
						INNER JOIN districts ON districts.district_id = locations.district_id
						LEFT JOIN (tj_journal) ON tj_journal.user_id = users.id 
						WHERE users.id NOT IN (SELECT distinct userroles.user_id FROM userroles WHERE
									userroles.role_id = 6) AND
								users.id IN (SELECT DISTINCT userroles.user_id from userroles WHERE
										userroles.role_id = 7) AND
							districts.district_id = locations.district_id AND
							(districts.district_id = user_locs.loc_id OR
							user_locs.loc_id = locations.location_id )
							AND
							districts.district_id = ? AND
							DAYOFWEEK(tj_journal.date_taught) <> 1 AND
							DAYOFWEEK(tj_journal.date_taught) <> 7 AND
							tj_journal.date_taught >= ? AND
							users.id = user_locs.user_id AND
							tj_journal.deleted = 0 
						GROUP BY district_id, users.id
						ORDER BY district_name, school, users.LastName, users.FirstName


	";

	$sth = $env{'dbh'}->prepare($qry);
	$sth->execute($district_id, $start_date);
	my @teacher_reports = ();
	while (my $row = $sth->fetchrow_hashref()) {
		push @teacher_reports,{%$row};
	}
	return(\@teacher_reports);
}
sub get_tj_districts {
    my $qry = "";
    my $sth;
    my @return_array;
    if ($env{'demo_mode'}) {
        $qry = "select district_id, district_alt_name as district_name from districts order by district_name";
    } else {
        $qry = "select district_id, district_name from districts WHERE 
district_id IN (SELECT distinct t3.district_id FROM users t1, user_locs t2, locations t3, userroles
WHERE t1.id = t2.user_id AND t2.loc_id = t3.location_id and userroles.user_id = t1.id AND userroles.role_id = 7 )
 order by district_name";
    }
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @return_array, {$$row{'district_name'}=>$$row{'district_id'}};
    }
	return(@return_array);
}
sub grid_edit_curriculum {
	my($r) = @_;
	my $curriculum_id = $r->param('curriculumid')?$r->param('curriculumid'):0;
	my $profile = &Apache::Promse::get_user_profile();
	# my ($crumbs,$depth) = &Apache::Promse::build_bread_crumbs($r);
	my $crumbs;
	my $depth;
	my $href_base = '"?token=' . $env{'token'} . ';menu=code;submenu=grid';
	$r->print(&edit_lesson_html_framework());
	$r->print(&Apache::Promse::lesson_tag_javascript($profile));
	$r->print(&Apache::Promse::lesson_tag_css());
	#$r->print($crumbs . "<br />");
	if ($depth eq 'district') {
		
	} elsif ($depth eq 'curriculum') {
	} elsif ($depth eq 'grade') {
	} elsif ($depth eq 'unit') {
		my $curriculum_id = $r->param('curriculumid');
		my $grade = $r->param('grade');
		my $unit_id = $r->param('unitid');
		my $lessons = &get_curriculum_grade_unit_lessons($unit_id);
		foreach my $lesson(@$lessons) {
			$r->print('<a href=' . $href_base . ';curriculumid=' . $curriculum_id . ';grade=' . $grade . ';unitid=' . $unit_id . 
					';lessonid=' . $$lesson{'id'} . '">' . 
					$$lesson{'title'} . '</a><br/>' . "\n");
		}
		
	} elsif ($depth eq 'lesson') {
		#$r->print('assign common core standard');
		#$r->print('<input id="standardfilter" type="text" value="" onkeyup="filterUpdate()" />');
		#$r->print('<div id="standardSelector" style="display:block;float:left;text-align:left;width:200px;height:500px;overflow:scroll;">');
		#my $standard_select = &Apache::Promse::build_select('standard',\@options,\@selected,$javascript,$width);
		#$r->print('</div>');
		#$r->print('<div id="standardDescription" class="standardDescription">Mouse over standard to see description</div>');
		#$r->print($standard_select);
	}
}
sub journal_comms {
	my ($r) = @_;
	$r->print(&journal_comms_css); 
	$r->print(&journal_comms_js);
	my $token = $env{'token'};
	# sets district to east lansing by default, else what was selected in form
	my $district_id = $r->param('districtid')?$r->param('districtid'):13;
	my $threshold = $r->param('threshold')?$r->param('threshold'):70;
	my $district_info = &Apache::Promse::get_district_info($district_id);
	my $start_date = $r->param('startdate')?$r->param('startdate'):$$district_info{'date'};
	my $reporting_days = &compute_reporting_days($start_date);
    my @districts = &get_tj_districts();
    my $district_selector = &Apache::Promse::build_select('districtid',\@districts,$district_id);
	if ($r->param('action') eq 'refresh') {
		# $r->print("<br \> action is refresh for district $district_id name from get district info is: $$district_info{'district_name'} and $$district_info{'date'} computed start date is $start_date <br \>");
	}
	my $output = qq~
	<div style="float:left">
	<form method="get">
	Start Date: <input type="text" name="startdate" value="" \> <br \>
	District: $district_selector <br \>
	Threshold: <input type="text" value="" name="threshold" \> <br \>
	<input type="submit" \>
	<input type="hidden" name="token" value="$token" \>
	<input type="hidden" name="menu" value="tj" \>
	<input type="hidden" name="action" value="refresh" \>
	<input type="hidden" name="submenu" value="comms">
	</form>
	</div>
	<div style="float:right">
	<form method="post">
	<textarea name="message" style="width:300px;height:90px;">Type your message here</textarea>
	<input type="submit" value="Email" \>
	<input type="hidden" name="token" value="$token" \>
	<input type="hidden" name="menu" value="tj" \>
	<input type="hidden" name="action" value="email" \>
	<input type="hidden" name="submenu" value="comms">
	</div>
	~;
	$r->print($output);
	$r->print('<div class="commsDisplay" style="clear:both">');
	my $teacher_reports = &get_entry_counts($district_id,$start_date);
	#$r->print("District: $$district_info('district_name'), Start Date: $start_date, Threshold: $threshold");
	$r->print("District: $$district_info{'district_name'}, Start Date: $start_date, Threshold: $threshold" );
	foreach my $row (@$teacher_reports) {
		my $percent_done = ($$row{'entry_count'} / $reporting_days);
		if ($percent_done < ($threshold / 100)) {
			$r->print('<div class="commsRow">');
			$r->print('<input type="checkbox" name="send" value="' . $$row{'id'} . '" checked />');
			$r->print("$$row{'LastName'}, $$row{'FirstName'} $$row{'username'} $$row{'school'} - " . sprintf("%.2f", $percent_done));
			$r->print('</div>');
		}
	}
	$r->print("</form>");
	$r->print("<br \> total days will be $reporting_days");
	$r->print('</div>'); # close the commsDisplay div
}
sub journal_comms_css {
	my $css = qq~
	<style>
	div.commsDisplay {
		text-align:left;
		background-color:#f0f0f0;
	}
	div.commsRow {
		background-color:#eeeeee;
	}
	div.altCommsRow {
		background-color:#cccccc;
	}
	div.statusMesssage {
		background-color:#ffdddd;
		float:right;
		display:block;
		width:300px;
		height:100px;
	}
	</style>
	~;
	return($css);
}
sub journal_comms_js{
	my $js = qq~
	<script type="text/javascript">
	function toggleAll() {
		alert("toggling");
	}
	</script>
	~;
	return($js);
}
sub journal_stats_excel_friendly {
	my ($r) = @_;
	my $date_filter = '2013-08-19';
	my ($district_summaries, $invoice_stats, $entry_counts) = &build_district_stats($date_filter);
	my $reporting_days = &compute_reporting_days($date_filter);
	foreach my $district_summary (@$district_summaries) {
		my $expected_total = $reporting_days * $$district_summary{'total_teachers'};
		my $percent_active_total;
		my $percent_total;
		my $district_invoice_stats = $$invoice_stats{$$district_summary{'district_id'}};
		my $district_invoice1_ok = $$district_invoice_stats{'invoice1_ok'};
		my $district_invoice2_ok = $$district_invoice_stats{'invoice2_ok'};
		my $district_invoice1_submitted = $$district_invoice_stats{'invoice1_submitted'};
		my $district_invoice2_submitted = $$district_invoice_stats{'invoice2_submitted'};
		if ($$district_summary{'active_teachers'}) {
			my $expected_active_total = $reporting_days * $$district_summary{'active_teachers'};
			$percent_total = sprintf ('%.1f',($$district_summary{'total_entries'}/$expected_total) * 100);
			$percent_active_total = sprintf ('%.1f', ($$district_summary{'total_entries'}/$expected_active_total) * 100);
		} else {
			$percent_active_total = 'na';
		}
		$r->print($$district_summary{'district_name'} . ",\n");
		$r->print($$district_summary{'total_entries'} . ",\n");
		$r->print($$district_summary{'total_teachers'} . ",\n");
		$r->print(sprintf ('%.1f', $$district_summary{'active_teachers'} / $$district_summary{'total_teachers'} * 100) . ",\n");
		$r->print(sprintf ('%.1f', $$district_summary{'good_guys'} / $$district_summary{'total_teachers'} * 100) . ",\n");
		$r->print(sprintf ('%.1f', $$district_summary{'need_work'} / $$district_summary{'total_teachers'} * 100) . ",\n");
		$r->print(sprintf ('%.1f', $$district_summary{'dead_beats'} / $$district_summary{'total_teachers'} * 100) . ",\n");
		$r->print($district_invoice1_ok . ",\n");
		$r->print($district_invoice1_submitted . ",\n");
		$r->print($district_invoice2_ok . ",\n");
		$r->print($district_invoice2_submitted . "<br>");
	}
}
sub journal_summaries {
	my ($r) = @_;
	my $rst;
	my $start_date = $r->param('start_date')?$r->param('start_date'):'2014-01-01';
	my $end_date = $r->param('start_date')?$r->param('end_date'):'2014-02-01';
    my @districts = &get_tj_districts();
	unshift @districts,{'Select District'=>'0'};
	my $district_id = $r->param('districtid')?$r->param('districtid'):13;
    my $district_selector = &Apache::Promse::build_select('districtid',\@districts,0,'onchange="onDistrictSelect()"');
	$r->print ('<div id="statusMessage" style="background-color:#ffdddd;
		padding:3px;
		float:right;
		display:block;
		width:300px;
		height:50px">Status Message</div>');
	$r->print('<div id="controlPanel" style="float:left;background-color:#ddffdd;padding:5px;display:block;width:275px;text-align:left" >');
	$r->print($district_selector);
	$r->print('<img style="float:right" height="15" width="15" helpid="help04" onmouseover="mouseoverhelp(this)" onmouseout="mouseouthelp()" src="../images/helpsmall.png" />');
	$r->print('<div style="display:block;width:100%;text-align:center;" id="classselector">Select A District Above</div>');
	$r->print ('<span style="display:block;float:left;width:100px;height:20px;text-align:right;">Start Date:</span> <input type="text" id="startdate" name="start_date" value="2013-09-01" style="float:right;width:80px;" onchange="classSelectorChange()" /><br />');
	$r->print ('<span style="display:block;clear:both;float:left;width:100px;height:20px;text-align:right" onchange="classSelectorChange()">End Date: </span> <input type="text" id="enddate" name="end_date" value="2014-05-01" style="float:right;width:80px;" onchange="classSelectorChange()" />');
	$r->print ('<span style="display:block;clear:both;float:left;width:100px;height:20px;text-align:right" onchange="classSelectorChange()">Completion %: </span> <input type="text" id="threshold" name="threshold" value="75" style="float:right;width:80px;" onchange="classSelectorChange()"/>');
	$r->print ('<input type="hidden" name="action" value="retrieve" />');
	$r->print ('<input type="hidden" name="token" value="' . $env{'token'} . '" />');
	$r->print ('<input type="hidden" name="menu" value="tj" />');
	$r->print ('<input type="hidden" name="submenu" value="summaries" />');
	$r->print ('<button style="display:block;width:100px;" id="updateButton" type="button" onclick="buttonClicked()">Update Table</button>');
	$r->print('</div>');
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
sub journal_stats {
	my ($r) = @_;
	$r->print('<a href="admin?menu=tj;action=excelfriendly;token=' . $env{'token'} . '">Excel Friendly District Summary</a>');
	# first figure how many reporting days there should be
	# let's get some aggregate data
	my $reporting_days;
	my $time_stamp_filter = "'2013-09-03 11:19:01'";
	my $qry = "SELECT count(tj_journal.journal_id) AS total FROM tj_journal
					WHERE DAYNAME(tj_journal.date_taught) != 'Saturday' AND
						DAYNAME(tj_journal.date_taught) != 'Sunday' AND
						tj_journal.user_id NOT IN (select userroles.user_id from userroles where role_id = 6) AND
						tj_journal.date_taught > ? ";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute('2000-01-01');
	my $row = $rst->fetchrow_hashref();
	my $total_entries = $$row{'total'};
	$r->print($total_entries . " total entries from ");
	$qry = "SELECT COUNT(DISTINCT user_id) AS num_users FROM tj_journal";
	$rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	$row = $rst->fetchrow_hashref();
	my $total_contributors = $$row{'num_users'};
	$r->print($total_contributors . " individuals");
	$qry = "SELECT COUNT(users.id) AS idle_users FROM users, userroles
			WHERE users.id NOT IN (SELECT DISTINCT user_id from tj_journal) AND
					users.id NOT IN (SELECT user_id from userroles where role_id = 6)
					AND userroles.role_id = 7 AND
					userroles.user_id = users.id";
	$rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	$row = $rst->fetchrow_hashref();
	my $idle_users = $$row{'idle_users'};
	$r->print("(With $idle_users having no entries.)");
	$qry = "SELECT tj_journal.time_stamp FROM tj_journal WHERE 
		time_stamp > $time_stamp_filter AND
		DAYNAME(tj_journal.date_taught) != 'Saturday' AND
			DAYNAME(tj_journal.date_taught) != 'Sunday' ORDER BY time_stamp";
	$rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	my $day = 0;
	my $hour = 0;
	my $minute;
	my $second;
	my $daily_entries = 0;
	my $hourly_entries = 0;
	my %day_bins;
	my %hour_bins;
	my $current_day = 0;
	my $current_hour = 0;
	my $done_one = 0;
	my $min_date = 99999999999;
	my $max_date = 0;
	my $min_hour = 25;
	my $max_hour = 0;
	my $max_daily_entries = 0;
	my $max_hourly_entries = 0;
	my $light_color = '#eeeeee';
	my $dark_color = '#dddddd';
	my $row_color = $light_color;
	my $max_entry_count = 0;
	my $district_name = '';
	my $district_id = 0;
	my $district_entries = 0;
	my $district_teachers = 0;
	my $district_active_teachers = 0;
	my $dead_beats = 0;
	my $need_work = 0;
	my $good_guys = 0;
	my $current_district = 0;
	my $first_row = 1;
	print STDERR "\n about " . localtime(time) . " to building stats \n";
	my ($district_summary, $invoice_stats, $entry_counts) = &build_district_stats();
	print STDERR "\n about " . localtime(time) . " back from stats \n";
	my $bar_width = 200;
	# was $bar_width / $max_entry_count, now percentage so / 100
	my $x_scale = $bar_width / 100;
	$r->print('<div style="display:block;overflow:hidden;text-align:center;width:950px;border-style:solid;border-color:#cccccc;">');
	$r->print(qq~
	<style type="text/css">
		div.summary_row {
			display:block;
			overflow:hidden;
			width:100%;
			height:30px;
			font-size:20px;
		}
		span.col_1 {
			display:block;
			overflow:hidden;
			width:100px;
			float:left;
			border-style:solid;
			border-color:#eeeeee;
		}
		span.col_2 {
			display:block;
			overflow:hidden;
			width:50px;
			float:left;
			border-style:solid;
			border-color:#eeeeee;
		}
	</style>
~);
	$r->print('<div class="summary_row" style="text-align:center">');
	$r->print('<span class="col_1">District</span><span class="col_1">Entries</span>');
	$r->print('<span class="col_1">Teachers</span><span class="col_1">% Active</span>');
	$r->print('<span class="col_2" style="background-color:#57c197">&nbsp;%</span><span class="col_2" style="background-color:#e7e54b">&nbsp;%</span>');
	$r->print('<span class="col_2" style="background-color:#d85330";>&nbsp;%</span>');
	$r->print('<span class="col_2" style="background-color:#eeeeee";>OK-1</span>');
	$r->print('<span class="col_2" style="background-color:#eeeeee";>Sub-1</span>');
	$r->print('<span class="col_2" style="background-color:#eeeeee";>OK-2</span>');
	$r->print('<span class="col_2" style="background-color:#eeeeee";>Sub-2</span>');
	print STDERR "\n about " . localtime(time) . " to loop \n";
	
	$r->print('</div>');
	foreach my $district_summary (@$district_summary) {
		$reporting_days  = &compute_reporting_days($$district_summary{'date'});
		my $expected_total = $reporting_days * $$district_summary{'total_teachers'};
		my $percent_active_total;
		my $percent_total;
		my $district_invoice_stats = $$invoice_stats{$$district_summary{'district_id'}};
		my $district_invoice1_ok = $$district_invoice_stats{'invoice1_ok'};
		my $district_invoice1_submitted = $$district_invoice_stats{'invoice1_submitted'};
		my $district_invoice2_ok = $$district_invoice_stats{'invoice2_ok'};
		my $district_invoice2_submitted = $$district_invoice_stats{'invoice2_submitted'};
		my $district_id = $$district_summary{'district_id'};
		if ($$district_summary{'active_teachers'}) {
			my $expected_active_total = $reporting_days * $$district_summary{'active_teachers'};
			$percent_total = sprintf ('%.1f',($$district_summary{'total_entries'}/$expected_total) * 100);
			$percent_active_total = sprintf ('%.1f', ($$district_summary{'total_entries'}/$expected_active_total) * 100);
		} else {
			$percent_active_total = 'na';
		}
		$r->print('<div class="summary_row">');
		$r->print('<span class="col_1" onclick="alert(\'clicked\')">' . $$district_summary{'district_name'} . "</span> \n");
		$r->print('<span class="col_1">' . $$district_summary{'total_entries'} . "</span> \n");
		$r->print('<span class="col_1">' . $$district_summary{'total_teachers'} . "</span> \n");
		$r->print('<span class="col_1">' . sprintf ('%.1f', $$district_summary{'active_teachers'} / $$district_summary{'total_teachers'} * 100) . "</span> \n");
		$r->print('<span class="col_2">' . sprintf ('%.1f', $$district_summary{'good_guys'} / $$district_summary{'total_teachers'} * 100) . "</span> \n");
		$r->print('<span class="col_2">' . sprintf ('%.1f', $$district_summary{'need_work'} / $$district_summary{'total_teachers'} * 100) . "</span> \n");
		$r->print('<span class="col_2">' . sprintf ('%.1f', $$district_summary{'dead_beats'} / $$district_summary{'total_teachers'} * 100) . "</span> \n");
		$r->print('<span class="col_2">' . $district_invoice1_ok . "</span> \n");
		$r->print('<span class="col_2">' . $district_invoice1_submitted . "</span> \n");
		$r->print('<span class="col_2">' . $district_invoice2_ok . "</span> \n");
		$r->print('<span class="col_2">' . $district_invoice2_submitted . "</span> \n");
		$r->print('</div>' . "\n");
	}
	$r->print('</div>'); # end the district summary table
	$r->print('<div style="text-align:left;margin-left:5px;font-size:18px">');
	$r->print("Journal Users (with entries) <br />");
	my $current_district = 0;
	my $current_school = '';
	foreach my $row (@$entry_counts) {
		if ($$row{'district_id'} ne $current_district) {
			$reporting_days  = &compute_reporting_days($$row{'date'});
			$current_district = $$row{'district_id'};
			$r->print($$row{'district_name'} . "<br>");
		}
		if ($$row{'school'} ne $current_school) {
			$current_school = $$row{'school'}; 
			$r->print($$row{'school'} . "<br>");
		}
		if ($$row{'entry_count'}) {
			$row_color = ($row_color eq $light_color)?$dark_color:$light_color;
			$r->print('<div style="width:600px;height:22px;display:block;background-color:' . $row_color . ';">');
			$r->print('<span style="font-size:16px;float:left;display:block;width:175px;">');
			$r->print('<a href="admin?menu=tj;action=userdetail;userid=' . $$row{'id'} . ';token=' . $env{'token'} . '">' . $$row{'LastName'} . '&nbsp;</a>');
			$r->print( '</span>');
			$r->print('<span style="font-size:16px;display:block;float:left;width:175px;">' . $$row{'FirstName'} . "&nbsp;</span>");
			$r->print('<span style="font-size:16px;display:block;float:left;width:248px">');
			$r->print('<span style="font-size:16px;display:block;float:left;height:22px;width:' . $bar_width . 'px">');
			my $percent_done = ($$row{'entry_count'} / $reporting_days);
				my $display_width =  $percent_done * $x_scale * 100;
				my $display_color;
				if ($percent_done lt .25) {
					$display_color = '#d85330';
				} elsif ($percent_done lt .75) {
					$display_color = '#e7e54b';
				} else {
					$display_color = '#57c197';
				}
				$r->print('<span style="float:left;display:block;background-color:'. $display_color . ';margin-top:2px;height:18px;width:' . $display_width . 'px">&nbsp;</span>');
			$r->print('</span>');
			$r->print('<span style="float:left;width:30px;display:block">' . $$row{'entry_count'} . '/' . sprintf('%.0f', $reporting_days) . '</span');
			$r->print('</span>');
			$r->print('</div>');
		}
	}
	$r->print('</div>');
	
}
sub lesson_tag_framework_html {
	my $html = qq~
<div id="lessonContainer">
	<div id="lessonTitleContainer">
	</div>
	<div id="lessonDescriptionContainer">
	</div>
	something in here
	<div id="selectorContainer">
		<input id="standardfilter" type="text" value="" onkeyup="filterUpdate()" />
		<div id="selectorItemsContainer">
		</div>
	</div>
	<div id="standards">
		standards are here
	</div>
</div>	
	
~;
	
	return($html);
}
sub messages_announcements_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Sys Msgs','messages','announcements',$active,'tabBottom',undef);
    return($tab_info);
}
sub messages_addannouncement_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','New Message','messages','addannouncement',$active,'tabBottom',undef);
    return($tab_info);
}
sub messages_rss_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','RSS','messages','rss',$active,'tabBottom',undef);
    return($tab_info);
}
sub messages_editannouncement_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Edit Message','messages','editannouncement',$active,'tabBottom',undef);
    return($tab_info);
}
sub schedule_form {
    my ($r) = @_;
    my $output;
    $r->print('<form name="form1" method="post" action="admin">');
    $r->print('<div class="scheduleForm">');
    
    $r->print('<div class="datesContainer">');
    
    $r->print('<div class="dateGroup">');
    $r->print('<div class="dateLabel">');
    $r->print('Start Date:');
    $r->print('</div>'); # end dateLabel
    $r->print('<div class="datePulldown">');
    &Apache::Promse::date_pulldown($r, 'start');
    $r->print('</div>'); # end datePulldown
    $r->print('</div>'); # end dateGroup
    
    $r->print('<div class="dateGroup">');
    $r->print('<div class="dateLabel">');
    $r->print('End Date:');
    $r->print('</div>'); # end dateLabel
    $r->print('<div class="datePulldown">');
    &Apache::Promse::date_pulldown($r, 'end');
    $r->print('</div>'); # end datePulldown
    $r->print('</div>'); # end dateGroup

    $r->print('</div>'); # end datesContainer

    $r->print('<div class="recipientContainer">');
    $r->print('<strong>Recipients:</strong><br />');
    $r->print('<div class="recipientRow">');
    $r->print('<div class="recipientLabel">Teacher</div>');
    $r->print('<div class="recipientCheckbox">');
    $r->print('<input type="checkbox" name="recipient" value="Teacher" /> ');
    $r->print('</div>');
    $r->print('</div>'); #end recipientRow
    $r->print('<div class="recipientRow">');
    $r->print('<div class="recipientLabel">Assoc</div>');
    $r->print('<div class="recipientCheckbox">');
    $r->print('<input type="checkbox" name="recipient" value="Apprentice" /> ');
    $r->print('</div>');
    $r->print('</div>'); #end recipientRow
    $r->print('<div class="recipientRow">');
    $r->print('<div class="recipientLabel">Mentor</div>');
    $r->print('<div class="recipientCheckbox">');
    $r->print('<input type="checkbox" name="recipient" value="Mentor" /> ');
    $r->print('</div>');
    $r->print('</div>'); #end recipientRow
    $r->print('<div class="recipientRow">');
    $r->print('<div class="recipientLabel">Editor</div>');
    $r->print('<div class="recipientCheckbox">');
    $r->print('<input type="checkbox" name="recipient" value="Editor" /> ');
    $r->print('</div>');
    $r->print('</div>'); #end recipientRow
    $r->print('<div class="recipientRow">');
    $r->print('<div class="recipientLabel">Admin</div>');
    $r->print('<div class="recipientCheckbox">');
    $r->print('<input type="checkbox" name="recipient" value="Administrator" /> ');
    $r->print('</div>');
    $r->print('</div>'); #end recipientRow
    $r->print('</div>'); # end recipientContainer
    
    $r->print('<div>');
    $r->print('Subject:');
    $r->print('</div>');
    $r->print('<div>');
    $r->print('<input name="subject" type="text" value="" size="40" />');
    $r->print('</div>');
    $r->print('<div>');
    $r->print('Message:');
    $r->print('</div>');
    $r->print('<div>');
    $r->print('<textarea name="message" cols="55" rows="10"></textarea>');
    $r->print('</div>');
    
    $r->print('</div>'); # end scheduleForm
    my %fields = ('menu'=>'messages',
                  'submenu'=>'addannouncement',
                  'action'=>'addmessage');
    $r->print(&Apache::Promse::hidden_fields(\%fields));
    $r->print('<input type="submit" name="Submit" value="Save Message" />'); 
    $r->print('</form>');   
}
sub update_admin_message {
    my ($r) = @_;
    my %fields;
    my %id_field;
    $id_field{'id'}=$r->param('messageid');
    $fields{'subject'}=&Apache::Promse::fix_quotes($r->param('subject'));
    $fields{'message'}=&Apache::Promse::fix_quotes($r->param('message'));
    $fields{'start_date'}="'".$r->param('startyear')."/".$r->param('startmonth')."/".$r->param('startday')."'";
    $fields{'end_date'}="'".$r->param('endyear')."/".$r->param('endmonth')."/".$r->param('endday')."'";
    &Apache::Promse::update_record("messages",\%id_field,\%fields);
    return 'ok'    
}
sub users_roles_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Roles','users','roles',$active,'tabBottom',undef);
    return($tab_info);
}
sub users_add_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Add','users','add',$active,'tabBottom',undef);
    return($tab_info);
}
sub users_domains_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Domains','users','domains',$active,'tabBottom',undef);
    return($tab_info);
}
sub users_edituser_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Edit User','users','edituser',$active,'tabBottom',undef);
    return($tab_info);
}
sub partners_districts_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Districts','partners','districts',$active,'tabBottom',undef);
    return($tab_info);
}
sub partners_locations_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Locations','partners','locations',$active,'tabBottom',undef);
    return($tab_info);
}
sub partners_partners_submenu {
    # all partner processing handled with Flash application
    #my ($active) = @_;
    #my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Partners','partners','partners',$active,'tabBottom',undef);
    #return($tab_info);
}
sub partners_associates_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('admin','Associates','partners','associates',$active,'tabBottom',undef);
    return($tab_info);
}
sub check_text {
    my ($text_to_check) = @_;
    #my @words = split(/(\w+)/g,$text_to_check);
    my @words = $text_to_check =~ m/(\w+)/g;
    my $qry = 'SELECT COUNT(*) as found FROM lexicon WHERE word = ?';
    my $rst = $env{'dbh'}->prepare($qry);
    my %output;
    my %words_found;
    my @bad_words;
    foreach my $word(@words) {
        my $word_to_check = uc($word);
        $rst->execute($word_to_check);
        my $row = $rst->fetchrow_hashref();
        if (! $$row{'found'}) {
            if (! $words_found{$word_to_check}) {
                push @bad_words, $word;
                $words_found{$word_to_check} = 1;
            }
        }
    }
    $output{'badwords'} = [@bad_words];
    return(\%output);
}
sub spell_check {
    my ($r) = @_;
    my $curriculum_id = $r->param('curriculumid');
    my $qry;
    my $rst;
    my $token = $env{'token'};
    my $script = qq~
    <script type="text/javascript">
        var token = "$token";
        var lessons = Array();
        var units = Array();
        var grades = Array();
        \$('body').on('click', 'div.correctCheckWord', function() {
            \$(this).find('span').show();
        });
        \$('body').on('focus','textarea',function() {
            console.log('textarea focus');
            \$('#saveButton').show();
        });
        \$('body').on('click','#saveButton',function() {
            var unitTitle = \$('#unitTitle').val();
            var unitDescription = \$('#unitDescription').val();
            var lessonTitle = \$('#lessonTitle').val();
            var lessonDescription = \$('#lessonDescription').val();
            if (unitTitle != unit.title || unitDescription != unit.description) {
                \$("#statusMessage").text("Updating unit . . .");
                var record = Object();
                record.tablename = 'cc_units';
                record.keyFields = {id:unit.id};
                record.fields = {title:unitTitle,
                                 description:unitDescription};
                recordString = JSON.stringify(record);
                \$.ajax({
                    type:"POST",
                    url:'admin',
                    data:{token:token,
                            record:recordString,
                            action:'updaterecord',
                            ajax:'ajax'}
                })
                .done(function( data ) {
                    \$("#statusMessage").text("Updated unit.");
                });
                
            }
            if (lessonTitle != lesson.title || lessonDescription != lesson.description) {
                \$("#statusMessage").text("Updating lesson . . .");
                var record = Object();
                record.tablename = 'cc_themes';
                record.keyFields = {id:lesson.id};
                record.fields = {title:lessonTitle,
                                 description:lessonDescription};
                recordString = JSON.stringify(record);
                \$.ajax({
                    type:"POST",
                    url:'admin',
                    data:{token:token,
                            record:recordString,
                            action:'updaterecord',
                            ajax:'ajax'}
                })
                .done(function( data ) {
                    \$("#statusMessage").text("Updated lesson.");
                });
                
            }
            
           \$('#saveButton').hide();
        });
        \$('body').on('click', 'div.spellCheckWord', function() {
            var word = \$(this).attr('badword');
            addToDictionary(word);
            \$(this).parent().remove();
            var remainingButtons = \$('#correctionContainer').children().length;
            if (remainingButtons === 0) {
                console.log('remaining buttons count is: ' + remainingButtons);
                //processNext();
            }
        });
        function spellCheck(curriculumOBJ) {
            grades = curriculumOBJ['grades'];
            units = Array();
            lessons = Array();
            numGrades = grades.length;
            processNext();
        }
        function processNext () {
            if (lessons.length > 0) {
                lesson = lessons.shift();
                \$("#lessonTitle").val(lesson['title']);
                \$("#lessonDescription").val(lesson['description']);
                checkText(lesson['title'] + ' ' + lesson['description']);
            } else if (units.length > 0) {
                unit = units.shift();
                lessons = unit['lessons'];
                lesson = lessons.shift();
                \$("#unitTitle").val(unit['title']);
                \$("#unitDescription").val(unit['description']);
                \$("#lessonTitle").val(lesson['title']);
                \$("#lessonDescription").val(lesson['description']);
                checkText(unit['title'] + ' ' + unit['description'] + ' ' + lesson['title'] + ' ' + lesson['description']);
            } else if (grades.length > 0) {
                grade = grades.shift();
                \$("#grade").text(grade['display']);
                units = grade['units'];
                unit = units.shift();
                lessons = unit['lessons'];
                lesson = lessons.shift();
                \$("#unitTitle").val(unit['title']);
                \$("#unitDescription").val(unit['description']);
                \$("#lessonTitle").val(lesson['title']);
                \$("#lessonDescription").val(lesson['description']);
                checkText(unit['title'] + ' ' + unit['description'] + ' ' + lesson['title'] + ' ' + lesson['description']);
            } else {
                \$("#statusMessage").text('No more lessons');
                // all done now
            }
        }
        function addToDictionary(word) {
            \$("#statusMessage").text("Adding " + word + " to dictionary . . . ");
            var record = Object();
            record.tablename = 'lexicon';
            record.fields = {word:word};
            recordString = JSON.stringify(record);
            \$.ajax({
                type:"GET",
                url:'admin',
                data:{token:token,
                        record:recordString,
                        action:'insertrecord',
                        ajax:'ajax'}
            })
            .done(function( data ) {
                \$("#statusMessage").text("Added " + word + " to dictionary.");
            });
            
        }
        function updateRecord(record) {
            
            \$.ajax({
                type:"GET",
                url:'admin',
                data:{token:token,
                        record:record,
                        action:'updaterecord',
                        ajax:'ajax',
                        texttocheck:textToCheck},
            })
            .done(function( data ) {
                //badWords = msg['badwords'];
                //showBadWords(badWords);
            });
            
            
        }
        function checkText(textToCheck) {
            \$("#statusMessage").text("Checking text . . . ");
            \$.ajax({
                type:"GET",
                url:'admin',
                data:{token:token,
                        action:'checktext',
                        ajax:'ajax',
                        texttocheck:textToCheck},
            })
            .done(function( msg ) {
                \$("#statusMessage").text("Back from checking text.");
                badWords = msg['badwords'];
                showBadWords(badWords);
            });
            
        }
        function correctWord() {
            
        }
        function showBadWords(badWords) {
            badWordText = '';
            \$("#correctionDiv").empty();
            var wordCount = 0;
            var correctionDiv = '<div id="correctionContainer">';
            while (word = badWords.shift()) {
                wordCount ++;
                correctionDiv +=    '<div class="correctionRow">';
                correctionDiv +=        '<div style="cursor:pointer;" class="spellCheckWord" badword="'+ word + '">' + word + '</div>';
                correctionDiv +=    '</div>';
            }
            correctionDiv += '</div>';
            \$("#correctionDiv").append(correctionDiv);

            if (wordCount === 0) {
                processNext();
            }
        }
        function nextClicked() {
            processNext();
        }
        function curriculumClicked(curriculumID) {
            \$("#statusMessage").text("Retrieving curriculum . . . ");
            \$("#unitTitle").text('');
            \$("#unitDescription").text('');
            \$("#lessonTitle").text('');
            \$("#lessonDescription").text('');
            \$("#badwords").empty();
            \$.ajax({
                type:"GET",
                url:'admin',
                data:{token:token,
                        action:'getcurriculum',
                        ajax:'ajax',
                        curriculumid:curriculumID},
            })
            .done(function( msg ) {
                \$("#statusMessage").text("Retrieved curriculum");
                //console.log('back from getcurriculum');
                //console.log(msg);
                \$("#curriculumTitle").text(msg['title'] + ' (' + curriculumID + ')');
                spellCheck(msg);
            });
            
        }
    </script>
    ~;
    $r->print($script);
    #
    #   retrieve curriculum and display
    #
    $qry = "SELECT cc_curricula.id as curriculum_id, cc_curricula.title
            FROM cc_curricula, cc_curricula_districts
            WHERE cc_curricula.id = cc_curricula_districts.curriculum_id AND cc_curricula_districts.district_id = 129
            ORDER BY cc_curricula.title";
    $rst = $env{'dbh'}->prepare($qry);
    $rst->execute();
    $r->print('<div style="float:left;text-align:left;display:block;width:340px;height:600px;overflow:scroll;background-color:#eeffee">');
    while (my $row = $rst->fetchrow_hashref()) {
        $r->print('<div class="curriculumRow"  curriculumid="' . $$row{'curriculum_id'} . '" onclick="curriculumClicked('. $$row{'curriculum_id'}.')">' .$$row{'title'} . '</div>');
    }
    #
    #   Screen layout
    #
    $r->print('</div>');
    $r->print('<div id="lessonForm" class="lessonForm">');
    $r->print('<div id="statusMessage" class="statusMessage">Select a curriculum</div>');
    $r->print('<div id="infoPanel" >');
    $r->print('<span id="curriculumTitle"></span><br />');
    
    $r->print('</div>');
    $r->print('Grade - <span id="grade"></span><br />');
    $r->print('<textarea id="unitTitle" class="spChTitleInput"></textarea>');
    $r->print('<textarea id="unitDescription" class="spChDescriptionInput"></textarea>');
    $r->print('<textarea id="lessonTitle" class="spChTitleInput"></textarea>');
    $r->print('<textarea id="lessonDescription" class="spChDescriptionInput"></textarea>');
    $r->print('<div class="spChButton" onclick="nextClicked()">Next</div>');
    $r->print('<div class="spChButton" style="display:none;" id="saveButton">Save</div>');
    $r->print('<div id="correctionDiv"></div>');
    $r->print('</div>');
    if ($curriculum_id) { 
        $r->print("in the spell check");
        $qry = "SELECT cc_units.id as unit_id, cc_units.title as unit_title, cc_units.description as unit_description, 
                cc_themes.id as lesson_id, cc_themes.title as lesson_title, cc_themes.description as lesson_description 
                  FROM cc_units, cc_themes
                  WHERE cc_units.id = cc_themes.unit_id AND
                  cc_units.curriculum_id = $curriculum_id";
        $rst = $env{'dbh'}->prepare($qry);
        $rst->execute();
    }
    
}
sub tj_admin_stats {
	my ($r) = @_;
	$r->print("handling tj_admin Stats here.");
	my $qry = "SELECT t1.id, t1.username, t1.FirstName, t1.LastName, districts.district_name, locations.school 
FROM users t1
LEFT JOIN user_locs ON t1.id = user_locs.user_id
LEFT JOIN locations ON user_locs.loc_id = locations.location_id
LEFT JOIN districts ON locations.district_id = districts.district_id
WHERE districts.district_name IS NOT NULL AND
t1.username like '%@%'
ORDER BY districts.district_name, locations.school, t1.LastName, t1.FirstName";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	while (my $row = $rst->fetchrow_hashref()) {
		$r->print($$row{'LastName'} . ', ' . $$row{'FirstName'} . '<br />');
	}
	my $output = qq~
	<canvas id="myCanvas" width="250" height="100" style="border:1px solid #cccccc;">
	Something typed on canvas.
	</canvas>
	~;
	$r->print($output);
	return();
}
sub tj_user_detail {
	my ($r) = @_;
	my $user_detail = &Apache::Journal::get_user_log($r, $r->param('userid'),1);
	my $log_entries = $$user_detail{'userlog'};
	$r->print("STARTING SUMMARY<BR>");
	my $user_summary = &Apache::Journal::get_user_summary($r, $r->param('userid'));
	$r->print($user_summary);
	$r->print("<br>FINISHED SUMMARY<br>");
	$r->print(scalar @$log_entries . ' log/topic entries found <br>');
	# %journal_entry keys:'journalid',	'datetaught', 'classid', 'classname', 'framework_id', 
	# 'frameworktitle', 'duration', 'background', 'pages', 'notes'
	@$log_entries; #date ascending now
	$r->print('<div style="text-align:left;">');
	$r->print('<div>');
	$r->print('<span style="float:left;width:90px;text-align:center;">Date</span>');
	$r->print('<span style="float:left;width:100px;text-align:center;">Class</span>');
	$r->print('<span style="float:left;width:300px;text-align:center;">Topic</span>');
	$r->print('<span style="float:left;width:120px;text-align:center;">Activities</span>');
	$r->print('<span style="float:left;width:80px;text-align:center;">Duration</span>');
	$r->print('<span>Background</span><span>Pages</span><span>Notes</span>');
	$r->print('</div>');
	foreach my $topic_entry(@$log_entries) {
		if ($$topic_entry{'datetaught'} gt '2012-09-03') {
			$r->print('<div style="clear:both;">');
		$r->print('<span style="float:left;width:90px;text-align:left;">' . $$topic_entry{'datetaught'} . "</span>");
		$r->print('<span style="float:left;width:100px;text-align:left;">' . $$topic_entry{'classname'} . "</span>");
		$r->print('<span style="float:left;width:300px;text-align:left;">' . $$topic_entry{'frameworktitle'} . "</span>");
		$r->print('<span style="float:left;width:120px;text-align:left;">');
		if ($$topic_entry{'activity'}) {
			my $activities = $$topic_entry{'activity'};
			my $first_one = 1;
			foreach my $activity (@$activities) {
				if ($first_one) {
					$first_one = 0;
				} else {
					$r->print(', ');
				}
				$r->print($$activity{'activity_name'});
			}
		} else {
			$r->print('&nbsp;');
		}
		$r->print('</span>');
		$r->print('<span style="float:left;width:80px;text-align:left;">' . $$topic_entry{'duration'} . "</span>");
		$r->print('<span style="float:left;width:100px;text-align:left;">');
		$r->print($$topic_entry{'background'} . "(bg), ");
		$r->print($$topic_entry{'pages'} . "(pg), ");
		$r->print($$topic_entry{'notes'} . "(nb)");
		$r->print('</span>');
			$r->print('</div>');
		}
	}
	$r->print('</div>');
}
sub updateRecord {
    my ($r) = @_;
    my $record = JSON::XS::->new->utf8->decode($r->param('record'));
    my $table_name = $$record{'tablename'};
    my $fields = $$record{'fields'};
    my $keyFields = $$record{'keyFields'};
    &Apache::Promse::update_record_new($table_name,\%$keyFields,\%$fields);
    my %output = ('status'=>'finished');
    return (\%output);
}
sub insertRecord {
    my ($r) = @_;
    my $record = JSON::XS::->new->utf8->decode($r->param('record'));
    my $table_name = $$record{'tablename'};
    my $fields = $$record{'fields'};
    my %keyFields = ();
    &Apache::Promse::insert_record($table_name,\%$fields,0);
    my %output = ('status'=>'finished');
    return (\%output);
}
sub handler {
    my $r = new CGI;
    &Apache::Promse::validate_user($r);
    my $auth_token = &Apache::Promse::authenticate('Administrator');
    my $alert_message;
    if ($auth_token ne 'ok') {
        &Apache::Promse::top_of_page($r);
        print "Not authorized for this page<br>";
        &Apache::Promse::footer($r);
    } else {
        if ($r->param('ajax') eq 'ajax') {
            my $output;
            if ($r->param('action') eq 'getcurriculum') {
                $output = get_curriculum($r->param('curriculumid'));
            } elsif ($r->param('action') eq 'checktext') {
                my $text = $r->param('texttocheck');
                $output = check_text($text);
            } elsif ($r->param('action') eq 'insertrecord') {
                $output = insertRecord($r);
            } elsif ($r->param('action') eq 'updaterecord') {
                $output = updateRecord($r);
            }
			print $r->header(-type => 'application/json',
	                    -expires => 'now');
			$r->print(JSON::XS::->new->pretty(1)->encode( \%$output));
			return('ok');			
        }
        &Apache::Promse::top_of_page_menus($r, 'admin',&admin_tabs_menu());
        if ($env{'menu'} eq 'users') {
            if ($env{'submenu'} eq 'edituser') {
                if ($env{'action'} eq 'update') {
                    my $msg = &Apache::Promse::update_user($r);
                    if ($msg =~ m/Duplicate/) {
                        $r->print('The username you entered already exists');
                    } else {
                        &Apache::Promse::update_user_roles($r);
                    }
                    $r->print($msg."<br />");
                }
                &Apache::Authenticate::add_vpd_user_form($r);
            } elsif ($env{'submenu'} eq 'roles') {
                if (($env{'action'} eq 'Active') || ($env{'action'} eq 'Inactive')) {
                    $alert_message = "Deleting user";
                    $alert_message .= &Apache::Promse::activate_user($r);
                } elsif ($env{'action'} eq 'update') {
                    my @roles;
                    #only update if a role was set
                    if ($r->param('role')) {
                        &Apache::Promse::update_user_roles($r, $r->param('userid'));
                    } else {
                        print "No role selected<br>";
                    }
                }
                &Apache::Promse::admin_form($r);
            } elsif ($env{'submenu'} eq 'add') {
                if ($env{'action'} eq 'saverecord') {
                    my $msg = &Apache::Authenticate::save_new_vpd_record($r);
                    if ($msg =~ m/Duplicate/) {
                        $r->print('Tried to save the VPD record, but the username already exists in the database.<br />');
                        $r->print('Use the BACK button on your browser and try another username.<br />');
                    }
                }
                &Apache::Authenticate::add_vpd_user_form($r);    
            } elsif ($env{'submenu'} eq 'domains') {
				if ($r->param('action') eq 'adddomain') {
					my %fields = ('domain_name'=> "'" . $r->param('domain') . "'",
								'enabled'=>1);
					&Apache::Promse::save_record('ok_domains',\%fields,0);
				}
				$r->print('handling domains here');
				my $token = $env{'token'};
				my $qry = "SELECT id, domain_name, enabled FROM ok_domains ORDER BY domain_name";
				my $rst = $env{'dbh'}->prepare($qry);
				$rst->execute();
				$r->print('<div style="text-align:left">');
				$r->print('following are existing domain names<br />');
				while (my $row = $rst->fetchrow_hashref()) {
					$r->print($$row{'domain_name'} . "<br />");
				}
				$r->print('</div>'); 
				$r->print('<div style="text-align:left">');
				my $form_html = qq~
				<form method="get" action="">
					<input name="domain" type="test" />
					<input type="submit" />
					<input type="hidden" name="token" value="$token">
					<input type="hidden" name="menu" value="users">
					<input type="hidden" name="action" value="adddomain">
					<input type="hidden" name="submenu" value="domains">
				</form>
				~;
				$r->print($form_html);
				$r->print('</div>');
			}
        } elsif ($env{'menu'} eq 'tj') {
			if ($env{'action'} eq 'insertclass') {
				my $class_name = $r->param('classname');
				my $grade =$r->param('grade');
				my $notes = $r->param('notes')?$r->param('notes'):'';
				my %fields = ('class_name' => &Apache::Promse::fix_quotes($class_name),
							'grade' => $r->param('grade'),
							'notes' => &Apache::Promse::fix_quotes($notes));
				&Apache::Promse::save_record('tj_classes', \%fields);
			} elsif ($env{'action'} eq 'userdetail') {
				&tj_user_detail($r);
			} elsif ($env{'action'} eq 'excelfriendly') {
				&journal_stats_excel_friendly($r);
			}
			if ($env{'submenu'} eq 'add') {
				&add_class($r);
			} elsif ($env{'submenu'} eq 'classes') {
				my $classes = &Apache::Promse::get_classes($r);
				my @tj_teachers = &Apache::Promse::get_tj_teachers($r);
				foreach my $teacher(@tj_teachers) {
					# $r->print($$teacher{'lastname'});
				}
				foreach my $class(@$classes) {
					$r->print($$class{'class_name'} . '<br />')
				}
			} elsif ($env{'submenu'} eq 'summaries') {
				&journal_summaries($r);
			} elsif ($env{'submenu'} eq 'comms'){
				&journal_comms($r);
			} elsif ($env{'submenu'} eq 'stats') {
				&journal_stats($r);
			}
        } elsif ($env{'menu'} eq 'messages') {
            if ($env{'action'} eq 'addmessage') {
                my %fields;
                my $table = "messages";
                my $recipients = join (',',$r->param('recipient'));
                $fields{'recipients'} = "'".$recipients."'";
                $fields{'start_date'} = "'".$r->param('startyear')."/".$r->param('startmonth')."/".$r->param('startday')."'";
                $fields{'end_date'} = "'".$r->param('endyear')."/".$r->param('endmonth')."/".$r->param('endday')."'";
                $fields{'subject'} = &Apache::Promse::fix_quotes($r->param('subject'));
                $fields{'message'} = &Apache::Promse::fix_quotes($r->param('message'));
                $fields{'deleted'} = 0;
                $r->print(&Apache::Promse::save_record($table, \%fields));
                
            } elsif ($env{'action'} eq 'delete') {
                &Apache::Promse::delete_admin_message($r);
            } elsif ($env{'action'} eq 'saveedit') {
                &update_admin_message($r);
            }
            if ($env{'submenu'} eq 'announcements') {
                &admin_messages($r);
            } elsif ($env{'submenu'} eq 'addannouncement') {
                &schedule_form($r);
            } elsif ($env{'submenu'} eq 'editannouncement') {
                &edit_admin_message($r);
            }
        } elsif ($env{'menu'} eq 'print') {
        my $row = &Apache::Promse::get_user_location();
        my $district_id = $$row{'district_id'};
        my $district_name = $$row{'district_name'};
        my $token = $env{'token'};
        my $path = &Apache::Flash::get_URL_path($r);
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
    			'width', '550',
    			'height', '400',
    			'src', '../flash/printCurriculum',
    			'quality', 'high',
    			'pluginspage', 'http://www.macromedia.com/go/getflashplayer',
    			'align', 'middle',
    			'play', 'true',
    			'loop', 'true',
    			'scale', 'showall',
    			'wmode', 'window',
    			'devicefont', 'false',
    			'id', 'printCurriculum',
    			'bgcolor', '#ffffff',
    			'name', 'printCurriculum',
    			'menu', 'true',
    			'allowFullScreen', 'false',
    			'allowScriptAccess','sameDomain',
    			'movie', '../flash/printCurriculum',
    			'salign', ''
    			); //end AC code
    	}
    </script>
    <noscript>
    	<object classid="clsid:d27cdb6e-ae6d-11cf-96b8-444553540000" codebase="http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=9,0,0,0" width="550" height="400" id="printCurriculum" align="middle">
    	<param name="allowScriptAccess" value="sameDomain" />
    	<param name="allowFullScreen" value="false" />
    	<param name="movie" value="printCurriculum.swf" /><param name="quality" value="high" /><param name="bgcolor" value="#ffffff" />	<embed src="http://vpddev.educ.msu.edu/flash/printCurriculum.swf" quality="high" bgcolor="#ffffff" width="550" height="400" name="printCurriculum" align="middle" allowScriptAccess="sameDomain" allowFullScreen="false" type="application/x-shockwave-flash" pluginspage="http://www.macromedia.com/go/getflashplayer" />
    	</object>
    </noscript>
    </body>
    </html>
    ~;    
        $r->print($output);
            
        } elsif ($env{'menu'} eq 'partners') {
            &Apache::Flash::promse_admin_html($r);
#            &Apache::Promse::partner_menu($r);
#            if ($env{'submenu'} eq 'partners') {
#                &Apache::Promse::partners($r);
#            } elsif ($env{'submenu'} eq 'districts') {
#                &Apache::Promse::edit_districts($r); 
#            } elsif ($env{'submenu'} eq 'locations') {
#                &Apache::Promse::manage_user_locations($r);
#            } elsif ($env{'submenu'} eq 'associates') {
#                &Apache::Promse::associates($r);
#            } elsif ($env{'submenu'} eq 'editpartner') {
#                &Apache::Promse::partner_forms($r);
#            }
        } elsif ($env{'menu'} eq 'code') {
			if ($env{'submenu'} eq 'grid') {
				&grid_edit_curriculum($r);
			} elsif ($env{'submenu'} eq 'flash') {
            	&Apache::Flash::promse_admin_code_html($r);
			} elsif ($env{'submenu'} eq 'spell') {
			    &spell_check($r);
			}
        } elsif ($env{'menu'} eq 'stats') {
            if ($env{'submenu'} eq 'system') {
                &Apache::Promse::admin_stats($r);
			} elsif ($env{'submenu'} eq 'cc') {
                &cc_report($r);
            } elsif ($env{'submenu'} eq 'tj') {
				&tj_admin_stats($r);
            }
        } elsif ($env{'target'} eq 'mail') {
            $r->print('Sending test email');
            &Apache::Promse::mail_test($r);
        } elsif ($env{'target'} eq 'editlocations') {
            &Apache::Promse::edit_locations($r);
        } elsif ($env{'target'} eq 'editdistricts') {
            &Apache::Promse::edit_districts($r); 
        }
        &Apache::Promse::footer;
    }
}
1;
