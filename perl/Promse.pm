#
# $Id: Promse.pm,v 1.151 2009/02/01 18:03:58 banghart Exp $
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
package Apache::Promse;
#test
use Apache::Authenticate;
# use Apache::Flash;
use DBI;
use GD;
use Math::Trig qw(great_circle_distance deg2rad acos);
use XML::DOM;
use Net::LDAP;
use Net::HTTP;
use Net::SMTP;
use Mail::Sendmail;
use JSON::XS;

use strict;
# define globals here
require Exporter;
our @ISA = qw(Exporter);
our %env;
our %config;
use vars qw(%env %config);
our @EXPORT = qw(%env %config);
my $earth_radius = 3959;
open IN, '< /etc/httpd/conf/promse.conf';
while (<IN>) {
    $_=~ /^(.*?)(,)(.*?)$/;
    $config{$1}=$3;
}
my $timeout;
my $upload_dir;
sub logthis {
    my $message=shift;
    # my $execdir=$perlvar{'lonDaemons'};
    my $now=time;
    my $local=localtime($now);
    print STDERR "$local ($$): $message\n";
    if (open(my $fh,">>/var/www/logs/promse.log")) {
	    print $fh "$local ($$): $message\n";
	    close($fh);
    } else {
        print STDERR "Couldn't open promse.log message: $message \n $! \n";
    }
    return 1;
}
sub group_admin_menu {
    my $r = @_;
    $r->print('<a href="home?token='.$env{'token'}.'&amp;target=groups&amp;menu=display">[Display Groups]</a>');
    return 1;
}
sub tabbed_menu_item {
    my($page, $title, $menu, $submenu, $active, $top_or_bottom, $add_fields) = @_;
    my %tab_info;
    if ($active) {
        %tab_info = ('url' => '#',
                    'class'=> 'class="'.$top_or_bottom.'Active"',
                    'label'=> $title);
        if ($$add_fields{'secondary'}) {
            $tab_info{'secondary'} = $$add_fields{'secondary'};
        }
    } else {
        my %fields = ('token'=>$env{'token'},
                    'menu'=>$menu,
                    'submenu'=>$submenu);
        if ($add_fields) {
            foreach my $key (keys(%$add_fields)) {
                if ($key ne 'secondary') {
                    $fields{$key} = $$add_fields{$key};
                }
            }
        }
        %tab_info = ('url' => &Apache::Promse::build_url($page,\%fields),
                    'class'=> 'class="'.$top_or_bottom.'"',
                    'label'=> $title);
    }
    return(\%tab_info);
}

sub tabbed_menu_start {
    my ($tab_info) = @_;
    # $tab_info is array reference
    # each element in array is a hash reference consisting of:
    # {'url'} - not enclosed in double quotes (")
    # {'class'} - eg.,' class="active" ' (or empty string)
    # {'label'} - String
    my $line_width = 1080; #same width as wrapperColumn *** Modified to be wrapperColumn - 2
    my $output = qq~
<div id="tabNavWrapper">
    <div class="tabTopContainer">
        ~;
    my $secondary_menu = "";
    my $sec_tabs;
    foreach my $tab(@$tab_info) {
        $output .= '<div class="tabTopSeparator">&nbsp;</div>';
        $output .= '<div '.$$tab{'class'}.'><a style="padding-top: 2px;" href="' . $$tab{'url'}.'" '.
        ' >'.$$tab{'label'}.'</a></div>'."\n";
        # insert code for "secondary" menu if $tab{'secondary'} exists
        if ($$tab{'secondary'}) {
            $sec_tabs = ($$tab{'secondary'});
            foreach my $sec_tab(@$sec_tabs) {
                $secondary_menu .= '<div '.$$sec_tab{'class'}.'><a style="padding-top: 2px;" href="' . $$sec_tab{'url'}.'">'.$$sec_tab{'label'}.'</a></div>'."\n";
            }
        }
        $line_width -= 126;
    }
    $output .=  '<div style="width: '.$line_width.'px;" class="tabTopLineRight">&nbsp;</div>';
    $output .= '</div>'."\n"; # close the tab top container
    $output .= '<div class="tabBottomContainer">'."\n";
    $output .= $secondary_menu;
    $output .= '</div>'."\n"; # close tab Bottom Container
    $output .= '</div>'."\n"; # close newTabNavWrappr
    return($output);
}

sub tabbed_menu_end {
    my $output;
    my $display_name = &username_to_display_name($env{'username'});
    $output .= qq~
~;   
    return($output);
}

sub group_document_add {
    my($r) = @_;
    my $upload_dir = "/var/www/html/groupdocs";
    my $upload_filehandle = $r->upload('groupdoc');
    my $file_name = $r->param('groupdoc');
    my $user_id = &token_to_userid($r->param('token'));
    # have to decide if this is a URL or a file to upload
    # we'll assume a URL if doc_name begins with 'http'
    # save the file or url to the database
    if ($r->param('groupurl')) {
        $file_name = $r->param('groupurl');
        my %fields = ('location' => &fix_quotes('web'),
                            'doc_name' => &fix_quotes($file_name),
                            'description' => &fix_quotes($r->param('description')),
                            'user_id' => $user_id,
                            'date' => ' NOW() ',
                            'group_id' => $env{'group_id'}
                            );
        &save_record('group_docs',\%fields,1);
    } else {
        my %fields = ('location' => &fix_quotes($upload_dir.'/'.$file_name),
                            'doc_name' => &fix_quotes($file_name),
                            'description' => &fix_quotes($r->param('description')),
                            'user_id' => $user_id,
                            'date' => ' NOW() ',
                            'group_id' => $env{'group_id'}
                            );
        my $record_id = &save_record('group_docs',\%fields,1);
        $file_name =~ /^(.+)(\..+$)/;
        $file_name = $1.'_'.$record_id.$2;
        open UPLOADFILE, ">$upload_dir/$file_name";
        binmode UPLOADFILE;
        while ( <$upload_filehandle> ) { 
            print UPLOADFILE;
        } 
        close UPLOADFILE;
    }
    return 1;
}
sub group_documents {
    my ($r) = @_;
    if ($env{'action'} eq 'adddocument') {
        &group_document_add($r);
    }
    &group_menu($r);
    &group_document_menu($r);
    if ($env{'submenu'} eq 'uploaddoc') {
        my %fields = ('action'=>'adddocument',
                        'submenu'=>'documents',
                        'menu'=>'groups',
                        'groupid'=>$env{'group_id'}
                        );
        $r->print('<form method="post" action="" ENCTYPE="multipart/form-data">');
        $r->print('<fieldset>');
        $r->print('<label>Document description:<textarea name="description" rows="6" cols="40"></textarea></label>');
        $r->print('<label>Click Browse to select a file to upload. <INPUT TYPE="file" NAME="groupdoc" /></label>');
        $r->print(&hidden_fields(\%fields));
        $r->print('<input type="submit" name="upload" value="Upload Document" />');
        $r->print('</fieldset>');
        $r->print('</form>');
        $r->print('<div><strong>Or:</strong></div>');
        $r->print('<form method="post" action="" >');
        $r->print('<fieldset>');
        $r->print('<label>Website description:<textarea name="description" rows="6" cols="40"></textarea></label>');
        $r->print('<label> <INPUT TYPE="text" NAME="groupurl" size="70"/></label>');
        $r->print(&hidden_fields(\%fields));
        $r->print('<input type="submit" name="upload" value="Upload Web Site" />');
        $r->print('</fieldset>');
        $r->print('</form>');
    } else {
        &group_docs_browse($r);
    }
    return 1;
}
sub group_docs_browse {
    my ($r) = @_;
    my $group_id = $env{'group_id'};
    my $user_roles = &get_user_roles();
    my $highlight = 0;
    my $td_style;
    my $qry;
    my $sth;
    my $url;
    if ($env{'action'} eq 'saveedit') {
        my %id_fields = ('id'=>$r->param('docid'));
        my %fields = ('description'=>&fix_quotes($r->param('description')));
        &update_record('group_docs',\%id_fields,\%fields);
    } elsif ($env{'action'} eq 'editdoc') {
        $qry = "select * from group_docs where id = ".$r->param('docid');
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        my %fields = ('target'=>'groups',
                        'menu'=>'documents',
                        'action'=>'saveedit',
                        'groupid'=>$r->param('groupid'),
                        'docid'=>$r->param('docid')
                        );
        $r->print('<form method="post" action="home"');
        $r->print('<textarea rows=14 cols=70 name="description">');
        $r->print($$row{'description'});
        $r->print('</textarea>');
        $r->print(&hidden_fields($r, \%fields));
        $r->print('<input type="submit" value="Update Document Description"');
        $r->print('</form>');
    }
    $qry = "select * from group_docs where group_id = $group_id order by doc_name";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<table><tr><th>Document Name</th><th>Description</th></tr>');
    while (my $row = $sth->fetchrow_hashref()) {
        if ($highlight eq 1) {
            $highlight = 0;
            $td_style = 'docDescription';
        } else {
            $highlight = 1;
            $td_style = 'docDescriptionHighlight';
        }
        if ($$row{'location'} eq 'web') {
            $url = $$row{'doc_name'};
            $r->print('<tr><td id="'.$td_style.'"><a href="'.$url.'" target="_blank">'.$$row{'doc_name'}.'</a>');
        } else {
            my $serial = $$row{'id'};
            $url = $$row{'location'};
            $url =~ /^(.+)(\..+$)/;
            $url = $1.'_'.$serial.$2;
            $url =~ s|^/var/www/html/||;
            $r->print('<tr><td id="'.$td_style.'"><a href="../'.$url.'" target="_blank">'.$$row{'doc_name'}.'</a>');
        }
        if ($user_roles =~ m/Admin/) {
            my %fields = ('target'=>'groups',
                            'groupid'=>$r->param('groupid'),
                            'token'=>$env{'token'},
                            'menu'=>'documents',
                            'docid'=>$$row{'id'},
                            'action'=>'editdoc');
            my $url = &build_url('home',\%fields);
            $r->print(' [<a href="'.$url.'">Edit</a>]');
        }
        $r->print('</td>');
        $r->print('<td id="'.$td_style.'">'.&text_to_html($$row{'description'}).'</tr>');
    }
    $r->print('</table>');
    return 1;
}
sub update_group {
    my($r) = @_;
    my $group_id = $env{'group_id'};
    my %fields;
    my %id;
    $id{'group_id'} = $group_id;
    $fields{'name'} = &fix_quotes($r->param('name'));
    $fields{'description'} = &fix_quotes($r->param('description'));
    &update_record('groups',\%id,\%fields);    
    return 1;
}
sub add_group_member {
    my($r) = @_;
    my $group_id = $r->param('groupid');
    my $added_id = $r->param('addeduser');
    my $qry;
    $qry = "insert into group_members (group_id, user_id) values ($group_id, $added_id)";
    $env{'dbh'}->do($qry);
    return 1;
}
sub remove_group_member {
    my($r) = @_;
    my $group_id = $r->param('groupid');
    my $removed_id = $r->param('removeduser');
    my $qry;
    $qry = "delete from group_members where group_id = $group_id and user_id = $removed_id";
    $env{'dbh'}->do($qry);
    return 1;
}
sub edit_group_members {
    my($r) = @_;
    my $group_id = $r->param('groupid');
    my $alpha_filter = $r->param('alphafilter');
    if ($r->param('addeduser')) {
        &add_group_member($r);
    }
    if ($r->param('removeduser')) {
        &remove_group_member($r);
    }
    my %fields;
    $fields{'token'} = $env{'token'};
    $fields{'submenu'} = 'membership';
    $fields{'action'} = 'adduser';
    $fields{'menu'} = 'groups';
    $fields{'groupid'} = $group_id;
    unless ($alpha_filter) {
        $alpha_filter = 'A';
    }
    $alpha_filter .= '%';
    my $qry = "select id, lastname, firstname from users where id <> ALL ";
    $qry.= "(select user_id from group_members where group_id = ".$group_id." ) and lastname like '".$alpha_filter."' order by lastname, firstname";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    &alpha_menu($r,'home',\%fields);
    $r->print('<h4>Select Group Members</h4>'."\n");
    $r->print('<div class="groupNameContainer">'."\n");
    $r->print('All Users'."\n");
    $r->print('Name to Add to Group'."\n");
    $r->print('<div class="groupMemberScroller">'."\n");
    my $url = 'home?';
    foreach my $key (keys(%fields)) {
       $url .= $key.'='.$fields{$key}.'&amp;';
    }
    while (my $row = $sth->fetchrow_hashref) {
        $r->print('<div class="groupMemberRow">');
        $r->print('<div class="groupMemberLink">');
        $r->print('<a href="'.$url.'addeduser='.$$row{'id'}.'">Add</a>');
        $r->print('</div>');
        $r->print('<div class="groupMemberName">');
        print $$row{'firstname'}." ".$$row{'lastname'}."\n";
        $r->print('</div>');
        $r->print('</div>');
    }
    $r->print('</div></div>'."\n");

    $qry = "select id, lastname, firstname from users, group_members where group_id = ".$group_id." and id = user_id order by lastname, firstname";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<div class="floatLeft">');
    $r->print('<div class="addressScroller">'."\n");
    $r->print('<table><caption>Current group members</caption>'."\n");
    $r->print('<thead><tr><th scope="col">Select</th>'."\n");
    $r->print('<th scope="col">Name to Remove</th>'."\n");
    $r->print('</tr>'."\n");
    $r->print('</thead>'."\n");
    $r->print('<tbody>'."\n");
    $fields{'action'} = 'removeuser';
    $url = 'home?';
    foreach my $key (keys(%fields)) {
       $url .= $key.'='.$fields{$key}.'&amp;';
    }
    if ($sth->rows) {
        while (my $row = $sth->fetchrow_hashref) {
            print '<tr><td scope="row"><a href="'.$url.'removeduser='.$$row{'id'}.'">Delete</a></td>';
            print '<td>'.$$row{'firstname'}." ".$$row{'lastname'}."</td></tr>";
        }
    } else {
        print "<span>There are no names in this group</span>";
    }
    $r->print('<tr class="bottomRow"><td colspan="2"></td></tr>'."\n");
    $r->print('</tbody></table>'."\n");
    $r->print('</div></div>'."\n");
    $r->print('<div class="clear"></div>');
    return 1;
}
sub group_form {
    my($r,$mode) = @_;
    $r->print('<form method="post" action="home">');
    my %fields;
    my $name_value;
    my $description_value;
    my $submit_value;
    if ($mode eq 'update') {
        my $group_id = $r->param('groupid');
        my $qry = "select * from groups where group_id = $group_id";
        my $sth;
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        $name_value = $$row{'name'};
        $description_value = $$row{'description'};
        $submit_value = 'Update Group';
        $fields{'action'} = 'updategroup';
        $fields{'groupid'} = $group_id;
    } else {
        $submit_value = 'Add Group';
        $fields{'action'} = 'addgroup';
    }
    $fields{'menu'} = 'groups';
    $fields{'submenu'} = 'selectgroup';
    $r->print('<fieldset>');
    $r->print('<div><label>Group Name:</label><input type="text" name="name" value="'.$name_value.'" /></div>');
    $r->print('<div><label>Description:</label><textarea rows="5" cols="50" name="description">'.$description_value.'</textarea></div>');
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" value="'.$submit_value.'" />');
    $r->print('</fieldset>');
    $r->print('</form>');
    return 1;    
}

sub display_my_groups {
    my($r) = @_;
    my $user_id = $env{'user_id'};
    my $sth;
    my $qry;
    my $user_roles = &get_user_roles($r);
    if ($user_roles =~ /Admin/) {
        # Admin gets them all
         $qry = "select groups.group_id, name, description 
            FROM groups
            ORDER BY groups.name";
    } else {
        # others get only the ones they belong to
         $qry = "select groups.group_id, name, description 
            FROM groups, group_members
            WHERE groups.group_id = group_members.group_id AND
                group_members.user_id = $user_id
            ORDER BY groups.name";
    }
    my $found_one = 0;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<div class="groupSelectorContainer">');
    $r->print('<div class="groupHeader">');
    $r->print('Groups');
    $r->print('</div>');
    $r->print('<div class="groupScroller">');
    while (my $row = $sth->fetchrow_hashref()) {
        $found_one = 1;
        $r->print('<div class="groupRow">');
        $r->print('<a href="home?token='.$env{'token'}.'&amp;menu=groups&amp;submenu=membership&amp;groupid='.$$row{'group_id'}.'">'.&text_to_html($$row{'name'}).'</a>'."\n");
        $r->print('</div>');
    }
    if (!$found_one) {
        $r->print('<div class="groupRow">');
        $r->print('No groups yet');
        $r->print('</div>');
    }
    $r->print('</div>'); # end groupScroller
    $r->print('</div>');
    return 1;
}
sub save_group {
    my ($r) = @_;
    my $table = 'groups';
    my %fields;
    $fields{'name'} = &fix_quotes($r->param('name'));
    $fields{'description'} = &fix_quotes($r->param('description'));
    &save_record($table,\%fields);
    return 1;
}
sub display_group_info {
    my ($r) = @_;
    my $groupid = $r->param('groupid');
    my $qry = "select * from groups where group_id = $groupid";
    my $sth;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $r->print('<div>'."\n");
    $r->print('Details for: '.$$row{'name'});
    $r->print('</div>'."\n");
    my $text = $$row{'description'};
    $text=~ s/\n/<br>/g;
    $r->print('Description: '.$text);   
    $r->print('<br /><a href="home?token='.$env{'token'}.'&amp;menu=groups&amp;submenu=editgroup&amp;groupid='.$groupid.'">[Edit Group]</a><br />');
    return 1;
}
sub display_group_members {
    my ($r) = @_;
    my $groupid = $r->param('groupid');
    my $qry = "select lastname, firstname from users t1, group_members t2 where t2.group_id = $groupid ";
    $qry .= " and t1.id = t2.user_id order by lastname";
    my $sth;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $found_one = 0;
    $r->print('<div class="groupSelectorContainer">');
    $r->print('<div class="groupHeader">');
    $r->print('Group Members');
    $r->print('</div>');
    $r->print('<div class="groupScroller">');
    while (my $row = $sth->fetchrow_hashref()) {
        $found_one = 1;
        $r->print('<div class="groupRow">');
        $r->print($$row{'firstname'}.' '.$$row{'lastname'});
        $r->print('</div>');
    }
    unless ($found_one) {
        $r->print('<div class="groupRow">');
        $r->print('<br />No members in group<br />');
        $r->print('</div>');
    }
    $r->print('</div>'); # end groupScroller
    $r->print('</div>'); # end groupSelectorContainer
    $r->print('<br /><a href="home?token='.$env{'token'}.'&amp;menu=groups&amp;submenu=editmembers&amp;groupid='.$groupid.'">[Edit Member List]</a><br />');
    
    return 1;
}
sub alpha_menu {
    my ($r,$url,$fields) = @_;
    my $alpha_filter = $r->param('alphafilter');
    unless ($alpha_filter) {
        $alpha_filter = 'A';
    }
    my $url_encode = '?';
    foreach my $key(keys(%$fields)) {
        $url_encode .= $key.'='.$$fields{$key}.'&amp;';
    }
    $url .= $url_encode;
    my (@alphabet) = ('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z');
    my $output;
    my $strong_on;
    my $strong_off;
    foreach my $letter(@alphabet) {
        if ($letter eq $alpha_filter) {
            $strong_on = '<strong>';
            $strong_off = '</strong>';
        } else {
            $strong_on = '';
            $strong_off = '';
        }
            
        $output .= $strong_on.'<a href="'.$url.'alphafilter='.$letter.'">['.$letter.']</a>'.$strong_off;
    }
    $r->print("$output");
    return 1;
}
sub get_non_member_groups {
    my($userid) = @_;
    # returns a list of groups that $userid is not a member of
    my $roles = &get_user_roles();
    my $qry = "select group_id, name from groups where group_id not in 
                (select group_id from group_members where user_id = $userid)";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my %group_ids;
    while (my $row = $sth->fetchrow_hashref()) {
        $group_ids{$$row{'name'}} = $$row{'group_id'};
    }
    return (\%group_ids);
}
sub get_user_groups {
    my($userid) = @_;
    # returns a list of groups that $userid is a member of
    # if user is admin, returns all groups
    my $roles = &get_user_roles();
    my $role_filter = "";
    if (!($roles =~ /Administrator/)) {
        $role_filter = " AND user_id = $userid ";
    }
    my $qry = "SELECT DISTINCT t1.group_id, name 
            FROM group_members t1, groups t2 
            WHERE t1.group_id = t2.group_id 
            $role_filter";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my %group_ids;
    $group_ids{'exists'} = 'false';
    while (my $row = $sth->fetchrow_hashref()) {
        $group_ids{$$row{'name'}} = $$row{'group_id'};
        $group_ids{'exists'} = 'true';
    }
    return (\%group_ids);
}
sub get_thread_name {
    my($thread_id) = @_;
    my $thread_name;
    my $thread_description;
    my $qry;
    $qry = "select short_name, description from threads where id = $thread_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $thread_name = $$row{'short_name'};
    $thread_description = $$row{'description'};
    return ($thread_name,$thread_description);
}
sub group_where_am_i {
    my ($r) = @_;
    my $group_id = $env{'group_id'};
    my ($group_name,$group_description) = &get_group_name($group_id);
    my $thread_id = $r->param('threadid');
    my $thread_name;
    my $thread_description;
    if ($thread_id) {
        ($thread_name, $thread_description) = &get_thread_name($thread_id);
    }
    $r->print('<div id="whereAmI">');
    $r->print('Group: '.&text_to_html($group_name.'--'));
    if ($thread_id) {
        $r->print('Thread: <strong>'.&text_to_html($thread_name).': </strong>'.&text_to_html($thread_description));
    }
    $r->print('</div>');
    return 1;
}
sub delete_post {
    my ($r) = @_;
    my $node = $r->param('node');
    my $thread_id = $r->param('threadid');
    my $return_value;
    my $qry = "lock tables posts write";
    $env{'dbh'}->do($qry);
    $qry = "select next, previous from posts where id = $node";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    my $next = $$row{'next'};
    my $previous = $$row{'previous'};
    if ($previous) {
        if (! $next) {$next = 'NULL';}
        $qry = "update posts set next = $next where id = $previous";
        $env{'dbh'}->do($qry);
    }
    if ($next) {
        if (! $previous) {$previous = 'NULL';}
        $qry = "update posts set previous = $previous where id = $next";
        $env{'dbh'}->do($qry);
    }
    $qry = "delete from posts where id = $node";
    $env{'dbh'}->do($qry);
    $qry = "unlock tables";
    $env{'dbh'}->do($qry);
    $return_value = 'deleted';
    return ($return_value);
}
sub strand_to_coords {
    my ($strand,$level) = @_;
    my @coords;
    my $qry = "SELECT coord FROM strand_framework, strands, math_framework
                WHERE strands.id = strand_framework.strand_id AND
                (math_framework.code = strand_framework.framework_code or
                math_framework.code like concat(strand_framework.framework_code, '.%')) AND
                strands.strand_id = '$strand' AND 
                coord <> 0 and
                level = '$level'";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push @coords,$$row{'coord'};
    }
    return \@coords;
}
sub get_district_scores {
    # returns nodes and scores for feeding to make_gfw
    my ($district,$grade) = @_;
    my $level;
    my %scores_by_coord;
    if ($grade =~ /[3|4|5]/) {
        $level = 'ES';
    } elsif ($grade =~ /[6|7|8]/) {
        $level = 'MS';
    }
    my $qry = "select * from school_performance where school = $district and grade = $grade";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        my $coords = &strand_to_coords($$row{'strand'},$level);
        foreach my $coord(@$coords) {
            $scores_by_coord{$coord} = $$row{'score'};
        }
    }
    return \%scores_by_coord;
}
sub make_menu {
    # under construction, not yet doing anything
    my $r = @_;
    my ($links,$selected)=@_;
    foreach my $anchor_link(@$links) {
        $r->print('');
    }
    
}
sub score_span_selector {
    my ($score) = @_;
    my $lowThreshold = 30;
    my $highThreshold = 70;
    my $score_span = '<span class="midScore">';
    if ($score > $highThreshold) {
        $score_span = '<span class="hiScore">';
    } elsif ($score < $lowThreshold) {
        $score_span = '<span class="lowScore">';
    }
    return ($score_span);
}
sub district_data_menu {
    my ($r)=@_;
    $r->print('<span class="nav">[ <a href="home?token='.$Apache::Promse::env{'token'}.
              '&amp;target=data;display=table;menu=districtdata">Tabular Display</a> ]</span>');
    $r->print('<span class="nav">[ <a href="home?token='.$Apache::Promse::env{'token'}.
              '&amp;target=data;display=graphic;menu=districtdata">Graphic Display</a> ]</span>');
    return 1;
}
sub tabular_data_col_head {
    my ($r,$legend_name,$legend_values)=@_;
    $r->print('<div class="districtDataColHeaderRow">');  
    $r->print('<div class="districtDataTitleHeader">Strand</div>');
    $r->print('<div class="legendContainer">');
    $r->print('<div class="legendName">'.$legend_name.'</div>');
    foreach my $value(@$legend_values) {
        $r->print('<div class="legendValue">'.$value.'</div>');
    }
    $r->print('</div>'); # end legend container
    $r->print('</div>'); 
    return 1;
}
sub tabular_data_display {
    my ($r)=@_;
    my (@locations) = &get_user_locations($env{'user_id'});
    # @locations contains a location for each year
    my $location = $locations[0];
    my $district_id = $$location{'district_id'};
    my $school_id = $r->param('schoolid')?$r->param('schoolid'):0;
    my $scores_col_1;
    my $scores_col_2;
    my $scores_col_3;
    my $legend_name;
    my @legend_values;
    if (!$school_id) {
        $school_id = $district_id;
    }
    my $threshold = 50;
    if ($r->param('threshold')) {
        $threshold = $r->param('threshold');
    }
    my $grade;
    if (!$r->param('grade')) {
        $grade = '3';
    } else {
        $grade = $r->param('grade');
    }
    my $year = 2004;
    if (!$r->param('year')) {
        $year = 2004;
    } else {
        $year = $r->param('year');
    }
    my $display_columns_num = 1;
    if ($grade =~ /,/) {
        $legend_name = "Grade";
        # multiple grades to deal with
        my @grades = split(/,/,$grade);
        @legend_values = split(/,/,$grade);
        my $col_counter = 1;
        foreach my $score_grade (@grades) {
            if ($col_counter eq 1) {
                $scores_col_1 = &get_scores($school_id, $year, $score_grade);
            } elsif ($col_counter eq 2) {
                $scores_col_2 = &get_scores($school_id, $year, $score_grade);
            } elsif ($col_counter eq 3) {
                $scores_col_3 = &get_scores($school_id, $year, $score_grade);
            }    
            $col_counter ++;
        }
        $display_columns_num = 3;
    } elsif ($year =~ /,/) {
        $legend_name = "Year";
        my @years = split(/,/,$year);
        @legend_values = split(/,/,$year);
        my $col_counter = 1;
        foreach my $score_year (@years) {
            if ($col_counter eq 1) {
                $scores_col_1 = &get_scores($school_id, $score_year, $grade);
            } elsif ($col_counter eq 2) {
                $scores_col_2 = &get_scores($school_id, $score_year, $grade);
            } elsif ($col_counter eq 3) {
                $scores_col_3 = &get_scores($school_id, $score_year, $grade);
            }    
            $col_counter ++;
        }
        $display_columns_num = 3;
    } else {
        $legend_name = "Score";
        $scores_col_1 = &get_scores($school_id, $year, $grade);
        $scores_col_2 = $scores_col_1;
        $scores_col_3 = $scores_col_1;
    }
    my @options = ({'3'=>'3'},
                  {'4'=>'4'},
                  {'5'=>'5'},
                  {'3-5'=>'3,4,5'},
                  {'6'=>'6'},
                  {'7'=>'7'},
                  {'8'=>'8'},
                  {'6-8'=>'6,7,8'},
                  {'9'=>'9'},
                  {'10'=>'10'},
                  {'11'=>'11'},
                  {'12'=>'12'},
                  {'9-11'=>'9,10,11'},
                  {'10-12'=>'10,11,12'}
                  );
    my $grade_select = &build_select('grade',\@options,$grade,' onChange="retrieveDistrictSchools(grade)" ','5em');
    my @schools = &get_schools($district_id);
    unshift (@schools,{'District Wide'=>'0'});
    my $school_select = &build_select('schoolid',\@schools,$school_id,"");
    my @thresholds = ({'30'=>'30'},
                    {'40'=>'40'},
                    {'50'=>'50'},
                    {'60'=>'60'},
                    {'70'=>'70'},
                    {'80'=>'80'}); 
    my $threshold_select = &build_select('threshold',\@thresholds,$threshold,"","3em");
    my @years = ({'2004'=>'2004'},
                    {'2007'=>'2007'},
                    {'2008'=>'2008'},
                    {'2004-08'=>'2004,2007,2008'}
                    ); 
    my $year_select = &build_select('year',\@years,$year,' onChange="retrieveDistrictSchools(grade)" ',"6em");
                   
    my $javascript = qq ~
    <script type="text/javascript" >
        var token="$Apache::Promse::env{'token'}";
        var districtID="$district_id";
        var t=setTimeout("populateFormFirst()",200)
        populateFormFirst();
        function populateFormFirst() {
            try {
                grade = document.getElementById("grade").value;
                schoolid = document.getElementById("schoolid").value;
                clearTimeout(t);
                retrieveDistrictSchools(grade);
            } 
            catch (e) {
                return;
            }
        }
        function retrieveDistrictSchools(grade) {
            var xmlHttp;
            document.getElementById("statusMessage").innerHTML="Loading";
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
                    document.getElementById("schoolPulldown").innerHTML=display; 
                    document.getElementById("statusMessage").innerHTML="&nbsp;";  
                    // timedMsg();     
                }
            }
            grade = document.getElementById("grade").value;
            year = document.getElementById("year").value;
            xmlHttp.open("GET","/promse/flash?token="+token+";action=getdistrictschoolsbygrade;year="+year+";schoolid="+schoolid+";districtid="+districtID+";grade="+grade,true);
            xmlHttp.send(null);
        }
        </script>        
    ~;
    $r->print($javascript);
    $r->print('<div class="dataContainer">');
    $r->print('<div style="float: left">District: <strong>'.$$location{'district_name'}.'</strong></div> ');
    $r->print('<div style="text-align: right;margin-right: 20px"><span id="statusMessage"></span></div>');
    $r->print('<form method="post" action="">');
    $r->print('<div class="dataInputForm">Grade: '.$grade_select.'School: <span id="schoolPulldown">'.$school_select.'</span>');
    $r->print('Year: '.$year_select);
    #$r->print('Threshold: '.$threshold_select);
    $r->print('<input type="submit" value="Update Display" />');
    $r->print('</div>');
    my %fields = ('districtid'=>$district_id,
                  'menu'=>'data',
                  'whichdata'=>'districtdata',
                  'submenu'=>'tabular');
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
    my $row_counter = 0;
    my $alternator = 0;
    my $row_class;
    my $div_opened = 0;
    my $num_rows;
    if (scalar(@$scores_col_1)) {
        $num_rows = scalar(@$scores_col_1);
    } elsif (scalar(@$scores_col_2)) {
        $num_rows = scalar(@$scores_col_2);
    } elsif (scalar(@$scores_col_3)) {
        $num_rows = scalar(@$scores_col_3);
    } else {
        $num_rows = 0;
    }
    for (my $row = 0; $row < $num_rows; $row ++) {
        my $score = $$scores_col_1[$row];
        my $score2 = $$scores_col_2[$row];
        my $score3 = $$scores_col_3[$row];
        $alternator = $alternator?0:1;
        if ($alternator) {
            $row_class = '<div class="districtDataRow" >';
        } else {
            $row_class = '<div class="districtDataRowAlt" >';
        }
        if(!$row_counter) {
            # here for beginning of first column
            $r->print('<div class="dataColOne">');
            &tabular_data_col_head($r,$legend_name,\@legend_values);
            $div_opened = 1;
        } elsif ($row_counter == 15) {
            # after 15 rows end first column, start second
            $r->print('</div>');
            $r->print('<div class="dataColTwo">');
            &tabular_data_col_head($r,$legend_name,\@legend_values);
        }
        $r->print($row_class);
        if ($display_columns_num == 3) {
            if ($$score{'description'}) {
                $r->print('<div class="strandDescription">'.&text_to_html($$score{'description'}).'</div>');
            } elsif ($$score2{'description'}) {
                $r->print('<div class="strandDescription">'.&text_to_html($$score2{'description'}).'</div>');
            } elsif ($$score3{'description'}) {
                $r->print('<div class="strandDescription">'.&text_to_html($$score3{'description'}).'</div>');
            }    
            if ($$score{'score'}) {
                my $score_span = &score_span_selector($$score{'score'});
                $r->print('<div class="strandScore">'.$score_span.$$score{'score'}.'</span></div>');
            } else {
                $r->print('<div class="strandScore"></div>');
            }
            if ($$score2{'score'}) {
                my $score_span = &score_span_selector($$score2{'score'});
                $r->print('<div class="strandScore">'.$score_span.$$score2{'score'}.'</span></div>');
            } else {
                $r->print('<div class="strandScore"></div>');
            }
            if ($$score3{'score'}) {
                my $score_span = &score_span_selector($$score3{'score'});
                $r->print('<div class="strandScore">'.$score_span.$$score3{'score'}.'</span></div>');
            } else {
                $r->print('<div class="strandScore"></div>');
            }
            $r->print('</div>'."\n");
        } else {
            $r->print('<div class="strandDescription">'.&text_to_html($$score{'description'}).'</div>');
            if ($$score{'score'}) {
                my $score_span = &score_span_selector($$score{'score'});
                $r->print('<div class="strandScore"></div>');
            }
            if ($$score{'score'}) {
                my $score_span = &score_span_selector($$score{'score'});
                $r->print('<div class="strandScore">'.$score_span.$$score{'score'}.'</span></div>');
            }
            if ($$score{'score'}) {
                my $score_span = &score_span_selector($$score{'score'});
                $r->print('<div class="strandScore"></div>');
            }
            $r->print('</div>'."\n");
        }
        $row_counter ++;
    }
    # close the last opened column div
    if ($div_opened) {
        $r->print('</div>');
    } else {
        if (($grade =~ /,/)&&($year =~ /,/)) {
            $r->print('Cannot display multiple year AND multiple grade in one table.');
        } else {
            $r->print('No data returned for selected grade and school.');
        }
    }   
    
    $r->print('</div>');
    return 1;
}
sub get_scores {
    my ($school_id, $year, $grade) = @_;
    my $qry = "SELECT t1.score, t2.description, t2.id 
               FROM school_performance t1, strands t2
               WHERE t1.school = $school_id AND
                     t1.year = $year AND
                     t1.grade = $grade AND
                     t1.strand_id = t2.id ORDER BY t2.id";
    my $sth = $Apache::Promse::env{'dbh'}->prepare($qry);
    $sth->execute();
    my @scores = ();
    my $scores_ref = \@scores;
    while (my $row = $sth->fetchrow_hashref()) {
        push(@scores,{%$row});
    }    
    return (\@scores);
}
sub data {
    my ($r)=@_;
    # should enter with district, grade, strand set (at least in $r)
    # if not set from form, then read from profile
    # TO DO:  restrict data based on user's school, district, etc.
    my $districtid;
    my $threshold;
    my $which_data;
    if (!$r->param('whichdata')) {
        $which_data = 'districtdata';
    } else {
        $which_data = $r->param('whichdata');
    }
    if ($r->param('districtid')) {
        $districtid = $r->param('districtid');
    } else {
        my $profile = &get_user_profile($env{'user_id'});
        $districtid = $$profile{'district_id'};
    }
    my $grade;
    if ($r->param('grade')) {
        $grade = $r->param('grade');
    } else {
        $grade = '3';
    }
    if ($r->param('threshold')) {
        $threshold = $r->param('threshold');
    } else {
        $threshold = '50';
    }
    my %fields;
    if ($which_data eq 'districtdata') {
        if ($env{'submenu'} eq 'graphic') {
            &Apache::Flash::gfw_flash_html($r);
        } elsif ($env{'submenu'} eq 'tabular') {
            &tabular_data_display($r);
        }
        return;
#        &visualizer_javascript($r);
#        $r->print('<form method="post" action="">');
#        my @districts = &get_districts();
#        $r->print('<div style="float:left;width:200px;text-align:left;">');
#        $r->print('<fieldset>');
#        $r->print('<label>District:');
#        $r->print(&build_select('districtid',\@districts,$districtid, ' style="width:15em;" '));
#        $r->print('</label>');
#        my @grades = ({'3'=>'3'},{'4'=>'4'},{'5'=>'5'},{'6'=>'6'},{'7'=>'7'},{'8'=>'8'});
#        $r->print('<br />');
#        $r->print('<label>Grade:');
#        $r->print(&build_select('grade',\@grades,$grade, ' style="width:3em;" '));
#        $r->print('</label>');
#        my @thresholds = ({'20%'=>'30'},{'30%'=>'30'},{'40%'=>'40'},{'50%'=>'50'},{'60%'=>'60'},{'70%'=>'70'},{'80%'=>'80'},{'90%'=>'90'});
#        $r->print('<br />');
#        $r->print('<label>Threshold:');
#        $r->print(&build_select('threshold',\@thresholds,$threshold, ' style="width:4em;" '));
#        $r->print('</label>');
#        %fields = ('token'=>$env{'token'},
#                    'target'=>'data',
#                    'menu'=>'districtdata',
#                    );
#        $r->print(&hidden_fields(\%fields));
#        $r->print('<br />');
#        $r->print('<input type="submit" value="Update settings" />');
#        $r->print('</fieldset>');
#        $r->print('</form>');
#        $r->print('</div>');
#        my $node_scores = &get_district_scores($districtid,$grade);
#        my $graphic_name = &make_gfw('testimage.gif',$node_scores,$threshold);
#        $r->print('<img src="../dynimages/'.$graphic_name.'" name="gfw" alt="framework" usemap="#frameworkmap" />');
#        $r->print(&framework_image_map);
#        $r->print('<h2 id="heading"></h2>');
#        $r->print('<div id="description" ></div>');
    } else {
        $r->print('<div>');
        $r->print('[<a href="../resources/PROMSE_Science_Report.pdf">Sample Science Report (8.5 MB PDF)</a>]<br />');
        #$r->print('[<a href="../resources/PROMSE_Math_Report.pdf">Sample Math Report (coming soon)</a>]<br />');
        #$r->print('[<a href="../resources/PROMSE_Case_Study.pdf">Case Study of Using Data to Improve Fraction Achievement (coming soon)</a>]<br />');
        %fields = ('token'=>$env{'token'},
                        'target'=>'data',
                        'menu'=>'districtdata',
                        'display'=>'table'
                        );
        my $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Explore Your District'."'".'s Data (in process)</a>]');
        $r->print('</div>');
    }
    return 'ok';
}
sub update_thread {
    my ($r) = @_;
    my $thread_id = $r->param('threadid');
    my $thread = &get_thread ($thread_id);
    my %fields = ('menu' => 'groups',
                'groupid' => $env{'group_id'},
                'threadid' => $thread_id,
                'action' => 'updatethread',
                'submenu' => 'discuss');
    $r->print('<form action="">');
    $r->print('Short Name: <input type="text" name="shortname" value="'.$$thread{'short_name'}.'" /><br />');
    $r->print('Long Name: <input type="text" name="longname" value="'.$$thread{'long_name'}.'" /><br />');
    $r->print('<textarea rows="14" cols="60" name="description">');
    $r->print($$thread{'description'});
    $r->print('</textarea><br />');
    $r->print('<input type="submit" value="Save Changes" />');
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
    return 'ok';
}
sub delete_thread {
    my ($r) = @_;
    my $thread_id = $r->param('threadid');
    my $thread = &get_thread($thread_id);
    my $deleted;
    my $qry = "delete from threads where id = $thread_id";
    $env{'dbh'}->do($qry);
    $qry = "delete from posts where id = $thread_id";
    $env{'dbh'}->do($qry);
    $deleted = 'deleted';
    return ($deleted);
}
sub groups {
    my ($r) = @_;
    my $non_member_groups;
    # not already in a group?
    # &group_selector($r, $group_ids, 'discuss');
    # $non_member_groups = &get_non_member_groups($env{'user_id'});
    if ($env{'action'} eq 'addpost') {
        if (!($r->param('post') eq '')) {&save_post($r)};
    }
    if ($env{'action'} eq 'deletepost') {
        &delete_post($r);
    }
    if ($env{'action'} eq 'addthread') {
        &save_thread($r);
    }
    if ($env{'group_id'} ne 'undefined') {
        &group_where_am_i($r);
    }
    if ($env{'action'} eq 'deletethread') {
        &delete_thread($r)
    }
    if ($env{'action'} eq 'updatethread') {
        my %id = ('id' => $r->param('threadid'));
        my %fields = ('description' => &fix_quotes($r->param('description')),
                  'short_name' => &fix_quotes($r->param('shortname')),
                  'long_name' => &fix_quotes($r->param('longname')));
        &update_record ('threads',\%id,\%fields);
    }
    if ($env{'action'} eq 'addreply') {
        if (!($r->param('post') eq '')){&save_reply($r)};
    }
    if ($env{'action'} eq 'saveeditpost') {
        &group_post_update($r);
    }
    if ($env{'action'} eq 'addgroup') {
        &save_group($r);
    }
    if ($env{'action'} eq 'updategroup') {
        &update_group($r);
    }
    if ($env{'submenu'} eq 'selectgroup') {
        &display_my_groups($r);
    } elsif ($env{'submenu'} eq 'addgroup') {
        &group_form($r);
    } elsif ($env{'submenu'} eq 'membership') {
        &display_group_info($r);
        &edit_group_members($r);
    } elsif ($env{'submenu'} eq 'editgroup') {
        &group_form($r,'update');
    } elsif ($env{'submenu'} eq 'editthread') {
        &update_thread($r);
    } elsif ($env{'submenu'} eq 'editmembers') {
        &edit_group_members($r);
    }
    if ($env{'submenu'} eq 'group_discuss') {
        # here after group is selected
        
        &group_menu($r);
        $r->print('<div>Please select a group activity.</div>');
        # &group_discuss($r);
    } elsif ($env{'submenu'} eq 'discuss') {
        &select_thread($r);
    } elsif ($env{'submenu'} eq 'addthread') {
        &start_thread($r);
    } elsif ($env{'submenu'} eq 'selectthread') {
        &group_discuss_menu($r);
        &select_thread($r);
    } elsif ($env{'submenu'} eq 'post') {
        if ($env{'action'} eq 'addpost') {
            &group_discuss_menu($r);
            &thread_menu($r);
            if (!($r->param('post') eq '')) {&save_post($r)};
            &show_thread($r);
        } else {
            &post_to_thread($r);
        }
    } elsif ($env{'submenu'} eq 'browsethread') {
        &show_thread($r);
    } elsif ($env{'submenu'} eq 'reply') {
        &reply_to_thread($r);
    } elsif ($env{'submenu'} eq 'documents') {
        &group_documents($r);
        
    } elsif ($env{'submenu'} eq 'uploaddoc') {
        &group_documents($r);
    } elsif ($env{'submenu'} eq 'browsedocs') {
        &group_documents($r);
    } elsif ($env{'submenu'} eq 'editpost') {
        &edit_post($r);
    } else {
        # shouldn't ever get here
        # here to select a group
    }
   
    return 1;
}
sub group_post_update {
    my ($r) = @_;
    my $node = $r->param('node');
    my $post = $r->param('post');
    $post = &fix_quotes($post);
    my $qry = "update posts set post = $post where id = $node";
    $env{'dbh'}->do($qry);
    return 1;
}
sub get_first_post_id {
    my ($thread_id) = @_;
    my $qry = "select id from posts where thread_id = $thread_id and previous is NULL";
    my $sth = $env{'dbh'}->prepare($qry);
    my $valid;
    my $post_id;
    $sth->execute();
    if (my $row = $sth->fetchrow_hashref()) {
        $post_id = $$row{'id'};
        $valid = 1;
    }
    return ($post_id, $valid);
}
sub get_next_in_thread {
    my ($thread_id, $next_id) = @_;
    my $qry = "select * from posts where thread_id = $thread_id and id = $next_id order by date desc limit 1";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return \%$row;
}
sub edit_post {
    my($r) = @_;
    my $thread_id = $r->param('threadid');
    my $group_id = $env{'group_id'};
    my %fields = ('submenu'=>'browsethread',
                    'threadid'=>$thread_id,
                    'action'=>'saveeditpost',
                    'menu'=>'groups',
                    'groupid'=>$group_id,
                    'node'=>$r->param('node'),
                    'indent'=>$r->param('indent')
                    );
    my $post_content = &get_post_content($r->param('node'));
    $r->print('<div class="groupStart">Edit your post</div>');
    $r->print('<div id="groupInstruction">Make your edits below. ');
    $r->print('Be sure to click Save Edits when finished.</div>');
    $r->print('<form method="post" action="home">');
    $r->print('<fieldset>');
    $r->print('<legend id="postReply"><div id=legendText>Edit a post</div></legend>');
    $r->print('<form method="post" action="home">');
    $r->print('<label>Your post: </label><textarea rows="10" cols="70" name="post" />'.$post_content.'</textarea>');
    
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" value="Save Edits"');
    $r->print('</fieldset>');
    $r->print('</form>');
    return 1;
}
sub show_post {
    my ($r, $post_id) = @_;
    my $qry = "select indent, date, posts.id, next, post, FirstName, LastName, photo, user_id from posts, users
                 where posts.id = $post_id and user_id = users.id";
    my $sth = $env{'dbh'}->prepare($qry);
    my $content;
    my $node;
    my $node_next;
    my $indent;
    my %fields;
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $node = $$row{'id'};
    $indent = $$row{'indent'} + 1;
    if ($$row{'next'}) {
        $node_next = $$row{'next'};
    } else {
        $node_next = 'NULL';
    }
    $r->print('<div id="postContainer">');
    $r->print('<div id="postDate">');
    $r->print('Posted: '.$$row{'date'}.' By: '.$$row{'FirstName'}." ".$$row{'LastName'});
    $r->print('</div>');
    $r->print('<div id="postContent">');
    $r->print('<div id="indent'.$indent.'">');
            
    if ($$row{'photo'}) {
        %fields = ('target' => 'profiledisplay',
                   'token' => $env{'token'},
                   'profileid' => $$row{'user_id'});
        my $url = &build_url('home',\%fields);
        $r->print('<a href="'.$url.'">
                   <img align="left" width="50" height="50" src="../images/userpics/'.$$row{'photo'}.'" alt="" />
                   </a>');
    }
    $content = &text_to_html($$row{'post'});
    $r->print($content);
    $r->print('</div>');
    $r->print('</div>');
    $r->print('<div id="postReply">');
    my $user_roles = &get_user_roles;
    if (($user_roles =~ /Administrator/)||($env{'user_id'} eq $$row{'user_id'})) {
        %fields = ('token'=>$env{'token'},
                        'menu'=>'groups',
                        'submenu'=>'browsethread',
                        'action'=>'deletepost',
                        'groupid'=>$env{'group_id'},
                        'threadid'=>$r->param('threadid'),
                        'node'=>$node
                        );
        my $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'" onclick="javascript:return confirm(\'Delete this post?\')">Delete</a>]');
    }
    if ($$row{'user_id'} eq $env{'user_id'}) {
        %fields = ('token'=>$env{'token'},
                        'menu'=>'groups',
                        'submenu'=>'editpost',
                        'groupid'=>$env{'group_id'},
                        'threadid'=>$r->param('threadid'),
                        'node'=>$node
                        );
        my $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Edit</a>]');
    }
    %fields = ('token'=>$env{'token'},
                    'menu'=>'groups',
                    'submenu'=>'reply',
                    'groupid'=>$env{'group_id'},
                    'threadid'=>$r->param('threadid'),
                    'node'=>$node,
                    'indent'=>$indent
                    );
    my $url = &build_url('home',\%fields);
    $r->print('[<a href="'.$url.'">Respond</a>]');
    $r->print('</div>');
    $r->print('</div>');
    return $$row{'next'};
}
sub text_to_html {
    my($content)=@_;
        if ($content) {
        $content =~ s/&/&amp;/g;
        $content =~ s/</&lt;/g;
        $content =~ s/>/&gt;/g;
        $content =~ s/\r/<br \/>/g;
    }
    return($content);
}
sub show_thread {
    my ($r) = @_;
    my $thread_id = $r->param('threadid');
    my ($first_id,$valid) = &get_first_post_id($thread_id);
    my $next_id = $first_id;
    my $done = 0;
    if ($valid) {
        $r->print('<div id="postsContainer">');
        while (!$done) {
            $next_id = &show_post($r, $next_id);
            if (!$next_id) {
                $done = 1;
            }
        }
        $r->print('</div>'); 
    } else {
        $r->print('<div>There are no posts to this thread. Click Post to start the discussion.</div>');
    }
    return 1;
}
sub reply_to_thread {
    my ($r) = @_;
    my $thread_id = $r->param('threadid');
    my $group_id = $env{'group_id'};
    my %fields = ('submenu'=>'reply',
                    'threadid'=>$thread_id,
                    'action'=>'addreply',
                    'menu'=>'groups',
                    'groupid'=>$group_id,
                    'node'=>$r->param('node'),
                    'indent'=>$r->param('indent')
                    );
    my $post_content = &get_post_content($r->param('node'));
    $r->print('<div class="groupStart">Reply to a discussion post</div>');
    $r->print('<div id="groupInstruction">Enter your reply below. ');
    $r->print('Be sure to click Reply to Post when finished.</div>');
    $r->print('<form method="post" action="home">');
    $r->print('<fieldset>');
    $r->print('<legend id="postReply"><div id=legendText>'.$post_content.'</div></legend>');
    $r->print('<form method="post" action="home">');
    $r->print('<label>Description: </label><textarea rows="10" cols="70" name="post" /></textarea>');
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" value="Reply to Post"');
    $r->print('</fieldset>');
    $r->print('</form>');
    return 1;
}
sub get_thread_description {
    my($thread_id) = @_;
    my $qry = "select description from threads where id = $thread_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    my $description = $$row{'description'};
    return $description;
}
sub get_thread {
    my($thread_id) = @_;
    my $qry = "select * from threads where id = $thread_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return $row;
}
sub get_post_content {
    my($node) = @_;
    my $qry = "select post from posts where id = $node";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    my $post = $$row{'post'};
    return $post;
}
sub post_to_thread {
    my ($r) = @_;
    my $thread_id = $r->param('threadid');
    my $group_id = $env{'group_id'};
    my %fields = ('submenu'=>'browsethread',
                    'threadid'=>$thread_id,
                    'action'=>'addpost',
                    'menu'=>'groups',
                    'groupid'=>$group_id
                    );
    my $description = &get_thread_description($thread_id);
    $r->print('<form method="post" action="home">');
    $r->print('<div class="groupStart">Post to the discussion thread</div>');
    $r->print('<div id="groupInstruction">Enter your post to the thread below. ');
    $r->print('Be sure to click Post to Thread when finished.</div>');
    $r->print('<form method="post" action="home">');
    $r->print('<fieldset>');
    $r->print('<legend><div id="legendText"> Description of thread: '.$description.'</div></legend>');
    $r->print('<label>');
    $r->print('Your post:</label><textarea rows="10" cols="70" name="post" /></textarea>');
    
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" value="Post to Thread"');
    $r->print('</fieldset>');
    $r->print('</form>');
    return 1;
}
sub save_reply {
    my ($r) = @_;
    my $user_id = &token_to_userid($env{'token'});
    my $thread_id = $r->param('threadid');
    my $node = $r->param('node');
    my $post = &fix_quotes($r->param('post'));
    my $qry;
    $qry = "lock tables posts write";
    $env{'dbh'}->do($qry);
    $qry = "select next from posts where id = $node ";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    my $node_next = $$row{'next'};
    if (!($node_next)) {
        $node_next = 'NULL';
    }
    $post = &text_to_html($post);
    my %fields = ('user_id' => $user_id,
                'thread_id' => $thread_id,
                'date' => ' NOW() ',
                'post' => $post,
                'active' => '1',
                'previous' => $node,
                'next' => $node_next,
                'indent' => $r->param('indent')
                );
    my $new_id = &save_record('posts',\%fields,1);
    if ($new_id) {
        my %id_field = ('id'=>$node);
        %fields = ('next'=>$new_id);
        &update_record('posts',\%id_field,\%fields);
        %id_field = ('id'=>$node_next);
        %fields = ('previous'=>$new_id);
        &update_record('posts',\%id_field,\%fields);
    } else {
        $r->print('There was a problem, please contact the system administrator');
    }
    $qry = "unlock tables";
    $env{'dbh'}->do($qry);
    return 1;
}

sub save_post {
    my ($r) = @_;
    # assumes that we are appending to last of posts in linked list
    my $user_id = &token_to_userid($env{'token'});
    my $thread_id = $r->param('threadid');
    my $indent = '0'; # posts are all 0 indent
    my $previous;
    # first need to retrieve ID of last record
    my $qry;
    $qry = "lock tables posts write" ;
    $env{'dbh'}->do($qry);
    $qry = "select id, next from posts where thread_id = $thread_id and next is NULL";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    my $previous_post_id = $$row{'id'};
    if ($previous_post_id) {
        $previous = $previous_post_id;
    } else {
        $previous = " NULL ";
    }
    my %fields = ('user_id'=>$user_id,
                'thread_id'=>$thread_id,
                'date'=>' NOW() ',
                'post'=>&fix_quotes($r->param('post')),
                'active'=>'1',
                'indent'=>$indent,
                'previous'=>$previous
                );
    my $post_id = &save_record('posts',\%fields,1);
    my %id_fields = ('id' => $previous);                   
    %fields = ('next'=>$post_id);
    &update_record('posts',\%id_fields,\%fields);
    $qry = "unlock tables" ; 
    $env{'dbh'}->do($qry);           
    return 1;
}
sub thread_menu {
    my ($r) = @_;
    my $url;
    my %fields = ('token'=>$env{'token'},
                    'menu'=>'groups',
                    'threadid'=>$r->param('threadid'),
                    'groupid'=>$env{'group_id'},
                    'submenu'=>'browse');
    if (($env{'submenu'} eq 'post')||($env{'submenu'} eq 'reply')) {
        $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Browse Posts</a>]');
    }
    $fields{'submenu'} = 'post';
    if (($env{'submenu'} eq 'browse') || ($env{'submenu'} eq 'deletepost') ||
        ($env{'submenu'} eq 'editpost')||($env{'submenu'} eq 'reply')) {
        $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Post</a>]');
    }
    return 1;    
}
sub get_group_name {
    my($group_id) = @_;
    my $group_name;
    my $group_description;
    my $qry;
    $qry = "select name, description from groups where group_id = $group_id order by name";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $group_name = $$row{'name'};
    $group_description = $$row{'description'};
    return ($group_name,$group_description);
}
sub group_menu {
    my($r) = @_;
    my $url;
    my %fields = ('token'=>$env{'token'},
                    'menu'=>'groups',
                    'groupid'=>$env{'group_id'},
                    'submenu'=>'discuss');
    if (($env{'menu'} eq 'documents') || ($env{'menu'} eq 'browsedocs') ||
            ($env{'menu'} eq 'uploaddoc')) {
        $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Discuss</a>]');
    }
    if (($env{'submenu'} eq 'discuss') || ($env{'submenu'} eq 'selectthread')||
        ($env{'submenu'} eq 'startthread')||($env{'submenu'} eq 'browse') ||
        ($env{'submenu'} eq 'editthread') || ($env{'submenu'} eq 'deletethread')||
        ($env{'submenu'} eq 'post')|| ($env{'submenu'} eq 'deletepost') ||
        ($env{'submenu'} eq 'editpost')||($env{'submenu'} eq 'reply')) {
        $fields{'submenu'} = 'documents';
        $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Documents</a>]');
    }
    return 1;
}
sub group_document_menu {
    my($r) = @_;
    my $url;
    my %fields = ('token'=>$env{'token'},
                    'menu'=>'groups',
                    'groupid'=>$env{'group_id'},
                    'submenu'=>'browsedocs');
    if (($env{'submenu'} eq 'uploaddoc')) {
        $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Browse</a>]');
    }
    if (($env{'submenu'} eq 'browsedocs') || ($env{'submenu'} eq 'documents')) {
        $fields{'submenu'} = 'uploaddoc';
        $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Upload Document</a>]');
    }
    return 1;
}

sub group_discuss_menu {
    my($r) = @_;
    &group_menu($r);
    my $url;
    my %fields = ('token'=>$env{'token'},
                    'group'=>'groups',
                    'groupid'=>$env{'group_id'},
                    'submenu'=>'selectthread',
                    'action'=>'selectthread');
    if (($env{'submenu'} eq 'startthread') || ($env{'submenu'} eq 'browse') || 
            ($env{'submenu'} eq 'editthread') || ($env{'submenu'} eq 'deletepost')||
            ($env{'submenu'} eq 'editpost')||($env{'submenu'} eq 'reply')){
        $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Select Thread</a>]');
    }
    if (($env{'submenu'} eq 'selectthread') || ($env{'submenu'} eq 'discuss')) {
        $fields{'submenu'} = 'startthread';
        $url = &build_url('home',\%fields);
        $r->print('[<a href="'.$url.'">Start Thread</a>]');
    }
    return 1;
}
sub group_discuss {
    my($r) = @_;
    if ($env{'action'} eq 'startthread') {
        &start_thread($r);
    } elsif ($env{'action'} eq 'addthread') {
        &save_thread($r);
        $r->print('save the thread');
    } else {
        my %fields= ('submenu'=>'group_discuss',
                    'token'=>$env{'token'},
                    'menu'=>'groups',
                    'groupid'=>$env{'group_id'},
                    'action'=>$r->param('startthread'));
        my $url = &build_url('home', \%fields);
        $r->print('<a href="'.$url.'">Start a Thread</a>');
    }
    return 1;
}
sub select_thread {
    my($r) = @_;
    my $group_id = $env{'group_id'};
    my $qry = "SELECT t1.FirstName, t1.LastName, t2.description, t2.id thread_id, 
               count(t3.id) postcount, t2.short_name, t2.date, t1.id user_id
               FROM users t1, threads t2
               LEFT JOIN posts t3 on t2.id = t3.thread_id 
               WHERE t1.id = t2.user_id and t2.group_id = $group_id 
               GROUP by t2.id
               ORDER by t2.date desc";

    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    if ($sth->rows()) {
        $r->print('<div id="groupInstruction">');
        $r->print('Click on the thread that you wish to read or post to.</div>');
        $r->print('<table><tr><th>Thread (posts)</th><th>Description</th><th>Started By:</th>');
        while (my $row = $sth->fetchrow_hashref()) {
            my $picture = &get_picture($$row{'user_id'});
            my %fields = ('token' => $env{'token'},
                            'menu' => 'groups',
                            'groupid' => $env{'group_id'},
                            'submenu' => 'browsethread',
                            'threadid' => $$row{'thread_id'});
            my $url = &build_url('home',\%fields);
                           
            $r->print('<tr><td><a href="'.$url.'">'.$$row{'short_name'}.'</a> ('.$$row{'postcount'}.')</td>');
            my $text = $$row{'description'};
            $text=~ s/\n/<br \/>/g;
            $r->print('<td align="left">'.$text.'<br />');
            $fields{'submenu'} = 'editthread';
            $url = &build_url('home',\%fields);
            if ((&get_user_roles =~ m/Editor/)||($env{'user_id'} eq $$row{'user_id'})) {
                $r->print('<a href="'.$url.'">[Edit]</a>');
                $fields{'submenu'} = 'discuss';
                $fields{'action'} = 'deletethread';
                $url = &build_url('home',\%fields);
                $r->print('<a href="'.$url.'" onclick="javascript:return confirm(\'Delete this thread?\')"> [Delete]</a>');
            }
            $r->print('</td>');
            $fields{'target'}='profiledisplay';
            $fields{'profileid'} = $$row{'user_id'};
            $url = &build_url('home',\%fields);
            $r->print('<td><a href="'.$url.'"><img width="50" src="../images/userpics/'.$picture.'" 
                             alt="" /><br />'.$$row{'FirstName'}.' '.$$row{'LastName'}.
                             '</a></td></tr>');
        }
        $r->print('</table>');
    } else {
        $r->print('<div>There are no threads. Click Add Thread to create a new thread.</div>');
    }
        
    return 1;
}
sub get_picture {
    my ($user_id) = @_;
    my $picture;
    my $qry = "select photo from users where id = ".$user_id;
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $picture = $$row{'photo'};
    return($picture);
}
sub save_thread {
    my($r)=@_;
    my ($short_name, $long_name, $description);
    $short_name = &fix_quotes($r->param('shortname'));
    $long_name = &fix_quotes($r->param('longname'));
    $description = &fix_quotes($r->param('description'));
    my $user_id = &token_to_userid($env{'token'});
    my %fields = ('short_name'    => $short_name,
                    'long_name'   => $long_name,
                    'description' => $description,
                    'user_id'     => $user_id,
                    'date'        => ' NOW() ',
                    'active'      => ' 1 ',
                    'group_id'    => $env{'group_id'}
                    );
    my $thread_id = &save_record('threads',\%fields,1);
    # now create dummy first post
    %fields = ('user_id'=>$user_id,
                'thread_id'=>$thread_id,
                'date'=>' NOW() ',
                'post'=>&fix_quotes('dummy'),
                'active'=>'1',
                );
    # &save_record('posts',\%fields);
    return 1;
}
sub start_thread {
    my($r) = @_;
    # fields to be coded in hidden fields later
    my %fields = ('submenu'=>'discuss',
                'menu'=>'groups',
                'groupid'=>$env{'group_id'},
                'action'=>'addthread');
    $r->print('<div class="groupStart">Start a discussion thread</div>');
    $r->print('<div id="groupInstruction">Enter the information about your thread below. ');
    $r->print('Once you have created the thread, you can select the new thread and post to it.</div>');
    $r->print('<form method="post" action="home">');
    $r->print('<table><tr><td align="right">');
    $r->print('Short Name:</td><td align="left"><input type="text" name="shortname" /></td></tr>');
    $r->print('<tr><td align="right">Long Name:</td><td align="left"> <input size="40" type="text" name="longname" /></td></tr>');
    $r->print('<tr><td align="right">Description:</td><td align="left"> <textarea rows="5" cols="40" name="description" /></textarea></td></tr></table>');
    $r->print('<input type="submit" value="Save New Thread" /><br />');
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
    
    return 1;
}
sub build_url {
    
    my ($base, $fields)=@_;
    my $url;
    $url = $base.'?';
    foreach my $key(keys(%$fields)) {
        $url.=$key.'='.$$fields{$key}.'&amp;';
        # &logthis("url is $url");
    }
    $url =~ s/&amp;$//;
    return $url;
}
sub build_select {
    my($name,$options,$selected,$javascript,$width) = @_;
    # $options is reference to array of hashes
    $selected = !$selected?"":$selected;
    $javascript = !$javascript?"":$javascript;
    $width = !$width?"":' style="width: '.$width.'px; display: block;" ';
    my $output;
    my $checked;
    $output .= '<select '.$width.' id="'.$name.'" name="'.$name.'" '.$javascript.">\n";
    foreach my $option (@$options) {
        my @key = keys(%$option);
		if (ref($selected)) {
			$checked = "";
			foreach my $selected_element(@$selected) {
				print STDERR "********* It's a reference checking $selected_element \n";
		        if ($$option{$key[0]} eq $selected_element) {
		            $checked = " selected=\"selected\" ";
				}
			}
		} else {
        	if ($$option{$key[0]} eq $selected) {
            	$checked = " selected=\"selected\" ";
        	} else {
            	$checked = "";
			}
        }
        $output .= '<option value="'.$$option{$key[0]}.'"'.$checked.'>'."\n";
        $output .= $key[0];
        $output .= "</option>\n";
    }
    $output .= "</select>";
    return $output;
}
sub group_selector {
    my ($r, $group_ids, $menu) = @_;
    if (!$menu) {
        $menu = 'manage';
    }
    my %fields;
    my $url;
    %fields = ('token' => $env{'token'},
               'target' => 'groups',
               'menu' => $menu);
    $r->print('<div class="groupSelectorContainer">');
    
    $r->print('<div class="groupHeader">');
    $r->print('My Groups');
    $r->print('</div>');
    $r->print('<div class="groupScroller">');
    foreach my $key (sort(keys(%$group_ids))) {
        $fields{'groupid'} = $$group_ids{$key};
        $url = &build_url('home', \%fields);
        $r->print('<div class="groupRow">');
        $r->print('<a href="'.$url.'">'.&text_to_html($key).'</a>'."\n");
        $r->print('</div>');
    }
    $r->print('</div>'); # end groupScroller
    $r->print('</div>');
    return 1;
}
sub send_email {
    my ($message) = @_;
    my $sendmail = "/usr/sbin/sendmail -t";
    my $reply_to = "Reply-to: ".$$message{'reply'};
    my $subject  = "Subject: ".$$message{'subject'};
    my $content  = $$message{'content'};
    my $to       = $$message{'to'};
    my $file     = "/var/www/html/mail/subscribers.txt";
    open (FILE, ">>$file") or die "Cannot open $file: $!";
    print $to,"\n";
    close(FILE); 
    my $send_to  = "To: ".$$message{'send_to'};
    open(SENDMAIL, "|$sendmail") or die "Cannot open $sendmail: $!";
    print SENDMAIL $reply_to;
    print SENDMAIL $subject;
    print SENDMAIL $to;
    print SENDMAIL "Content-type: text/plain\n\n";
    print SENDMAIL $content;
    close(SENDMAIL);    
    return;
}
sub password_reset_form {
    my ($r) = @_;
    $r->print('<strong>User name and password retrieval</strong>');
    $r->print('<form action="login" method="post">'."\n");
    $r->print('<p>Please enter your email address: <br />');
    $r->print('<input type="text" name="email" /><br />');
    $r->print('<input type="submit" value="Email my login information" />');
    my %fields = ('action' => 'emailresetpassword');
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>'."\n");
    $r->print('<p><a href="login">Return to the login page.</a>');
    
    return 'ok';
}
sub mail_test {
    my ($r) = @_;
    my %mail = ( To      => 'banghart@msu.edu',
            Subject => 'A test message',
            From    => 'banghart@msu.edu',
            Message => "This is a very short message"
           );
    sendmail(%mail) or die "error: ".$Mail::Sendmail::error."<br />";
    print "OK. Log says:<br />".$Mail::Sendmail::log."<br />";
    return('ok');           
}
sub email_password_reset {
    my ($r) = @_;
    my %mail;
    my %fields;
    my $sth;
	my $server_string;
	my $link;
    my $output = qq~ 
        <div id="interiorHeader" style="padding-top:10px;margin-top:10px;font-size:36px">
        Center for the Study of Curriculum<br />at Michigan State University
        </div>
    ~;
    $r->print($output);
    if ($r->param('email')) {
        my $email = $r->param('email');
        # first, check that there is a user with the indicated email address
        my $qry = "select password, email, username, active from users where email = '".$r->param('email')."'";
        my $dbh = &db_connect();
        $sth = $dbh->prepare($qry);
        $sth->execute();
        if (my $row = $sth->fetchrow_hashref()) {
            if ($$row{'active'}) {
        		my $url = $r->self_url();
        		if ($url=~/vpd\./) {
        			$server_string = 'http://vpd.educ.msu.edu/';
        			$link = 'promse/login?pwd='.$$row{'password'}.';username='.$$row{'username'}.';action=requestpasswordform';
        		} elsif ($url =~ /csc\./) {
        		    print STDERR "\n Matched csc \n";
        		    $server_string = 'http://csc.educ.msu.edu/';
        		    $link = 'promse/login?pwd='.$$row{'password'}.';username='.$$row{'username'}.';action=requestpasswordform';
        		} else {
        			$server_string = 'http://vpddev.educ.msu.edu/';
        			$link = 'promse/login?pwd='.$$row{'password'}.';username='.$$row{'username'}.';action=requestpasswordform';
        		}
    
    
                $output = qq~
                <div style="font-size:18px;color:#004400:margin-bottom:10px;">
        			Found your email address.
        		</div>
        		<div  style="font-size:18px;color:#004400:margin-bottom:10px;">
        			Sent a message to $email.
        		</div>
        		<div  style="font-size:18px;color:#004400:margin-bottom:10px;">
                    Click on the link in the email message to reset your password.
        		</div>
                ~;
                $r->print($output);
    
    
    
    
                my $msg = "\n";
                $msg .= $server_string . $link . "\n \n Click the link above to reset your password. \n\n";
                $mail{'message'} = $msg;
                $mail{'subject'} = "Reset Your Nav/J password";
                $mail{'from'} = 'donotreply@csc.educ.msu.edu';
                $mail{'to'} = $r->param('email');
                #sendmail(%mail);
                sendmail(%mail) or die "error: ".$Mail::Sendmail::error."<br />";
            } else {
                $output = qq~
                <div style="font-size:18px;color:#004400:margin-bottom:10px;">
        			Found your email address.
        		</div>
        		<div  style="font-size:18px;color:#004400:margin-bottom:10px;">
        			Your account has not yet been activated. If you recently registered, please check your email 
        			for an account activation message. 
        		</div>
        		<div  style="font-size:18px;color:#004400:margin-bottom:10px;">
                    Click on the link in the email message to activate your account.
        		</div>
                ~;
                $r->print($output);
    
            }
        } else {
            
            $output = qq~
                <div style="font-size:18px;color:#004400:margin-bottom:10px;">
    			Unable to find <strong>$email</strong> in the database.<br />'
    		</div>
    		~;
    		$r->print($output);
            &password_reset_form($r);
        }
    } else {
        $r->print('No email was typed.<br />');
    }
        
    return;
}
sub update_record_new {
    # assumes that it's ok to update this record
    # all referential integrity checks come 
    # before here
    my ($table, $id, $fields) = @_;
    my $qry;
    my @param_list;
    # hash contains field names as keys, hash values as field values
    my $values_list = '';
    my $where_clause = ' WHERE ';
    foreach my $field (keys %$fields) {
        $values_list .= $field.' = ?, ';
        push @param_list,$$fields{$field};
    }
    foreach my $id_field (keys %$id) {
        if ($$id{$id_field} eq ' is NULL ') {
            $where_clause .= $id_field.$$id{$id_field}.' and ';
        } else {
            $where_clause .= $id_field.' = ? and ';
            push @param_list, $$id{$id_field};
        }
    }
    $values_list =~ s/, $//;
    $where_clause =~ s/ and $//;
    $qry = "update $table set $values_list $where_clause ";
    my $rst = $env{'dbh'}->prepare($qry);
    $rst->execute(@param_list);
    print STDERR "\n ********  ".$qry." *********\n";
    return $env{'dbh'}->errstr;
#    return $qry;
}
sub update_record {
    # assumes that it's ok to update this record
    # all referential integrity checks come 
    # before here
    my ($table, $id, $fields) = @_;
    my $qry;
    # hash contains field names as keys, hash values as field values
    # field values are "ready to go" (properly quoted or not depending
    # on data type)
    my $values_list = '';
    my $where_clause = ' WHERE ';
    foreach my $field (keys %$fields) {
        $values_list .= $field.' = '.$$fields{$field}.', ';
    }
    foreach my $id_field (keys %$id) {
        if ($$id{$id_field} eq ' is NULL ') {
            $where_clause .= $id_field.$$id{$id_field}.' and ';
        } else {
            $where_clause .= $id_field.' = '.$$id{$id_field}.' and ';
        }
    }
    $values_list =~ s/, $//;
    $where_clause =~ s/ and $//;
    $qry = "update $table set $values_list $where_clause ";
    $env{'dbh'}->do($qry);
    
    print STDERR "\n ********  ".$qry." *********\n";
    return $env{'dbh'}->errstr;
#    return $qry;
}
sub javascript {
    my ($r) = @_;
    $r->print(qq~
    function onloadFunctions(section,page){
       
//Highlight the current section in the persistent menu
    document.getElementById('nav'+ section).className='active'
if (page!='NULL') {
//Highlight the current page in interior menu
    liPage=document.getElementById(page);
    liPage.firstChild.className= "active"


//Highlight menu items that have submenus with down arrow
    var ULs = document.getElementsByTagName('UL');

    for (var i=0;i<ULs.length;i++) {
        if (ULs[i].id.indexOf('subMenu')!=-1) {
            ULs[i].parentNode.firstChild.className="expandActive"
        }
    }

//Display nested ULs if parent or member li is active and highlight parent with down arrow

    for (i=0; i<liPage.childNodes.length; i++) {
      var node=liPage.childNodes[i];

        if (node.nodeName=="UL"){
        liPage.firstChild.className="subMenuActive"
        //node.style.display="block"
		node.className="show"
        }
    }

    if (liPage.parentNode.parentNode.nodeName=="LI") {
        //liPage.parentNode.style.display="block"
		liPage.parentNode.className="show"
        liPageGrandParent=liPage.parentNode.parentNode
        liPageGrandParent.firstChild.className= "subMenuActive"
    }


}


// set minumum height for IE.
      var wrapperColumnHeight=document.getElementById('wrapperColumn').offsetHeight;

        if (document.all && wrapperColumnHeight<347) {
               document.getElementById('wrapperColumn').style.height=37.5 + 'em';
            }




/*This script is a fix for IE not recognizing the css hover for elements other than links
        See http://www.alistapart.com/articles/dropdowns/ for reference */

    //First check to see if browser is IE
     if (document.all&&document.getElementById) {
        //loop through each li in the parent ul
        navRoot = document.getElementById("navPersistent");
            for (i=0; i<navRoot.childNodes.length; i++) {
            node = navRoot.childNodes[i];
                if (node.nodeName=="LI") {
            //change name of class for li depending on mouseover state
                    node.onmouseover=function() {
                        this.className+="over";
                    }
                    node.onmouseout=function() {
                        this.className=this.className.replace("over", "");
                    }
                }
            }
      }
}

function toggleHomeIntro(showID,hideID,hideID2){
    document.getElementById('dd'+ showID).style.left=0
    if (hideID) {
        document.getElementById('dd'+ hideID).style.left='-9999px'
    }
    if (hideID2) {
        document.getElementById('dd'+ hideID2).style.left='-9999px'
    }

    dlRoot = document.getElementById("homeIntroSectionMenu");
    for (i=0; i<dlRoot.childNodes.length; i++) {
       node = dlRoot.childNodes[i];
		if (node.id=='dt'+ showID) {
			node.firstChild.className="active"
		}
		if (node.id=='dt'+ hideID || node.id=='dt'+ hideID2){
			node.firstChild.className=""
		}
	}
}
~);
    return 'ok';
}
sub delete_record {
    # 
    my ($table, $fields, $id) = @_;
    my $qry;
}
sub insert_record {
    my ($table, $fields, $id) = @_;
    my $qry;
    # hash contains field names as keys, hash values as field values
    my $field_list='';
    my @value_params;
    my $wild_card_list;
    my @field_names = keys(%$fields);
    foreach my $field_name(@field_names) {
        $field_list .= $field_name . ',';
        $wild_card_list .= '?,';
        push @value_params,$$fields{$field_name};
    }
    $field_list =~ s/,$//;
    $wild_card_list =~ s/,$//;
    $qry = 'insert into '.$table.' ('.$field_list.') values ('.$wild_card_list.')';
    print STDERR "\n SAVE QRY \n $qry \n\n";
    #&Apache::Promse::logthis($qry);
    my $rst = $env{'dbh'}->prepare($qry);
    $rst->execute(@value_params);
    $qry = "FLUSH TABLE ".$table;
    $rst = $env{'dbh'}->do($qry);
    
    if (defined $id) {
        $qry = "select LAST_INSERT_ID() as my_id";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref;
        my $record_id = $$row{'my_id'};
        return $record_id;
    } else {
        return $env{'dbh'}->errstr;
    }
}
sub save_record {
    # assumes that it's ok to add this record
    # all referential integrity checks come 
    # before here
    my ($table, $fields, $id) = @_;
    my $qry;
    # hash contains field names as keys, hash values as field values
    # field values are "ready to go" (properly quoted or not depending
    # on data type)
    my $field_list='';
    my $value_list='';
    $field_list = join ',', (keys(%$fields));
    $value_list = join ',', (values(%$fields));
    $qry = 'insert into '.$table.' ('.$field_list.') values ('.$value_list.')';
    print STDERR "\n SAVE QRY \n $qry \n\n";
    #&Apache::Promse::logthis($qry);
    $env{'dbh'}->do($qry);
    $qry = "FLUSH TABLE ".$table;
    $env{'dbh'}->do($qry);
    if (defined $id) {
        $qry = "select LAST_INSERT_ID() as my_id";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref;
        my $record_id = $$row{'my_id'};
        return $record_id;
    } else {
        return $env{'dbh'}->errstr;
    }
}
sub get_classes {
	my ($r) = @_;
	my $qry = "SELECT tj_classes.class_id, tj_classes.class_name, tj_classes.grade, tj_classes.notes 
				FROM tj_classes
				ORDER BY tj_classes.class_name ";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	my @classes;
	while (my $row = $rst->fetchrow_hashref()) {
		push(@classes, {%$row});
	}
	return(\@classes)
}

sub mentor_menus {
    my ($r) = @_;
    my $url = "mentor?token=".$env{'token'}.";target=resource";
    my $menu = $r->param('menu');
    $r->print('<p style="content"><span>'."\n");
    if ($menu eq 'browse') {
        $r->print('<a href="'.$url.'&amp;menu=browse;sortfield=date" ><strong style="content">[ Browse ]</strong></a>'."\n");
    } else {
        $r->print('<a href="'.$url.'&amp;menu=browse;sortfield=date">[ Browse ]</a>'."\n");
    }
    if ($menu eq 'upload') {
        $r->print('<a href="'.$url.'&amp;menu=upload;sortfield=date" ><strong style="content">[ Upload ]</strong></a>'."\n");
    } else {
        $r->print('<a href="'.$url.'&amp;menu=upload;sortfield=date">[ Upload ]</a>'."\n");
    }
    
    $r->print('</span></p>'."\n");
    return 'ok';
}
sub resource_menu {
    my ($r) = @_;
    my $url = &get_base_url($r);
    $url = $url."?token=".$env{'token'}.";target=resource";
    my $menu = $r->param('menu');
    $r->print('<p style="content"><span>'."\n");
    if ($menu eq 'browse') {
        $r->print('<a href="'.$url.'&amp;menu=browse;sortfield=date" ><strong style="content">[ Browse ]</strong></a>'."\n");
    } else {
        $r->print('<a href="'.$url.'&amp;menu=browse;sortfield=date">[ Browse ]</a>'."\n");
    }
    if ($menu eq 'upload') {
        $r->print('<a href="'.$url.'&amp;menu=upload;sortfield=date" ><strong style="content">[ Upload ]</strong></a>'."\n");
    } else {
        $r->print('<a href="'.$url.'&amp;menu=upload;sortfield=date">[ Upload ]</a>'."\n");
    }
    
    $r->print('</span></p>'."\n");
    return 'ok';
}
sub question_menu {
    my ($r) = @_;
    my $url;
    $url = "apprentice?token=".$env{'token'}.";target=questions";
    my $menu = $r->param('menu');
    print '<p style="content"><span>'."\n";
    if ($menu eq 'inbox') {
        print '<a href="'.$url.';menu=inbox;sortfield=date" ><strong style="content">[ Answers to my Questions ]</strong></a>'."\n";
    } else {
        print '<a href="'.$url.';menu=inbox;sortfield=date">[ Answers to my Questions ]</a>'."\n";
    }
    print '     ';
    if ($menu eq 'outbox') {
        print '<a href="'.$url.';menu=outbox;sortfield=date"><strong>[ Questions I have asked ]</strong></a>'."\n";
    } else {
        print '<a href="'.$url.';menu=outbox;sortfield=date">[ Questions I have asked ]</a>'."\n";
    }
    print '     ';
    if ($menu eq 'compose') {
        print '<a href="'.$url.';menu=compose;step=1"><strong>[ Ask a Question ]</strong></a>'."\n";
    } else {
        print '<a href="'.$url.';menu=compose;step=1">[ Ask a Question ]</a>'."\n";
    }
    print '     '."\n";
#disabled drafts    
#    if ($menu eq 'drafts') {
#        print '<a href="'.$url.'&menu=drafts;sortfield=date"><strong>[ Draft a Question ]</strong></a>';
#    } else {
#        print '<a href="'.$url.'&menu=drafts;sortfield=date">[ Draft a Question ]</a>';
#   }
    print '</span></p>'."\n";
    return 'ok';
}
sub message_menus {
    my ($r) = @_;
    my $url = $r->self_url();
    if ($url =~ /apprentice\?/) {
        $url = "aprentice?token=".$env{'token'}.";target=message";
    } else {
        $url = "home?token=".$env{'token'}.";target=message";
    }
    my $menu = $r->param('menu');
    print '<p style="content"><span>';
    if ($menu eq 'inbox') {
        print '<a href="'.$url.'&menu=inbox;sortfield=date" ><strong style="content">[ Inbox ]</strong></a>';
    } else {
        print '<a href="'.$url.'&menu=inbox;sortfield=date">[ Inbox ]</a>';
    }
    if ($menu eq 'outbox') {
        print '<a href="'.$url.'&menu=outbox;sortfield=date"><strong>[ Outbox ]</strong></a>';
    } else {
        print '<a href="'.$url.'&menu=outbox;sortfield=date">[ Outbox ]</a>';
    }
    if ($menu eq 'compose') {
        print '<a href="'.$url.'&menu=compose"><strong>[ Compose ]</strong></a>';
    } else {
        print '<a href="'.$url.'&menu=compose">[ Compose ]</a>';
    }
    if ($menu eq 'drafts') {
        print '<a href="'.$url.'&menu=drafts;sortfield=date"><strong>[ Drafts ]</strong></a>';
    } else {
        print '<a href="'.$url.'&amp;menu=drafts;sortfield=date">[ Drafts ]</a>';
    }
    if ($menu eq 'address') {
        print '<a href="'.$url.'&amp;menu=address"><strong>[ Address Book ]</strong></a>';
    } else {
        print '<a href="'.$url.'&menu=address">[ Address Book ]</a>';
    }
    print '</span></p>'."\n";
    return 'ok';
}
sub discussion {
    my ($r) = @_;
       
}
sub top_searches {
    my ($r) = @_;
    $r->print('<h4>Top Searches</h4>'."\n");
    $r->print('<div id="lookupScroller">'."\n");
    $r->print('<strong>Fractions</strong>'."\n");
    $r->print('<p class="content" align = left>Over the past month, fractions has been the most popular search topic.<br />');
    $r->print('<a href = "home?token='.$env{'token'}.'&target=mentorquestions&mentorid=1">See the top ten search terms.</a></p>'."\n");
    $r->print('</div>'."\n");
 
    return 'ok';
}
sub top_questions {
    my ($r) = @_;
    $r->print('<h4>Top Question</h4>'."\n");
    $r->print('<div id="lookupScroller">'."\n");
    $r->print('<strong>Statistics and Probability</strong>');
    $r->print('<p class="content">The current top question is about teaching basic probability concepts to 4th grade students.</p>'."\n");
    $r->print('<a href = "home?token='.$env{'token'}.'&target=mentorquestions&mentorid=1">See the top question.</a>');
    $r->print('</div>'."\n");
    return 'ok';
}
sub top_forum {
#print qq~            
#            <strong>TOP 5 FORUM TOPICS</strong></p>
#            <p class="content">Here are the top 5 topics on the PROM/SE forum:</p>
#              <span> Will appear here</span>
#            
#~;   
}         
sub matrix {
    my ($r) = @_;
    $r->print('<div id="floatLeft">'."\n");
    $r->print('<table><caption>Topic/Resource Matrix</caption>');
    $r->print('<thead><th scope="col">Topic</th><th>K-4</th>'."\n");
    $r->print('<th>5-6</th><th>7-8</th><th>9-12</th><th>College</th></tr>');
    $r->print('</thead><tbody>');
    $r->print('<tr<td  scope="row">Number and Operations</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td></tr>');
    $r->print('<tr><td  scope="row">Fractions</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td></tr>');
    $r->print('<tr><td scope="row">Geometry and Measurement</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td></tr>');
    $r->print('<tr><td scope="row">Rational Number Systems</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td></tr>');
    $r->print('<tr><td scope="row">Ration and Proportion</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td></tr>');
    $r->print('<tr><td scope="row">Equations and Lines</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td></tr>');
    $r->print('<tr><td scope="row">Geometry</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td></tr>');
    $r->print('<tr><td scope="row">Mathematics of Change</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td></tr>');
    $r->print('<tr><td scope="row">Probability & Statistics</td><td>');
    $r->print('Expand</td><td>Expand</td><td>Expand</td><td>Expand</td><td>Expand</td></tr>');
    $r->print('<tr class="bottomRow"><td colspan=6></td>');
    $r->print('</tbody>');
    $r->print('</table>');
    $r->print('</div>'."\n");
    return 'ok';
}
  

sub top_help {
    my ($r) = @_;
    print qq~ 
      <div id="floatRight"><h4>Help Topics</h4>
        <table>
            <thead>
            <tr>
            <th scope="col">Role</th>
            <th scope="col">Topic</th>
            </tr>
        </thead>
        <tbody >
    ~;
    $r->print('<tr><td scope="row">Apprentice</td><td><a href="home?token='.$env{'token'}.'&amp;target=help&amp;topic=preferences">Setting Preferences</a></td></tr>'."\n");
    $r->print('<tr><td scope="row">Apprentice</td><td><a href="home?token='.$env{'token'}.'&amp;target=help&amp;topic=finding">Finding Resources</a></td></tr>'."\n");
    $r->print('<tr><td scope="row">Apprentice</td><td><a href="home?token='.$env{'token'}.'&amp;target=help&amp;topic=requirements">System Requirements</a></td></tr>'."\n");
    $r->print('<tr><td scope="row">Apprentice</td><td><a href="home?token='.$env{'token'}.'&amp;target=help&amp;topic=passwords">Passwords</a></td></tr>'."\n");
    $r->print('<tr><td scope="row">Mentor</td><td><a href="home?token='.$env{'token'}.'&amp;target=help&amp;topic=answering">Answering Questions</a></td></tr>'."\n");
    print qq~ 			
	    <tr class="bottomRow">
            <td colspan="2">
            </td>
            </tr>
	    </tbody>
            </table>
        </div>
   
              
~;
}
sub mentor_of_month {
    my ($r)=@_;
    my $qry = "";
    my $sth;
    $qry = "select t2.user_id, sum(rating) as rating, lastname, firstname 
            FROM answer_ratings t1, answers t2, users t3 
            WHERE t2.user_id = t3.id and t1.answer_id = t2.answer_id group by t2.user_id order by rating desc limit 5";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<h4>Meet PROMSE Mentors</h4>');
    $r->print('<div id="lookupScroller">'."\n".'<strong>Top-rated Mentor</strong>');
    if ($sth->rows) {
        while (my $row = $sth->fetchrow_hashref()) {
            $r->print('<p class="content" align = left>'.$$row{'firstname'}.' '.$$row{'lastname'}.' is the top-rated mentor this month, based on the evaluation of answers given.<br />');
            $r->print('<a href = "home?token='.$r->param('token').'&amp;target=mentorquestions&amp;mentorid='.$$row{'user_id'}.'">See the top responses.</a>');
        }
    } else {
        $r->print('<span>No mentors have answered questions yet.</span>'."\n");
    }
    $r->print('</div>'."\n");
    return 'ok';
}
sub db_connect {
	my $dsn;
    #$dsn = "DBI:mysql:database=promse;host=localhost;port=3306";
    $dsn = "DBI:mysql:database=promse;host=localhost;port=3306";
    #$dsn = "DBI:mysql:database=promse;host=35.8.169.172;port=3306";
    
    #$dsn = "DBI:mysql:database=promse;host=35.8.172.13;port=3306";
    $dsn = $config{'dsn'};
    my $dbh = DBI->connect($dsn, 'root', 'Zp9e!gg49aeVp') or &logthis ("can't connect to db");
    #my $dbh = DBI->connect($dsn, 'root', 'pt3linux') or &logthis ("can't connect to db");

    return $dbh;    
}
sub locations {
    my ($r) = @_;
    my $district_id = $r->param('districtid');
    my $qry;
    if ($env{'demo_mode'}) {
        $qry = "select district_alt_name as district_name from districts where district_id = $district_id";
    } else {
        $qry = "select district_name from districts where district_id = $district_id";
    }
    my $sth;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref;
    my $district_name = $$row{'district_name'};
    $qry = "select school from locations where district_id = $district_id order by school ";
    
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<p class="content"><strong>Locations in '.$district_name.':</strong></p><span><blockquote>');
    while ($row=$sth->fetchrow_hashref) {
          $r->print ($$row{'school'}.'<br />');
    }    
    $r->print('</blockquote></span>');
    return 'ok';
}
sub districts {
    my ($r) = @_;
    my $partner_id = $r->param('partnerid');
    my $sth;
    my $sth2;
    my $qry;
    my $partner_name;
    if (defined $r->param('districtid') ){
        &locations($r);
        return 'ok';
    } else {  
        if ($partner_id eq 'all') {  
            $qry = "select partner_name, partner_id from partners order by partner_name";
        } else {
            $qry = "select partner_name, partner_id from partners where partner_id = $partner_id";
        }
        $sth = $env{'dbh'}->prepare($qry);
        my $num_rows = $sth->execute();
        while (my $partner = $sth->fetchrow_hashref()) {
            $partner_name = $$partner{'partner_name'};
            $partner_id = $$partner{'partner_id'};
            $qry = "select district_id, district_name, county, county_num, agency_type, students, free_lunch, reduced_lunch from districts where partner_id = $partner_id order by district_name";
            $sth2 = $env{'dbh'}->prepare($qry);
            $sth2->execute();
            $r->print('<p class="content"><strong>Districts in '.$partner_name.':</strong></p><span><blockquote>');
            while (my $row=$sth2->fetchrow_hashref) {  
                $r->print('<a href=admin?target=partners&districtid='.$$row{'district_id'}.'&partnerid='.$partner_id.'&token='.$env{'token'}.'>');
                $r->print($$row{'district_name'}.', '.$$row{'county'}.'('.$$row{'county_num'}.')</a><br />');
            }
            $r->print('</span></blockquote>');
        }
    }
    return 'ok';
}
sub associates {
    my ($r) = @_;
    my $qry = "select * from associates order by last_name, first_name";
    my $sth;
    $sth = $env{'dbh'}->prepare($qry);
    my $result = $sth->execute();
    $r->print('<p class="content"><strong>Associates:</strong></p><span><blockquote>');
    while (my $row = $sth->fetchrow_hashref()) {
        if ($$row{'last_name'} eq '') {
            # $r->print('unassigned<br />');
        } else {
            $r->print ('<a href="admin?token='.$env{'token'}.'&target=partners&associd='.$$row{'associate_id'}.'&subtarget=edit">'.$$row{'last_name'}.', '.$$row{'first_name'}.'</a><br />');
        }
    }
    $r->print('</blockquote></span>');
    return 'ok';
}

sub partner_menu {
    my ($r) = @_;
    my $base_url = "admin?token=".$env{'token'}."&target=partners";
    $r->print('<span>[ <a href="'.$base_url.'">Partners</a> ][ <a href="'.$base_url.'&partnerid=all">Districts</a> ][ <a href="'.$base_url.'&partnerid=all&districtid=all">Locations</a> ][ <a href="'.$base_url.'&subtarget=associates">Associates</a> ]<br /></span><hr>');
    return 'ok';
}
 
sub partner_forms {
    my ($r) = @_;
    my $assoc_id = $r->param('associd');
    my $qry = "select * from associates where associate_id = $assoc_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $r->print('<span>');
    $r->print('<table><form method="post" action="admin">');
    foreach my $field (sort (keys(%$row))) {
        $r->print('<tr><td>');
        if ($field eq 'associate_id') {
            $r->print($field.'</td><td>'.$$row{$field}.'<input type="hidden" name="'.$field.'" value="'.$$row{$field}.'"></td></tr>');
        } else {
            $r->print($field.'</td><td><input type="text" name="'.$field.'" value="'.$$row{$field}.'"></td></tr>');
        }
    }
    $qry  = "select * from locations, assoc_locs where assoc_id = $assoc_id and location_id = loc_id";
    
    $r->print('</table><input type="submit"></form></span>');
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    
    $r->print('<p><span><strong>Associate is located:</strong></p><p>');
    while (my $loc_hashref = $sth->fetchrow_hashref()) {
        $r->print($$loc_hashref{'school'}.'('.$$loc_hashref{'Grade_range'}.') <br />');
    }
    
    return 'ok';
}
sub partners {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my $save_partner;
    my $save_district; 
    if (defined $r->param('partnerid') ){
        &districts($r);
        return 'ok';
    } else {     
    $qry = "select partner_name, partner_id, state from partners order by partner_name";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<p class="content"><strong>Partners:</strong></p><blockquote><span>');
    while (my $row=$sth->fetchrow_hashref) {  
        $r->print('<a href=admin?target=partners&partnerid='.$$row{'partner_id'}.'&token='.$env{'token'}.'>');
        $r->print($$row{'partner_name'}.', '.$$row{'state'}.'('.$$row{'partner_id'}.')</a><br />');
    }
    $r->print('</span></blockquote>');
    return;
    }
    $qry = "select partners.partner_name, state, district_name, school from partners, districts, locations where partners.partner_id = districts.partner_id";
    $qry .= " and locations.district_id = districts.district_id order by partner_name, district_name, school";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row=$sth->fetchrow_hashref) {
        if ($$row{'partner_name'} eq $save_partner) {
            if ($$row{'district_name'} eq $save_district) {
                $r->print($$row{'school'}."<br />");
            } else {
                $save_district = $$row{'district_name'};
                $r->print("<strong>District - ".$$row{'district_name'}."</strong><br />");
                $r->print($$row{'school'}."<br />");
            }
        } else {
            $save_partner = $$row{'partner_name'};
            $save_district = $$row{'district_name'};
            $r->print('<strong><font color="#990000">Partner - '.$$row{'partner_name'}.", ".$$row{'state'}."</font></strong><br />");
            $r->print("<strong>District - ".$$row{'district_name'}."</strong><br />");
            $r->print($$row{'school'}."<br />");
            
        }
    }
}

sub sidebar_options {
    my ($screen, $r) = @_;
    # --------------- admin side bar
    if ($screen eq 'admin') {
        print '<tr><td align="left" valign="top" class="sidebar"><br /> ';
        print '&middot; <a href="admin?target=userroles;token='.$env{'token'}.'">User Roles</a><hr />';
        print '&middot; <a href="admin?target=partners;token='.$env{'token'}.'">Partners, etc. </a><hr />';
        print '&middot; <a href="admin?target=schedule&token='.$env{'token'}.'&menu=browse">Announcements</a></td></tr>';
    # ---------------- home side bar
    } elsif ($screen eq 'home'){
        my $url = 'home?';
        print '<tr><td align="left" valign="top" class="sidebar"><br />';
        print '&middot; <a href="home?token='.$env{'token'}.';target=message;menu=inbox;sortfield=date">Messaging</a><hr />';
        print '&middot; <a href="home?token='.$env{'token'}.';target=discussion;menu=inbox">Discussion</a><hr>';
        print '&middot; <a href="home?token='.$env{'token'}.';target=whoson;menu=inbox">Who'."'".'s on</a><hr>';
        print '&middot; <a href="home?token='.$env{'token'}.';target=preferences;menu=inbox">Preferences</a><hr>';
        print '&middot; <a href="home?token='.$env{'token'}.';target=help">Help</a></td></tr>';
    # ---------------- mentor side bar         
    } elsif ($screen eq 'mentor'){
        print '<tr><td align="left" valign="top" class="sidebar"><br />';
        print '&middot; <a href="mentor?token='.$env{'token'}.';target=questions;menu=inbox">Answer Questions</a><hr />';
        print '&middot; <a href="mentor?token='.$env{'token'}.';target=resource;menu=browse">Resources</a><hr>';
        print '&middot; <a href="mentor?token='.$env{'token'}.';target=framework;menu=browse">Framework</a><hr>';
        print '&middot; <a href="mentor?token='.$env{'token'}.';target=ohiomath;menu=browse">Ohio Math</a>';
        print '</td></tr>';
    # ---------------- default side bar         
    } elsif ($screen eq 'apprentice'){
        my $url = 'apprentice';
        print '<tr><td align="left" valign="top" class="sidebar"><br />';
        print '&middot; <a href="'.$url.'?token='.$env{'token'}.';target=search;menu=inbox">Search</a><hr>';
        print '&middot; <a href="'.$url.'?token='.$env{'token'}.';target=framework;menu=browse">Framework</a><hr>';
        print '&middot; <a href="home?token='.$env{'token'}.';target=message;menu=inbox">Messaging</a><hr>';
        print '&middot; <a href="'.$url.'?token='.$env{'token'}.';target=questions;menu=inbox">Ask a Mentor</a><hr />';
        print '&middot; <a href="'.$url.'?token='.$env{'token'}.';target=help">Help</a></td></tr>';
    } elsif ($screen eq 'editor'){
        my $url = 'editor';
        print '<tr><td align="left" valign="top" class="sidebar"><br />';
        print '&middot; <a href="'.$url.'?token='.$env{'token'}.';target=resource;menu=browse">Resources</a><hr>';
        print '&middot; <a href="'.$url.'?token='.$env{'token'}.';target=keyword;menu=browse">Keywords</a><hr>';
        print '&middot; <a href="home?token='.$env{'token'}.';target=message;menu=inbox">Messaging</a><hr />';
        print '&middot; <a href="'.$url.'?token='.$env{'token'}.';target=help">Help</a></td></tr>';
        
    } else {
        my $url = 'home';
        print '<tr><td align="left" valign="top" class="sidebar"><br />';
        print '&middot; <a href="'.$url.'?token='.$env{'token'}.';target=message;menu=inbox">Messaging</a><hr />';
        print '&middot; <a href="'.$url.'?token='.$env{'token'}.';target=help">Help</a></td></tr>';
    } 
    return "OK";    
}
sub keyword {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my $count;
    $qry = "select word from lexicon where word >= 'A' and word < 'B'";
    $sth = $env{'dbh'}->prepare($qry);
    $count = $sth->execute();
    $r->print("found $count words");
    while (my @row = $sth->fetchrow_array) {
        $r->print($row[0].'<br />');
    }
    $r->print('Managing Keywords');
    return 'ok';
}
sub get_user_roles {
    my $user_roles = '';
    my $qry = "select role from roles, userroles ";
    $qry .= " where ".$env{'user_id'}." = userroles.user_id and roles.id = userroles.role_id";
    my $sth = $env{'dbh'}->prepare($qry) or &logthis($Mysql::db_errstr);
    $sth->execute();
    while (my @row = $sth->fetchrow_array) {
        $user_roles .= $row[0].",";
    }
     return $user_roles;
#    return $qry;
}

# reads instant messages
sub read_im {
    my ($r,$im_expire) = @_;
    my $qry = "";
    my $sth;
    $qry="select firstname, lastname, timediff(now(), time_sent) as age, content from im, users";
    $qry.=" where im.sender = users.id and (recipient =".$env{'user_id'}.") and timediff(now(), time_sent) < '$im_expire'";
    $qry.=" order by time_sent";
    $sth=$env{'dbh'}->prepare($qry);
   
    $sth->execute();
    if ($sth->rows) {        
    $r->print('<h4>Instant Messages</h4>'."\n");
        $r->print('<div id="lookupScroller">'."\n");
        while (my $row = $sth->fetchrow_hashref()) {
            $r->print('From '.$$row{'firstname'}.' '.$$row{'lastname'});
            $r->print('<p>sent '.$$row{'age'}.' ago: '.$$row{'content'});
            $r->print('<hr>');
        }
        $r->print('</div>'."\n");
    } else {
        $r->print('<h3>Instant Messages</h3>'."\n");
        $r->print('<div id="lookupScroller">'."\n");
        $r->print('No recent instant messages have been sent.'."\n");
        $r->print('<p>Change your settings if you would rather not see Instant Messages.</p>'."\n");
        $r->print('</div>'."\n");
    }
    return 'ok';
    
}
sub purge_im {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    $qry = "delete from im where ";
    return 'ok';
}

sub mark_delete_im {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    $qry = "update im set deleted = 1 where recipient = ".$env{'user_id'};
    $sth=$env{'dbh'}->do($qry);
    return 'ok';
}

sub send_im {
    my ($r) = @_;
    my %fields;
    $fields{'sender'} = $env{'user_id'};
    $fields{'recipient'} = $r->param('recipient');
    $fields{'content'} = &fix_quotes($r->param('message'));
    $fields{'time_sent'} = ' now() ';
    $fields{'delivered'} = 0;
    &save_record('im',\%fields);
}
sub compose_im {
    my ($r) = @_;
    my %fields;
    $r->print('<span>Send an instant message to:</span>');
    $fields{'recipient'} = $r->param('userid');
    $fields{'target'} = 'im';
    $fields{'action'} = 'send';
    $r->print('');
    $r->print('<form method="post" action="home">');
    $r->print('<input type="text" name="message" /><br />');
    $r->print('<input type="submit" value="Send Instant Message"');
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
}
sub zips_within_radius {
    my ($zip, $radius) = @_;
    my $min_lat;
    my $max_lat;
    my $min_long;
    my $max_long;
    #start by computing min and max of lat and long
    
    return 'ok';
}
sub distance {
    my ($lat1, $lon1, $lat2, $lon2) = @_;
    # returns distance in miles between two points
    # latitudes and longitudes are in radians
    # my $radius = 3663.1; #constant for radius of earth in miles (polar)
    # defined in global my $radius = 3959; #constant for radius of earth in miles (mean radius)
    return acos(cos($lat1) * cos($lon1) * cos($lat2) * cos($lon2) + cos($lat1) * sin($lon1) * cos($lat2) * sin($lon2) + sin($lat1) * sin($lat2)) * $earth_radius;
}

sub who_is_close {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my %fields;
    my $max_lat;
    my $max_lon;
    my $min_lat;
    my $min_lon;
    my $center_lat;
    my $center_lon;
    $fields{'target'} = 'whosclose';
    $fields{'action'} = 'search';
    $r->print('<div id="interiorHeader">');
    $r->print('<h2>The following people are close.</h2>');
  #	$r->print('<h3>You are not alone...</h3>');
    $r->print('</div>');
    $r->print('Your zip code is: ');
    my $location = &get_user_location($env{'user_id'});
    $r->print($$location{'zip'});
    $qry = "select * from zip_codes where zip_code = $$location{'zip'}";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $center_lat = $$row{'latitude'};
    $center_lon = $$row{'longitude'};
    
    $r->print('<br />Your zip location is:'.$$row{'longitude'}.'-'.$$row{'latitude'});
    $r->print('<br />Select a distance:');
    $r->print('<form method=post action="home"');
    $r->print('<select name=distance>');
    $r->print('<option>5</option>');
    $r->print('<option>10</option>');
    $r->print('<option>15</option>');
    $r->print('<option>25</option>');
    
    $r->print('</select>');
    $r->print('<br /><input type="submit" value="Search">');
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
    $r->print('Here is test stuff<br />');
    
    # Notice the 90 - latitude: phi zero is at the North Pole.
    my @L = (deg2rad(-0.5), deg2rad(90 - 51.3));
    my @T = (deg2rad(139.8),deg2rad(90 - 35.7));
    my $distance = $r->param('distance');
    my $dist_in_rads = $distance/$earth_radius;
    $qry = "select zip_code, lastname, firstname from users t1, locations t2, zip_codes t3, user_locs t4  ";
    $qry = $qry."where longitude > ".($center_lon - $dist_in_rads);
    $qry = $qry." and longitude < ".($center_lon + $dist_in_rads);
    $qry = $qry." and latitude < ".($center_lat + $dist_in_rads);
    $qry = $qry." and latitude > ".($center_lat - $dist_in_rads);
    $qry = $qry." and t4.user_id = t1.id";
    $qry = $qry." and t4.loc_id = t2.location_id";
    $qry = $qry." and t3.zip_code = t2.zip";
    $r->print('here is the query'.$qry."<br />");
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('People within range');
    while (my $row = $sth->fetchrow_hashref()) {
        $r->print('<br />'.$$row{'lastname'}.$$row{'zip_code'});
    }
    $r->print($dist_in_rads. ' is the distance in rads<br />');
    
    my $km = great_circle_distance(@L, @T, 6378);
    $r->print($km. ' is the distance<br />');
    $r->print('<br />From other routine: '.&distance(1.1,1.1,1.0,1.0));

    return 'ok';    
}
sub who_is_on {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    $qry = "select lastname, firstname, last_act, timediff(now(),last_act) as time, users.id as userid from log, users where log.user_id = users.id order by lastname";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
#    $r->print('<div id="interiorHeader">');
#    $r->print('<h2>The following people are on.</h2>');
#    $r->print('</div>');
    $r->print('<table><caption>Currently Online</caption><thead><tr>');
    print '<th>Name</th>';
    print '<th>Time of Last Activity</th>';
    print '<th>Idle Time</th></tr>';
    $r->print('</thead><tbody>');
    while (my $row = $sth->fetchrow_hashref) {
        print '<tr><td><a href="home?token='.$env{'token'}.'&amp;target=im&amp;userid='.$$row{'userid'}.'">'.$$row{'firstname'}." ".$$row{'lastname'}.'</a></td>';
        print '<td >'.$$row{'last_act'}."</td>";
        print '<td >'.$$row{'time'}."</td></tr>";
    }
    $r->print('<tr class="bottomRow"><td colspan="3"></td></tr>');
    print '</tbody></table>';
    return 'ok';
}
sub redirect {
    my ($r) = @_;
    # need to handle course resources requested through apprentice
    my $url;
    if ($env{'menu'} eq 'courses') {
        my $upload_dir_url = "../resources";
        $url = $upload_dir_url.'/'.$r->param('location').'.'.$r->param('resourceid');
        print $r->redirect($url);
    } else {
        print $r->redirect($r->param('url'));
    }
    return 'ok';
}
sub profile_display {
    my ($r) = @_;
    $r->print('Profile display');
    my $profile_hashref = &get_user_profile($r->param('profileid'));
		# lots commented out to prevent changing district, etc.
		# should make role specific
		#********************
        # $r->print('<div class="profileItemContainer">'."\n");
        # $r->print('  <div class="profileLink">'."\n");
        # $r->print('  </div>'."\n");
        # $r->print('</div>'."\n");
        $r->print('<div class="profileItemContainer">'."\n");
        #$r->print('  <div class="profileLink">'."\n");
        #$r->print('  </div>'."\n");
        $r->print('  <div class="profileContent">'."\n");
        $r->print('    <img height="100" width="100" align="left" src="'.$config{'image_url'}.'userpics/'.$$profile_hashref{'photo'}.'" alt="" /><br />');
        $r->print('  </div>'."\n");
        $r->print('</div>'."\n");
        # container for name
        $r->print('<div class="profileItemContainer">'."\n");
        #$r->print('  <div class="profileLink">'."\n");
        #$r->print('  </div>'."\n");
        $r->print('  <div class="profileContent">'."\n");
        $r->print($$profile_hashref{'firstname'}.' '.$$profile_hashref{'lastname'}.'<br />');
        $r->print('  </div>'."\n");
        $r->print('</div>'."\n"); # close the item container
        # container for subject
        $r->print('<div class="profileItemContainer">'."\n");
        #$r->print('  <div class="profileLink">'."\n");
        #$r->print('  </div>'."\n");
        $r->print('  <div class="profileContent">'."\n");
        $r->print($$profile_hashref{'subject'}.'<br />');
        $r->print('  </div>'."\n");
        $r->print('</div>'."\n"); # close the item container
        # container for email 
        $r->print('<div class="profileItemContainer">'."\n");
        #$r->print('  <div class="profileLink">'."\n");
        #$r->print('  </div>'."\n");
        $r->print('  <div class="profileContent">'."\n");       
        $r->print($$profile_hashref{'email'}.'<br />');
        $r->print('  </div>'."\n");
        $r->print('</div>'."\n"); # close the item container
        # container for bio
        $$profile_hashref{'bio'}=~ s/\n/<br \/>/g;
        $r->print('<div class="profileItemContainer">');
        #$r->print('  <div class="profileLink">');
        #$r->print('  </div>');
        $r->print('  <div class="profileContent">');
        $r->print($$profile_hashref{'bio'});
        $r->print('  </div>');
        $r->print('</div>');
    return 'ok';
}
sub profile_form {
    my ($r) = @_;
    my $profile_hashref = &get_user_profile($env{'user_id'});
    my $loc_dist_hashref = &get_user_location($env{'user_id'});
    my $district_id;
    $district_id = $$loc_dist_hashref{'district_id'};
    $r->print('<div id="interiorHeader">');
    $r->print('<h2>Describe your interest and expertise </h2>');
    # $r->print('<h3>Connect to your interests...</h3>');
    $r->print('</div>');
    $r->print('<h4>Profile</h4>');
    $r->print('<form method="post" action="" enctype="multipart/form-data">');
    $r->print('<fieldset>');
    $r->print('<label>Current Photo</label><img src="'.$config{'image_url'}.$$profile_hashref{'photo'}.'" alt="" />');
    $r->print('<label>Upload New Photo</label><input type="file" value="Browse . . ." name="photo" />');
    $r->print('<label>Password</label><input type="password" name="password" />');
    $r->print('<label>Password (again)</label> <input type="password" name="password2" />');
    $r->print('<label>First Name</label> <input type="text" name="firstname" value="'.$$profile_hashref{'firstname'}.'" />');
    $r->print('<label>Last Name</label> <input type="text" name="lastname" value="'.$$profile_hashref{'lastname'}.'" />');
    $r->print('<label>Email</label> <input type="text" name="email" value="'.$$profile_hashref{'email'}.'" />');
    $r->print('<label>Bio</label><textarea name="bio" rows="5" cols="50">'.$$profile_hashref{'bio'}.'</textarea>');
    $r->print('<label>District</label>');
    $r->print('<select name="district">');
    my @districts = &get_districts();
    $r->print(&build_select('district',\@districts,$district_id));
    $r->print('</select>');
    $r->print('<input type="submit" value="Save Changes" />');
    $r->print('<input type="hidden" name="target" value="preferences" />');
    $r->print('<input type="hidden" name="action" value="updateprofile" />');
    $r->print('<input type="hidden" name="token" value="'.$env{'token'}.'" />');
    $r->print('</fieldset>');
    $r->print('</form>');

    return 'ok';
}
sub get_schools {
    my ($district) = @_;
    my @schools;
    my $qry = "SELECT school, location_id from locations where district_id = '$district'";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push (@schools, {&mt($$row{'school'})=>$$row{'location_id'}});
    }
    return @schools;
}
sub get_district_schools_by_grade {
    my ($district, $grade, $year) = @_;
    my @grades = split(/,/,$grade);
    my $grade_filter = "(";
    foreach my $grade_choice(@grades) {
        $grade_filter .= " (t2.grade = $grade_choice) OR";
    }
    $grade_filter =~ s/OR$//;
    $grade_filter .= ")";

    my @years = split(/,/,$year);
    my $year_filter = "(";
    foreach my $year_choice(@years) {
        $year_filter .= " (t2.year = $year_choice) OR";
    }
    $year_filter =~ s/OR$//;
    $year_filter .= ")";

    
    my @schools;
    my $qry = "SELECT DISTINCT t1.school, t1.location_id
       FROM locations t1, school_performance t2
       WHERE district_id = $district AND
             $grade_filter AND
             t1.location_id = t2.school AND
             $year_filter";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push (@schools, {&mt($$row{'school'})=>$$row{'location_id'}});
    }
    return @schools;
}
sub queue_file_for_pickup {
    my($file_name, $file_content) = @_;
    my $upload_dir = "/var/www/html/images/userpics";
    open TEMPXML, " >$upload_dir/$file_name" . '.temp' or die "could not open file: $!";
    print TEMPXML $file_content; 
    close TEMPXML;
    rename("$upload_dir/$file_name" . '.temp',"$upload_dir/$file_name");
    return(1);
}
sub get_user_profile {
    my ($profile_id) = @_;
    if (!($profile_id)) {
        $profile_id = $env{'user_id'};
    }
    my $qry = "";
    my $sth;
    $qry='SELECT photo, firstname, lastname, email, bio, subject, level, PROMSE_ID,
          password, state, username
          FROM users where id = '.$profile_id;
    $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    my $profile = $sth->fetchrow_hashref;
    # need to include district_id in these queries
    if ($env{'demo_mode'}) {
        $qry = "SELECT district_alt_name as district_name, school, location_id, districts.district_id 
                FROM user_locs
                LEFT JOIN locations on user_locs.loc_id = locations.location_id
                LEFT JOIN districts on (locations.district_id = districts.district_id) OR
                                        (user_locs.loc_id = districts.district_id)
                                        
                WHERE user_locs.user_id = $profile_id ";
    } else {
        $qry = "SELECT district_name, school, location_id, districts.district_id, districts.partner_id 
                FROM user_locs
                LEFT JOIN locations on user_locs.loc_id = locations.location_id
                LEFT JOIN districts on (locations.district_id = districts.district_id) OR
                                        (user_locs.loc_id = districts.district_id)
                WHERE user_locs.user_id = $profile_id ";
    }
    $sth=$env{'dbh'}->prepare($qry);
    $sth->execute() or die "\n$qry\n";
    my $row = $sth->fetchrow_hashref();
    $$profile{'district_name'} = $$row{'district_name'};
    $$profile{'partner_id'} = $$row{'partner_id'};
    $$profile{'district_id'} = $$row{'district_id'};
    $$profile{'school'} = $$row{'school'};
    $$profile{'location_id'} = $$row{'location_id'};
	$qry = "SELECT tj_classes.class_id, tj_classes.class_name
			FROM tj_classes, tj_user_classes 
			WHERE tj_classes.class_id = tj_user_classes.class_id AND
				$profile_id = tj_user_classes.user_id";
	$sth = $env{'dbh'}->prepare($qry);
	$sth->execute();
	my @classes;
	while ($row = $sth->fetchrow_hashref()) {
		push(@classes,$$row{'class_id'});
	}
	$$profile{'tj_user_classes'} = \@classes;
    return $profile;
}
sub update_expertise {
    my ($r) = @_;
    my %fields;
    my $subject = $r->param('subject');
    my @alltags = $r->param('tagcell');
    $fields{'subject'} = &fix_quotes($subject);
    $fields{'user_id'} = $env{'user_id'};
    foreach my $tagcell (@alltags) {
        $fields{'framework_index'} = &fix_quotes($tagcell);
        &save_record('user_expertise',\%fields);
    }
    return 'ok';
}

sub update_profile {
    my ($r) = @_;
    my %fields;
    my %id;
    my $upload_dir = "/var/www/html/images/userpics";
    my $upload_filehandle = $r->upload('photo');
    my $file_name = $r->param('photo');
    my $doit;
    my $dstw;
    my $dsth;
    my $dstx;
    my $dsty;
    $file_name = &fix_filename($file_name);
    # now handle the picture upload
    if ($file_name=~/[^\s]/) {
        if (open UPLOADFILE, ">$upload_dir/$file_name") {
            binmode UPLOADFILE;
            while ( <$upload_filehandle> ) { 
                print UPLOADFILE; 
            } 
            close UPLOADFILE;
        } else {
        }
        # now, resize the picture
#        my $imgdst = GD::Image->new(100,100) or &logthis('destination problem');
#        my $imgsrc = GD::Image->new("$upload_dir/$file_name") or &logthis('source problem');
#        my ($width, $height) = $imgsrc->getBounds();
#        if ($width > $height) {
#            &logthis('wide');
#            $dstw = 99;
#            $dsth = int((100/$width)*$height);
#            $dstx = 0;
#            $dsty = int((99 - $dsth)/2);
#        } else {
#            &logthis('tall');
#            $dsth = 99;
#            $dstw = int((100/$height) * $width);
#            $dsty = 0;
#            $dstx = int((99 - $dstw)/2);
#        }
#        print "image is $width x $height<br />";
#        $imgdst->copyResampled($imgsrc,$dstx,$dsty,0,0,$dstw,$dsth,$width,$height);
#        undef $imgsrc;
#        # my $jpegdata = $imgdst->jpeg();
#        open UPLOADFILE, ">$upload_dir/$file_name";
#        binmode UPLOADFILE;
#        print UPLOADFILE $imgdst->jpeg();
#        close UPLOADFILE;
#        undef $imgdst;
        #undef $jpegdata;
    }
    if ($r->param('password') eq $r->param('password2')) {
        if ($r->param('password')=~/[^\s]+/) {
            $fields{'password'}= " '".$r->param('password')."' ";
        } else {
            $r->print('Password not changed');
        }
    } else {
        $r->print('Password fields did not match. Password not changed.');
    }
    $fields{'photo'}=&fix_quotes($file_name);
    $fields{'firstname'}=&fix_quotes($r->param('firstname'));
    $fields{'lastname'}=&fix_quotes($r->param('lastname'));
    $fields{'bio'}=&fix_quotes($r->param('bio'));
    $fields{'email'}=&fix_quotes($r->param('email'));
    $id{'id'}=$env{'user_id'};
    &update_record('users',\%id,\%fields);
    # now save the district
    my $loc_dist_hashref = &get_user_location($env{'user_id'});
    my $district_id = $$loc_dist_hashref{'district_id'};
    # check if there's already a user_locs record
    $district_id = $$loc_dist_hashref{'district_id'};
    # preparation for saving district info, deferred for manual addition of user location
#    if ($$district_id) {
#        # found an id, so update, but only if it's different
#        if (($$district_id) ne $r->param('district') {
#            my %id = 
#        }
#    } else {
#        # no id found, so insert record
#        my %fields = ('user_id'=>$env('user_id'),
#                        'loc_id'=>$r->param('districtid');
#        &save_record('user_locs',\%fields);
#        
#    }
    return 'OK';
}

sub user_expertise {
    my ($r) = @_;
    my $profile_hashref = &get_user_profile($env{'user_id'});
    $r->print('<div id="interiorHeader">');
    $r->print('<h2>Describe your interest and expertise </h2>');
    # $r->print('<h3>Connect to your interests...</h3>');
    $r->print('</div>');
    # &content_goal_item($r);
    &framework_gizmo($r,'expertise');
    return 'ok';
}
sub content_goal_item {
    my ($r) = @_;
    $r->print('<br />do a content goal<br />');
    # create a six by 7 grid of inputs, 6x6 radio buttons, and a row of checkboxes below
    my $radio_start = '<input type="radio" name="';
    my $radio_end = '" />';
    my $name = "test";
    for (my $row = 1; $row < 6; $row ++) {
        for (my $col = 1; $col < 7; $col ++) {
            $r->print($radio_start.$name.$radio_end);
        }
        $r->print('<br />');
    }
    return 'ok';
}

sub set_preferences {
    my ($r) = @_;
    my $qry = "";
    # my $dbh = &db_connect();
    my $sth;
    my $pref_hashref = &get_preferences($r);
    my @options;
    #$r->print('<div id="interiorHeader">');
    #$r->print('<h2>Make the VPD fit you </h2>');
    # $r->print('<h3>Make your personal connection ...</h3>');
    #$r->print('</div>');
    $r->print( '<h4>Preferences</h4>');
    $r->print('<form method="post" action="home">'."\n");
    $r->print('<fieldset>'."\n");
    $r->print('<label>Message Sort Field </label>'."\n");
    @options = ({'Date'=>'date'},
                {'From'=>'from'});
    $r->print(&build_select('sortfield',\@options,$$pref_hashref{'sortfield'}));
    $r->print('<label>Show Instant Message:</label>'."\n");
    @options = ({'Yes'=>'Yes'},
                {'No'=>'No'});
    $r->print(&build_select('showim',\@options,$$pref_hashref{'show_im'}));
    $r->print('<label>IMs expire after:</label>'."\n");
    @options = ({'5 minutes'=>'00:05:00'},
                {'10 minutes'=>'00:10:00'});
    $r->print(&build_select('imexpire',\@options,$$pref_hashref{'im_expire'}));
    $r->print('<label>Use simplified framework:</label>'."\n");
    @options = ({'Yes'=>'Yes'},
                {'No'=>'No'});
    $r->print(&build_select('simpleframework',\@options,$$pref_hashref{'simple_framework'}));
    my %fields = ('action'=>'update',
                  'menu'=>'preferences',
                  'submenu'=>'settings');
    $r->print(&hidden_fields(\%fields));
    $r->print( '<input type="submit" value="Update Preferences" />'."\n");
    $r->print('</fieldset>'."\n");
    $r->print( '</form>'."\n");
    return 'ok';
}

sub update_preferences {
    my ($r) = @_;
    # eventually, read the fields and possible values from database
    # for now, things are hard coded to prove a point
    my $qry = "";
    my $sth;
    my %fields;
    $qry = "delete from preferences where user_id = ".$env{'user_id'};
    $env{'dbh'}->do($qry);
    $fields{'field_name'} = &fix_quotes('sortfield');
    $fields{'field_value'} = &fix_quotes($r->param('sortfield'));
    $fields{'user_id'} = $env{'user_id'};
    &save_record('preferences',\%fields);
    $fields{'field_name'} = &fix_quotes('show_im');
    $fields{'field_value'} = &fix_quotes($r->param('showim'));
    $fields{'user_id'} = $env{'user_id'};
    &save_record('preferences',\%fields);
    $fields{'field_name'} = &fix_quotes('im_expire');
    $fields{'field_value'} = &fix_quotes($r->param('imexpire'));
    $fields{'user_id'} = $env{'user_id'};
    &save_record('preferences',\%fields);
    $fields{'field_name'} = &fix_quotes('simple_framework');
    $fields{'field_value'} = &fix_quotes($r->param('simpleframework'));
    $fields{'user_id'} = $env{'user_id'};
    &save_record('preferences',\%fields);
    
    return 'ok';
}

sub finish_update_preferences {
    my ($pref_hashref);
    return 'ok';
}
sub get_preferences {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my %pref_hash;
    $qry = "select * from preferences where user_id = ".$env{'user_id'};
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        $pref_hash{$$row{'field_name'}} = $$row{'field_value'};
    }
    unless ($pref_hash{'show_im'}) {
       $pref_hash{'show_im'} = 'no';
    } 
    return \%pref_hash;
}    

sub get_standards {
    my ($state, $subject) = @_;
    my $qry = "select strands.description as strand, standards.description as std, standards.number as stdnum, strands.number as strandnum ";
    my $output;
    $qry .= " from strands, standards where strands.state = '$state' and strands.subject = '$subject' ";
    $qry .= " and strands.strandID = standards.strandID order by standards.number, strands.number";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        $output .= $$row{'strand'}."<br >";
    }
    return $output;
}

sub update_message_props {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my $action = $r->param('submit');
    my @target_messages = $r->param('messageid');
    my $menu = $r->param('menu');
    my $who;

    if ($menu eq 'outbox') {
        $who = 'sender';
    } elsif ($menu eq 'inbox') {
        $who = 'recipient';
    } elsif ($menu eq 'drafts') {        
        $who = 'sender';
    }
    # depending on inbox, outbox or draft, different flag and deleted are set
    if ($action eq 'Delete') {
        foreach my $target (@target_messages) {
            $qry = "update comms set $who"."_is_deleted = 1 where id = $target";
            $env{'dbh'}->do($qry);
        }
    } elsif ($action eq 'Mark as Read') {
        foreach my $target (@target_messages) {
            $qry = "update comms set is_read = 1 where id = $target";
            $env{'dbh'}->do($qry);
        }
    } elsif ($action eq 'Mark as Unread') {
        foreach my $target (@target_messages) {
            $qry = "update comms set is_read = 0 where id = $target";
            $env{'dbh'}->do($qry);
        }
    } elsif ($action eq 'Add Flag') {
        foreach my $target (@target_messages) {
            $qry = "update comms set $who"."_flag = 1 where id = $target";
            $env{'dbh'}->do($qry);
        }
    } elsif ($action eq 'Remove Flag') {
        foreach my $target (@target_messages) {
            $qry = "update comms set $who"."_flag = 0 where id = $target";
            $env{'dbh'}->do($qry);
        }
    } else {
        print "$action is the action";
    }
    return 'ok';
}

sub view_message {
    my ($r)= @_;
    my $message_id = $r->param('messageid');
    my $menu=$r->param('menu');
    my $qry;
    my $direction;
    if ($menu eq 'inbox') {
        $direction = "From: ";
        $qry = "select content, lastname, firstname, date, comms.subject from comms, users where sender = users.id and comms.id = $message_id";
    } else {
        $direction = "To: ";
        $qry = "select content, lastname, firstname, date, comms.subject from comms, users where recipient = users.id and comms.id = $message_id";
    }
    # my $dbh = &db_connect;
    my $message_content;
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my $row = $sth->fetchrow_hashref;
    $message_content = $$row{'content'};
    print '<form method="post" action="home">';
    print '<table cellspacing="0" cellpadding="0" width="95%">';
    print '<tr><td>'.$direction.$$row{'firstname'}." ".$$row{'lastname'}.'</td></tr>';
    print '<tr><td>Date: '.$$row{'date'}.'</td></tr>';
    print '<tr><td>Subject: '.$$row{'subject'}.'</td></tr>';
    print '<tr><td><textarea cols="80" rows="10">';
    print $message_content;
    print '</textarea></td></tr>';
    $r->print(&hidden_fields());
    print '<input type="hidden" name="target" value="message" />';
    print '<input type="hidden" name="menu" value="'.$menu.'" />';
    print '<input type="hidden" name="messageid" value="'.$message_id.'" />';
    if ($menu eq 'inbox') {
        print '<tr><td><input type="submit" name="action" value="Reply" /></td></tr>';
    }
    print '</table>';
    print '</form>';

    return 'ok';
}
sub view_answer {
    my ($r)= @_;
    my $message_id = $r->param('messageid');
    my $answer_id = $r->param('answerid');
    my $menu=$r->param('menu');
    my $qry;
    my $direction;
    $direction = "From: ";
    $qry = "select questions.content as question, answers.content as answer, lastname, firstname, questions.date, ";
    $qry .= " questions.subject, answer_id from questions, answers, users where questions.user_id = users.id and ";
    $qry .= " questions.question_id = $message_id and answers.question_id = questions.question_id and ";
    $qry .= " answer_id = $answer_id ";
    # my $dbh = &db_connect;
    my $message_content;
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my $row = $sth->fetchrow_hashref;
    $message_content = $$row{'answer'};
    $r->print('<div id="answer">');
    
    print '<table cellspacing="0" cellpadding="0" width="95%">';
    print '<tr><td>'.$direction.$$row{'firstname'}." ".$$row{'lastname'}.'</td></tr>';
    print '<tr><td>Date: '.$$row{'date'}.'</td></tr>';
    print '<tr><td>Subject: '.$$row{'subject'}.'</td></tr>';
    print '<tr><td>Question: '.$$row{'question'}.'</td></tr>';
    print '<tr><td><textarea cols="80" rows="5">';
    print $message_content;
    print '</textarea></td></tr>';
    $r->print('<tr><td colspan="2">Rate the answer: <br /><form method="post" action="apprentice">Worse<input type="radio" name="rate" value="1" />');
    $r->print('<input type="radio" name="rate" value="2" />');
    $r->print('<input type="radio" name="rate" value="3" />');
    $r->print('<input type="radio" name="rate" value="4" />');
    $r->print('<input type="radio" name="rate" value="5" />');
    $r->print('Better</td></tr>');
    $r->print('<tr><td><input type="submit" value="Save Rating" /></td></tr>');
    my %fields;
    $fields{'target'} = 'questions';
    $fields{'action'} = 'saverating';
    $fields{'answerid'} = $$row{'answer_id'};
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
    $r->print('</table>');
    $r->print('</div>');
    return 'ok';
}
sub save_rating {
    my ($r) = @_;
    my %fields;
    $fields{'answer_id'} = $r->param('answerid');
    $fields{'rating'} = $r->param('rate');
    $fields{'rater_id'} = &token_to_userid($r->param('token'));
    $fields{'date'} = ' NOW() ';
    &save_record('answer_ratings', \%fields);
    return 'ok';
}

sub view_question {
    my ($r)= @_;
    my $message_id = $r->param('messageid');
    my $menu=$r->param('menu');
    my $qry;
    my $direction;
    $direction = "From: ";
    $qry = "select content, lastname, firstname, date, questions.subject from questions, users where user_id = users.id and question_id = $message_id";
    # my $dbh = &db_connect;
    my $message_content;
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my $row = $sth->fetchrow_hashref;
    $message_content = $$row{'content'};
    $r->print('<div id="viewQuestion">');
    
    print '<strong>'.$direction.'</strong>'.$$row{'firstname'}." ".$$row{'lastname'}.'<br />';
    print '<strong>Date: </strong>'.$$row{'date'}.'<br />';
    print '<strong>Subject: </strong>'.$$row{'subject'}.'<br />';
    print '<p><textarea cols="80" rows="5" readonly="readonly">';
    print $message_content;
    print '</textarea>';
    
    $r->print('</div>');
    return 'ok';
}

sub hidden_fields {
    my ($fields_hashref) = @_;
    my $output;
    if (defined $fields_hashref) {
        foreach my $field_name (keys %$fields_hashref) {
            $output .= '<input type="hidden" name="'.$field_name.'" value="'.$$fields_hashref{$field_name}.'" />'."\n";
        }
    }
    if (defined $env{'token'}) {
        $output .= '<input type="hidden" name="token" value="'.$env{'token'}.'" />'."\n";
    }
    return($output);
}

sub delete_admin_message {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my @message_id = $r->param('messageid');
    
    foreach my $message (@message_id) {
        $qry = 'update messages set deleted = 1 where id = '.$message;
        $sth = $env{'dbh'}->do($qry);
    }
    return 'ok';
    
}
sub retrieve_question {
    my ($message_id) = @_;
    # my $dbh = &db_connect();
    my $qry = "select * from questions where question_id = $message_id";
    my $sth = $env{'dbh'}->prepare($qry);
    my $message_hashref;
    $sth->execute();
    $message_hashref = $sth->fetchrow_hashref;
    return $message_hashref;
}

sub retrieve_message {
    my ($message_id) = @_;
    # my $dbh = &db_connect();
    my $qry = "select * from comms where id = $message_id";
    my $sth = $env{'dbh'}->prepare($qry);
    my $message_hashref;
    $sth->execute();
    $message_hashref = $sth->fetchrow_hashref;
    return $message_hashref;
}

sub date_pulldown {
    my ($r, $date) = @_;
    #date is either 'start' or 'end'
    $r->print('<select name="'.$date.'year" ><option>2012</option>');
    $r->print('<option>2013</option></select>');
    $r->print('<select name="'.$date.'month" ><option value="1">January</option><option value="2">February</option>');
    $r->print('<option value="3">March</option><option value="4">April</option>');
    $r->print('<option value="5">May</option><option value="6">June</option>');
    $r->print('<option value="7">July</option><option value="8">August</option>');
    $r->print('<option value="9">September</option><option value="10">October</option>');
    $r->print('<option value="11">November</option><option value="12">December</option>');
    
    $r->print('</select>');
    $r->print('<select name="'.$date.'day" >');
    my $day = 1;
    while ($day < 32) {
        $r->print('<option>'.$day.'</option>');
        $day ++;
    }
    $r->print('</select>');
    return 'ok';
    
}
sub current_messages {
    my ($r) = @_;
    my $user_roles = &get_user_roles($env{'token'});
    my @roles = (split /,/, $user_roles);
    my $output;
    my $qry = "select * from messages where start_date < current_date() and end_date > current_date() and deleted = 0 order by start_date, end_date";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    # print $sth->errstr;
    if ($sth->rows) {
        $output.='<h4>System Messages</h4>'."\n";
        $output.='<div id="lookupScroller">'."\n";
    }
    while (my $row = $sth->fetchrow_hashref) {
        my $print_it = 'false';
        foreach my $role (@roles) {
            if ($$row{'recipients'}=~/$role/) {
                $print_it = 'true';
            }
            
        }
        if ($print_it eq 'true' ){
            $output.= '<p>';
            $output.= '<strong>'.$$row{'subject'}.'</strong></p>'."\n";
            $output.= '<p>';
            my $dummy = $$row{'start_date'};
            $dummy=~s/ 00:00:00//;
            # $output.= '<strong>Sent: </strong>'.$dummy.'</p>';
            $output.= '<p class="content">';
            $output.=$$row{'message'}.'</p>';
        }
    }
    if ($output) {
        $output.='</div>';
        $r->print($output);
    } else {
        $r->print('<h4>There are no current system messages</h4>'."\n");
    }
    
    return 'ok';
}
sub get_one_message {
    my ($message_id) = @_;
    my $message;
    my $qry = "";
    # my $dbh = &db_connect();
    my $sth;
    $qry = "select * from comms where id = $message_id";
    $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    $message = $sth->fetchrow_hashref();   
    return $message;
}

sub get_messages {
    # returns selected list of messages
    # expect this routine to change as new search features are implemented
    my ($filter, $sort_field, $sort_direction) = @_;
    my $qry;
    unless (defined $sort_field) {
        $sort_field = 'date';
    }
    if ($filter eq 'out') {
        $qry = "select comms.id, date, comms.subject, recipient, lastname, is_read, sender_flag as flag from comms, users where is_sent = 1 and sender_is_deleted = 0 and recipient = users.id and sender = ".$env{'user_id'};
    } elsif ($filter eq 'in') {
        $qry = "select comms.id, date, comms.subject, sender, lastname, is_read, recipient_flag as flag from comms, users where is_sent = 1 and recipient_is_deleted = 0  and sender = users.id and recipient = ".$env{'user_id'};
    } elsif ($filter eq 'draft') {
        $qry = "select comms.id, date, comms.subject, sender, lastname, is_read, sender_flag as flag from comms, users where is_sent = 0 and sender_is_deleted = 0  and recipient = users.id and sender = ".$env{'user_id'};
    }
    $qry .= ' order by '.$sort_field.$sort_direction;
    # print "<br />".$qry."<br />";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my %return_hash;
    my @return_array;
    while (my $row = $sth->fetchrow_hashref) {
        push @return_array, {%$row};
    }
    return \@return_array;
}

sub get_questions {
    # returns selected list of questions
    # expect this routine to change as new search features are implemented
    my ($filter, $sort_field, $sort_direction) = @_;
    my $qry;
    # my $dbh = &db_connect;
    unless (defined $sort_field) {
        $sort_field = 'date';
    }
    if ($filter eq 'out') {
        $qry = "SELECT question_id, date, questions.subject, lastname, is_read, content
                FROM questions, users 
                WHERE questions.user_id = users.id AND
                    is_sent = 1 AND user_id = ".$env{'user_id'};
    } elsif ($filter eq 'in') {
        $qry = "SELECT question_id, date, questions.subject, user_id, lastname, is_read, content
                FROM questions, users WHERE is_sent = 1 AND user_id = users.id ";
    } elsif ($filter eq 'draft') {
        $qry = "SELECT question_id, date, questions.subject, user_id, is_read, content
        FROM questions 
        WHERE is_sent = 0 AND user_id = ".$env{'user_id'};
    }
    $qry .= ' ORDER BY '.$sort_field . ' ' . $sort_direction;
    #print "<br />".$qry."<br />";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my %return_hash;
    my @return_array;
    while (my $row = $sth->fetchrow_hashref) {
        push @return_array, {%$row};
    }
    return \@return_array;
}

sub get_answers {
    # returns selected list of questions
    # expect this routine to change as new search features are implemented
    my ($filter, $sort_field, $sort_direction) = @_;
    my $qry;
    unless (defined $sort_field) {
        $sort_field = 'date';
    }
    if ($filter eq 'out') {
        $qry = "select question_id, date, questions.subject, lastname, is_read from questions, users ";
        $qry.= " where questions.user_id = users.id and is_sent = 1 and user_id = ".$env{'user_id'};
    } elsif ($filter eq 'in') {
        $qry = "select questions.question_id, answer_id, answers.date, questions.subject, questions.user_id, lastname, is_read ";
        $qry.= " from questions, users, answers where answers.is_sent = 1 and answers.user_id = users.id ";
        $qry.= " and questions.user_id = ".$env{'user_id'};
        $qry.= " and questions.question_id = answers.question_id";
    } elsif ($filter eq 'draft') {
        $qry = "select question_id, date, questions.subject, user_id, lastname, is_read  from questions, users ";
        $qry.= " where is_sent = 0 and user_id = ".$env{'user_id'};
    }
    $qry .= ' order by '.$sort_field.$sort_direction;
    # print "<br />".$qry."<br />";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my %return_hash;
    my @return_array;
    while (my $row = $sth->fetchrow_hashref) {
        push @return_array, {%$row};
    }
    return \@return_array;
}

sub message_box {
    my ($r,$box_type) = @_;
    my $box_title;
    my $sort_field;
    my $sort_direction;
    my $box_records;
    my $menu;
    my $direction;
    my $url_fields;
    my $sort_image;
    $url_fields = ';token='.$env{'token'}.';target=message;menu='.$r->param('menu').';sortdirection=';
    if ($r->param('sortdirection') eq 'desc') {
        $sort_direction = ' desc ';
        $url_fields .= 'asc';
        $sort_image= "../images/descend_10x5.gif";
    } else {
        $sort_direction = ' asc ';
        $url_fields .= 'desc';
        $sort_image= "../images/ascend_10x5.gif";
    }
    $sort_field = $r->param('sortfield');
    if ($box_type eq 'inbox') {
        $box_title = "InBox";
        $box_records = &get_messages('in', $sort_field, $sort_direction);
        $direction = "From";
        $menu = 'inbox';
    } elsif ($box_type eq 'outbox') {
        $box_title = "OutBox";
        $box_records = &get_messages('out', $sort_field, $sort_direction);
        $direction = "To";
        $menu = 'outbox';
    } elsif ($box_type eq 'draftbox') {
        $box_title = "Drafts";
        $box_records = &get_messages('draft', $sort_field, $sort_direction);
        $direction = "To";
        $menu = 'drafts';
    }
    my $light_color = "#ffffff";
    my $dark_color = "#eeeeee";
    my $row_color = $light_color;
    $r->print('<h4>'.$box_title.'</hr>'."\n");
    $r->print('<form method="post" action="home">'."\n");
    $r->print('<table><thead><tr>'."\n");
    $r->print('<th width="10"></th>'."\n");
    print '<th width="50" align="left" valign="top"><a href="home?sortfield=flag'.$url_fields.'"<strong>Flag</strong></a>&nbsp;'."\n";
    if ($sort_field eq 'flag') {
        print '<img src="'.$sort_image.'" alt="" />'."\n";
    }
    print '</th>';
    print '<th align="left" valign="top"><a href="home?sortfield=lastname'.$url_fields.'"<strong>'.$direction.'</strong></a> '."\n";
    if ($sort_field eq 'lastname') {
        print '<img src="'.$sort_image.'" alt="" />'."\n";
    }
    print '</th>'."\n";
    print '<th align="left" valign="top"><a href="home?sortfield=subject'.$url_fields.'"><strong>Subject</strong></a> '."\n";
    if ($sort_field eq 'subject') {
        print '<img src="'.$sort_image.'" alt="" />'."\n";
    }
    print '</th>'."\n";
    print '<th align="center" valign="top"><a href="home?sortfield=date'.$url_fields.'"><strong>Date</strong></a> '."\n";
    if ($sort_field eq 'date') {
        print '<img src="'.$sort_image.'" alt="">'."\n";
    }
    print '</th></tr>'."\n";
    $r->print('</thead><tbody>'."\n");
    foreach my $message (@$box_records) {
        print '<tr bgcolor="#EEEEEE" class="content">'."\n"; 
        print '<td width="10"><input type="checkbox" name="messageid" value="'.$$message{'id'}.' />"</td>'."\n";
        if ($$message{'flag'} eq '1') {
            print '<td align="center" width="10"><img src="../images/star.gif" alt="" /></td>'."\n";
        } else {
            print '<td align="center" width="10"><img src="../images/s.gif" alt="" /></td>'."\n";
        }
        print '<td align="left" valign="top"><a href="profile">'.$$message{'lastname'}.'</a>'."\n";
        print '</td>'."\n";
        print '<td align="left" valign="top"><a href="home?token='.$env{'token'}.';target=message;menu='.$menu.';action=view;sortfield='.$sort_field.';messageid='.$$message{'id'}.'">'."\n";
        if ($$message{'is_read'} eq '1') {
            print $$message{'subject'}.'</a></td>'."\n";
        } else {
            print '<strong>'.$$message{'subject'}.'</strong></a></td>'."\n";
        }
        print '<td align="center" valign="top">'.$$message{'date'}.'</td></tr>'."\n";
       
    }
    $r->print('<tr class="bottomRow"><td colspan="5"></td></tr>'."\n");
    $r->print('</tbody></table>'."\n");
    $r->print('<input class="buttonGroup" type="submit" name="submit" value="Delete" />'."\n");
    if ($direction eq 'From') {
        $r->print('<input class="buttonGroup" type="submit" name="submit" value="Mark as Read" />'."\n");
        $r->print('<input class="buttonGroup" type="submit" name="submit" value="Mark as Unread" />'."\n");
    }        
    $r->print('<input class="buttonGroup" type="submit" name="submit" value="Add Flag" />'."\n");
    $r->print('<input class="buttonGroup" type="submit" name="submit" value="Remove Flag" />'."\n");
    $r->print('<input type="hidden" name="token" value="'.$env{'token'}.'" />'."\n");
    $r->print('<input type="hidden" name="menu" value="'.$menu.'" />'."\n");
    $r->print('<input type="hidden" name="sortfield" value="'.$sort_field.'" />'."\n");
    $r->print('<input type="hidden" name="action" value="setprops" />'."\n");
    $r->print('<input type="hidden" name="target" value="message" />'."\n");
    $r->print('</form>'."\n"); 
    return 'ok';
}
sub list_strands {
    my ($r) = @_;
    my $profile = &get_user_profile($env{'user_id'});
    my $level = $$profile{'level'};
    my $where_clause;
    my $load_image_js = "var strands = new Array();";
    if (!$level) {
        $where_clause = "";
    } else {
        $where_clause = " where level = '$level'";
    }
    my $qry = "select * from strands $where_clause";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<script type="text/javascript">'."\n");
    $r->print('function imageSwap(strandID) {'."\n");
    $r->print('document.images["gfw"].src = strands[strandID].src;');
    $r->print('}'."\n");
    $r->print('</script>'."\n");
    $r->print('<div class="strandSelectContainer">');
    $r->print('<div class="strandSelectHead">');
    $r->print('Strands');
    $r->print('</div>');
    $r->print('<div class="strandSelect">');
    my $bgcolor;
    while (my $row = $sth->fetchrow_hashref()) {
        if ($bgcolor eq "highlight") {
            $bgcolor = "lowlight";
        } else {
            $bgcolor = "highlight";
        }
        $load_image_js .= "strands[".$$row{'id'}."] = new Image(); \n"; 
        $load_image_js .= "strands[".$$row{'id'}."].src = '../dynimages/strand_".$$row{'id'}.".gif'; \n";
        
        my $bold_on;
        my $bold_off;
        if ($env{'strand_id'} eq $$row{'id'}) {
            $bold_on = "<strong>";
            $bold_off = "</strong>";
        } else {
            $bold_on = "";
            $bold_off = "";
        }
        my %fields = ('token'=>$env{'token'},
                    'menu'=>'framework',
                    'action'=>'selectstrand',
                    'strandid'=>$$row{'id'});
        my $url = &build_url('apprentice',\%fields);
        $r->print('<span class="'.$bgcolor.'">');
        $r->print($bold_on);
        $r->print('<a onMouseOver="javascript:imageSwap('.$$row{'id'}.')" href="'.$url.'">'."\n");
        $r->print(&mt($$row{'description'}).'</a><br />');
        $r->print($bold_off);
        $r->print('</span>');
    }
    $r->print('</div>');
    $r->print('</div>');
    $r->print('<script type="text/javascript">'."\n");
    $r->print($load_image_js);
    $r->print('</script>'."\n");
}
sub javascript_escape {
    my ($text) = @_;
    $text =~ s/'/\\'/g;
    $text =~ s/"/\\"/g;
    $text =~ s/&/&amp;/g;
    return $text;
}
sub get_resource_nodes {
    # returns hash with key = node coordinate and value = 1
    my($resource_id, $resource_type) = @_;
    my $sth;
    my $file = "/var/www/html/dynimages/framework_base.gif";
    my $qry;
    if ($resource_type eq 'strand') {
        $qry = "SELECT coord 
                FROM strand_framework, math_framework
                WHERE math_framework.code like concat(strand_framework.framework_code,'%') AND
                     strand_framework.strand_id = $resource_id";
        
    } else {
        $qry = "SELECT coord 
                FROM res_framework, math_framework
                WHERE res_framework.framework_code = math_framework.code AND
                     res_framework.res_id = $resource_id";
    }
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my %existing_nodes;
    while (my $row = $sth->fetchrow_hashref()) {
        $existing_nodes{$$row{'coord'}} = 1;
    }
    return (\%existing_nodes);    
}
sub visualize_strand {
    my ($r) = @_;
    my $existing_nodes = &get_resource_nodes($env{'strand_id'},'strand',$r);
    my $graphic_name = &make_gfw("strand_".$env{'strand_id'}.".gif",$existing_nodes);
    &visualizer_javascript($r);
    $r->print('<div class="gfwContainer">');
    $r->print('<img src="../dynimages/'.$graphic_name.'" name="gfw" alt="framework" usemap="#frameworkmap" />');
    $r->print(&framework_image_map());
    $r->print('<h2 id="heading"></h2>');
    $r->print('<div id="description" ></div>');
    $r->print('</div>');
    return;
}
sub make_gfw {
    my($image_name,$existing_nodes,$threshold) = @_;
    my $pref_hashref = &get_preferences();
    my $file;
    if ($$pref_hashref{'simple_framework'} eq 'Yes') {
        $file = "/var/www/html/dynimages/framework_base_simplified.gif";
    } else {
        $file = "/var/www/html/dynimages/framework_base.gif";
    }
    my $src_img = GD::Image->newFromGif($file);
    my $white = $src_img->colorAllocate(255,255,255);
    my $black = $src_img->colorAllocate(0,0,0);
    my $green = $src_img->colorAllocate(0,128,0);       
    my $red = $src_img->colorAllocate(255,0,0);      
    my $gray = $src_img->colorAllocate(128,128,128);
    my $blue = $src_img->colorAllocate(0,0,255);
    my $animated_gif_data = $src_img->gifanimbegin( 1,20);
    $animated_gif_data .= $src_img->gifanimadd(undef,undef,undef,10);
    for (my $row = 0;$row < 14;$row ++) {
        for (my $col = 0;$col < 14;$col ++) {
            my $coord = ($col + 1)."_".($row + 1);
            if (exists $$existing_nodes{$coord}) {
                my $cx = ($col * 20) + 10;
                my $cy = ($row * 20) + 10;
                my $width = 10;
                my $height = 10;
                my $color;
                if ($threshold) {
                    if (($$existing_nodes{$coord}) > ($threshold )) {
                        $color = $green;
                    } else {
                        $color = $red;
                    }
                } else {
                    $color = $gray;
                }
                # here we put the spot on the graphic
                $src_img->filledEllipse($cx,$cy,$width,$height,$color)
            }
        }
    }
    $animated_gif_data .= $src_img->gifanimadd(undef,undef,undef,20);
    $animated_gif_data .= $src_img->gifanimend();
    # here we write the graphic to a file
    # my $gif_data = $src_img->gif;
    open (OUTPUT, "> /var/www/html/dynimages/$image_name");
    # print OUTPUT $gif_data;
    print OUTPUT $animated_gif_data;
    close OUTPUT;
    return $image_name;
}
sub visualizer_javascript {
    my ($r) = @_;
    $r->print('<script type="text/javascript">'."\n");
    $r->print('function showText(text, code) {'."\n");
    $r->print('document.getElementById("heading").innerHTML=code;'."\n");
    $r->print('document.getElementById("description").innerHTML=text;'."\n");
    $r->print('');
    $r->print('}'."\n");
    $r->print('function addCode(code) {'."\n");
    $r->print('document.form1.framecode.value=code;'."\n");
    $r->print('document.getElementById("form1").submit();');
    $r->print('}'."\n");
    $r->print('</script>'."\n");
    return;    
}
sub framework_selector {
    my ($r, $contentarea) = @_;
    if ($r->param('contentarea')) {
        $contentarea = $r->param('contentarea');
    }
    my $resourceid = $r->param('resourceid');
    my ($resource_name, $subject) = &get_resource_name($resourceid);
    my $table = $contentarea.'_framework';
    $r->print($resource_name.'<br />');
    my $existing_nodes = &get_resource_nodes($resourceid,'resource');
    my $graphic_name = &make_gfw('resource_'.$resourceid.'.gif',$existing_nodes);
    &visualizer_javascript($r);
    $r->print('<img src="../dynimages/'.$graphic_name.'" alt="framework" usemap="#frameworkmap" />');
    $r->print(&framework_image_map);
    $r->print('<form name="form1" id="form1" method="post" action="">');
    my %fields = ('target' => 'resource',
                  'menu' => 'resources',
                  'submenu'=>'tags',
                  'resourceid' => $resourceid,
                  'action' => 'addtag');
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="hidden" name="framecode" id="framecode" /><br />');
    $r->print('</form>');
    $r->print('<h2 id="heading"></h2>');
    $r->print('<div id="description" ></div>');
    return 'ok';
}


sub framework_image_map {
    my $image_map;
    my $qry;
    my $sth;
    $image_map .= '<map name="frameworkmap" id="frameworkmap" >';
    for (my $row = 0;$row < 14;$row ++) {
        for (my $col = 0;$col < 14;$col ++) {
            my $coord = ($col + 1).'_'.($row + 1);
            my $x1 = $col * 20;
            my $y1 = $row * 20;
            my $x2 = $x1 + 19;
            my $y2 = $y1 + 19;
            $qry = "select * from math_framework where coord = '$coord'";
            $sth = $env{'dbh'}->prepare($qry);
            $sth->execute();
            my $row = $sth->fetchrow_hashref();
            my $description = &javascript_escape($$row{'description'});
            my $code = &javascript_escape($$row{'code'});
            $image_map .= '<area shape="rect" 
                        nohref="nohref"
                        coords="'."$x1,$y1,$x2,$y2".'" 
                        onMouseOver="showText(\''.$description.'\',\''.$code.'\');" 
                        onClick="addCode(\''.$$row{'code'}.'\')"
                         />'."\n";
        }
    }
    $image_map .= '</map>';
    return $image_map;
}


sub topic_selector {
    my ($r, $contentarea) = @_;
    if ($r->param('contentarea')) {
        $contentarea = $r->param('contentarea');
    }
    my $table1 = $contentarea.'_topics';
    my $table2 = $contentarea.'_framework';
    my $qry = "";
    my $sth;
    $qry = "select t2.id, description, t2.code from $table1 t1, $table2 t2 where t1.code = t2.code order by t1.id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        $r->print('<input type="checkbox" name="frameworkcode" value="'.$$row{'id'}.'">');
        $r->print($$row{'code'}.'-'.$$row{'description'}.'<br />');
    }
    return 'ok';
}
sub question_box {
    my ($r,$box_type) = @_;
    my $box_title;
    my $sort_field;
    my $sort_direction;
    my $box_records;
    my $menu;
    my $direction;
    my $url;
    my $url_fields;
    my $sort_image;
    $url = $r->self_url();
    if ($url =~ /mentor\?/) {
        $url = 'mentor';
    } else {
        $url = 'apprentice';
    }
    $url_fields = ';token='.$env{'token'}.';target=questions;menu='.$r->param('menu').';sortdirection=';
    if ($r->param('sortdirection') eq 'desc') {
        $sort_direction = ' desc ';
        $url_fields .= 'asc';
        $sort_image= "../images/descend_10x5.gif";
    } else {
        $sort_direction = ' asc ';
        $url_fields .= 'desc';
        $sort_image= "../images/ascend_10x5.gif";
    }
    $sort_field = $r->param('sortfield');
    if ($box_type eq 'inbox') {
        $box_title = "Questions asked by Associates";
        $box_records = &get_questions('in', $sort_field, $sort_direction);
        $direction = "From";
        $menu = 'inbox';
    } elsif ($box_type eq 'outbox') {
        $box_title = "Questions awaiting reply";
        $box_records = &get_questions('out', $sort_field, $sort_direction);
        $direction = "To";
        $menu = 'outbox';
    } elsif ($box_type eq 'draftbox') {
        $box_title = "Draft Questions";
        $box_records = &get_questions('draft', $sort_field, $sort_direction);
        $direction = "To";
        $menu = 'drafts';
    }
    my $light_color = "#ffffff";
    my $dark_color = "#eeeeee";
    my $row_color = $light_color;

    $r->print('<form method="post" action="'.$url.'">');
    $r->print('<table>');
    $r->print('<caption>'.$box_title.'</caption>');
    $r->print('<thead><tr>');
    $r->print('<th width="10"><input type = "checkbox" /></th>');
    
    # remove flag until questions can be flagged
#    $r->print('<th width="50" align="left" valign="top">
#            <a href="'.$url.'?sortfield=flag'.$url_fields.'" ><strong>Flag</strong></a>&nbsp;');
#    if ($sort_field eq 'flag') {
#        $r->print('<img src="'.$sort_image.'" alt="" />');
#    }
#    $r->print('</th>');

    $r->print('<th align="left" valign="top"><a href="'.$url.'?sortfield=subject'.$url_fields.'"><strong>Subject</strong></a> ');
    if ($sort_field eq 'subject') {
        $r->print('<img src="'.$sort_image.'" alt="" />');
    }
    $r->print('</th>'."\n");
    $r->print('<th align="center" valign="top"><a href="'.$url.'?sortfield=date'.$url_fields.'"><strong>Date</strong></a> ');
    if ($sort_field eq 'date') {
        $r->print('<img src="'.$sort_image.'" alt="" />');
    }
    $r->print('</th></tr></thead><tbody>'."\n");
    foreach my $message (@$box_records) {
        if (!$$message{'subject'}) {
            $$message{'subject'} = "No Subject";
        }
        $r->print('<tr bgcolor="#EEEEEE" class="content">'."\n"); 
        $r->print('<td width="10"><input type="checkbox" name="messageid" value="'.$$message{'id'}.'" /></td>'."\n");
       
        # flag removed until questions have flags
#        if ($$message{'flag'} eq '1') {
#            $r->print('<td align="center" width="10"><img src="../images/star.gif" alt="" /></td>'."\n");
#        } else {
#            $r->print('<td align="center" width="10"><img src="../images/s.gif" alt="" /></td>'."\n");
#        }
        $r->print('<td align="left" valign="top"><a href="'.$url.'?token='.$env{'token'}.';target=questions;menu='.$menu.';action=view;sortfield='.$sort_field.';messageid='.$$message{'question_id'}.'">'."\n");
        if ($$message{'is_read'} eq '1') {
            $r->print($$message{'subject'}.'</a></td>'."\n");
        } else {
            $r->print('<strong>'.$$message{'subject'}.'</strong></a></td>'."\n");
        }
        $r->print('<td align="center" valign="middle">'.$$message{'date'}.'</td>'."\n");
        $r->print('</tr>'."\n");
    }
    $r->print('</tbody></table>');
    $r->print('<input class="buttonGroup" type="submit" name="submit" value="Delete" />'."\n");
    # $r->print('<input class="buttonGroup" type="submit" name="submit" value="Add Flag" />'."\n");
    # $r->print('<input class="buttonGroup" type="submit" name="submit" value="Remove Flag" />'."\n");
    $r->print('<input type="hidden" name="token" value="'.$env{'token'}.'" />'."\n");
    $r->print('<input type="hidden" name="menu" value="'.$menu.'" />'."\n");
    $r->print('<input type="hidden" name="sortfield" value="'.$sort_field.'" />'."\n");
    $r->print('<input type="hidden" name="action" value="setprops" />'."\n");
    $r->print('<input type="hidden" name="target" value="questions" />'."\n");
    $r->print('</form>'); 
    return 'ok';
}

sub answer_box {
    my ($r,$box_type) = @_;
    my $box_title;
    my $sort_field;
    my $sort_direction;
    my $box_records;
    my $menu;
    my $direction;
    my $url;
    my $url_fields;
    my $sort_image;
    $url = $r->self_url();
    if ($url =~ /mentor\?/) {
        $url = 'mentor';
    } else {
        $url = 'apprentice';
    }
    $url_fields = ';token='.$env{'token'}.';target=questions;menu='.$r->param('menu').';sortdirection=';
    if ($r->param('sortdirection') eq 'desc') {
        $sort_direction = ' desc ';
        $url_fields .= 'asc';
        $sort_image= "../images/descend_10x5.gif";
    } else {
        $sort_direction = ' asc ';
        $url_fields .= 'desc';
        $sort_image= "../images/ascend_10x5.gif";
    }
    $sort_field = $r->param('sortfield');
    $box_title = "Replies to my Questions";
    $box_records = &get_answers('in', $sort_field, $sort_direction);
    $direction = "From";
    $menu = 'inbox';
    my $light_color = "#ffffff";
    my $dark_color = "#eeeeee";
    my $row_color = $light_color;
    $r->print('<form method="post" action="'.$url.'">'."\n");
    $r->print('<table>');
    $r->print('<caption>'.$box_title.'</caption><thead>'."\n");
    $r->print('<tr>');
    $r->print('<th ><input type="checkbox" /></th>'."\n");
    $r->print('<th width="50" align="left" valign="top"><a href="'.$url.'?sortfield=flag'.$url_fields.'" ><strong>Flag</strong></a>&nbsp;'."\n");
    if ($sort_field eq 'flag') {
        $r->print('<img src="'.$sort_image.'" alt="" />'."\n");
    }
    $r->print('</th>'."\n");
    $r->print('<th align="left" valign="top"><a href="'.$url.'?sortfield=lastname'.$url_fields.'" ><strong>'.$direction.'</strong></a> '."\n");
    if ($sort_field eq 'lastname') {
        $r->print('<img src="'.$sort_image.'" alt="" />'."\n");
    }
    $r->print('</th>'."\n");
    $r->print('<th align="left" valign="top"><a href="'.$url.'?sortfield=subject'.$url_fields.'"><strong>Subject</strong></a> '."\n");
    if ($sort_field eq 'subject') {
        $r->print('<img src="'.$sort_image.'" alt="" />'."\n");
    }
    $r->print('</th>'."\n");
    $r->print('<th align="center" valign="top"><a href="'.$url.'?sortfield=date'.$url_fields.'"><strong>Date</strong></a> '."\n");
    if ($sort_field eq 'date') {
        $r->print('<img src="'.$sort_image.'" alt="" />'."\n");
    }
    $r->print('</th></tr></thead><tbody>'."\n");
    foreach my $message (@$box_records) {
#    foreach my $message (sort keys %$box_records) {
        $r->print('<tr bgcolor="#EEEEEE" class="content">'."\n"); 
        $r->print('<td width="10"><input type="checkbox" name="messageid" value="'.$$message{'id'}.'" /></td>'."\n");
        if ($$message{'flag'} eq '1') {
            $r->print('<td align="center" width="10"><img src="../images/star.gif" alt="" /></td>'."\n");
        } else {
            $r->print('<td align="center" width="10"><img src="../images/s.gif" alt="" /></td>'."\n");
        }
        $r->print('<td align="left" valign="top"><a href="profile">'.$$message{'lastname'}.'</a>'."\n");
        $r->print('</td>'."\n");
        $r->print('<td align="left" valign="top"><a href="'.$url.'?token='.$env{'token'}.';target=questions;menu='.$menu.';action=view;sortfield='.$sort_field.';messageid='.$$message{'question_id'}.';answerid='.$$message{'answer_id'}.'">'."\n");
        if ($$message{'is_read'} eq '1') {
            $r->print($$message{'subject'}.'</a></td>'."\n");
        } else {
            $r->print('<strong>'.$$message{'subject'}.'</strong></a></td>'."\n");
        }
        $r->print('<td align="center" valign="middle">'.$$message{'date'}.'</td>'."\n");
        $r->print('</tr>'."\n");
    }
    $r->print('</tbody></table>'."\n");
    $r->print('<input class="buttonGroup" type="submit" name="submit" value="Delete" />'."\n");
    $r->print('<input class="buttonGroup" type="submit" name="submit" value="Add Flag" />');
    $r->print('<input class="buttonGroup" type="submit" name="submit" value="Remove Flag" />');
    print '<input type="hidden" name="token" value="'.$env{'token'}.'" />'."\n";
    print '<input type="hidden" name="menu" value="'.$menu.'" />'."\n";
    print '<input type="hidden" name="sortfield" value="'.$sort_field.'" />'."\n";
    print '<input type="hidden" name="action" value="setprops" />'."\n";
    print '<input type="hidden" name="target" value="questions" />'."\n";
    print '</form>'."\n"; 
    return 'ok';
}



sub code_to_description {
    my ($code) = @_;
    my $qry = "";
    my $sth;
    $qry = "select description from math_framework where code = '$code'";
    $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return $$row{'description'};
}



sub time_to_seconds {
    my ($vid_time) = @_; # converts hh:mm:ss to total seconds
    my ($hour,$minutes,$seconds) = split /:/, $vid_time;
    
    return (($hour*3600) + ($minutes * 60) + $seconds);
}

sub video {
    my ($r) = @_;
    my $resource_id = $r->param('resource');
    my $qry = "select t1.title, location, t1.comments, start_time, end_time, t2.comments as clip_comments, 
                t2.title as clip_title from resources t1 
                left join vid_clips t2 ON t2.resource_id = t1.id
                where t1.id = $resource_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my @clips;
    my @disp_clips;
    my $row = $sth->fetchrow_hashref();
    my %t_hash;
    $t_hash{'start_time'} = &time_to_seconds($$row{'start_time'});
    $t_hash{'end_time'} = &time_to_seconds($$row{'end_time'});
    $t_hash{'display'} = $$row{'start_time'}.'-'.$$row{'end_time'};
    push @clips, {%t_hash};
    while (my $clip = $sth->fetchrow_hashref()) {
        $t_hash{'start_time'} = &time_to_seconds($$clip{'start_time'});
        $t_hash{'end_time'} = &time_to_seconds($$clip{'end_time'});
        $t_hash{'display'} = $$clip{'start_time'}.'-'.$$clip{'end_time'};
        push @clips, {%t_hash};
    }
    $r->print('<div id="interiorHeader">');
    $r->print('<h2>Video Resource Management </h2>');
    $r->print('<h3>Edit and select ...</h3>');
    $r->print('</div>');
        
    $r->print('<table><tr><td>'."\n");
    $r->print('');
    $r->print('<embed src="../video/'.$$row{'location'}.'" width="320" height="260"'."\n");
    $r->print('QTSRC="'.$$row{'location'}.'"'."\n");
    $r->print('controller="true"'."\n");
    $r->print('NAME="movie"'."\n");
    $r->print('bgcolor="cccccc" />'."\n");
    $r->print('</td><td valign="top"><form name="form1" method="post" action="">');
    $r->print('<input size="8" type="text" name="markin"><input size="8" type="text" name="markout"><br />'."\n");
    $r->print('<input type="button" value="Mark In" onClick="grab(1)" /><input type="button" value="Mark Out" onClick="grab(2)" />'."\n");
    $r->print('<br /><input type="button" value="Reset" onClick="resetmovie()">');
    $r->print('<br /><input type="text" name="title" />');
    $r->print('<p class="content">Description:</p>');
    $r->print('<p><textarea rows="8" name="description" cols="30"></textarea></p>');
    $r->print('<input type="hidden" name="target" value="video">');
    $r->print('<input type="hidden" name="action" value="saveclip">');
    $r->print('<input type="hidden" name="resource" value="'.$resource_id.'">');
    $r->print('<input type="hidden" name="token" value="'.$env{'token'}.'">');
    $r->print('<input type="submit" value="Save Clip">'."\n");
    $r->print('</form>'."\n");
    $r->print('</td><td valign="top">');
    $r->print('<span>Existing Clips<br />');
    foreach my $clip (@clips) {
        $r->print('<input type="button" onClick="playclip('.$$clip{'start_time'}.','.$$clip{'end_time'}.')" value="'.$$clip{'display'}.' Play" /><br />');
    }
    $r->print('</span></td></tr></table>');
    return 'ok';
}
sub save_clip {
    my ($r) = @_;
    $r->print('saving clip<br />');
    # will need error checking for sensible clips
    my %fields;
    $fields{'start_time'} = &fix_quotes($r->param('markin'));
    $fields{'end_time'} = &fix_quotes($r->param('markout'));
    $fields{'comments'} = &fix_quotes($r->param('description'));
    $fields{'author_id'} = $env{'user_id'};
    $fields{'resource_id'} = $r->param('resource');
    &save_record('vid_clips', \%fields);
    return 'ok';
}
sub delete_resource {
    my ($r) = @_;
    my $qry;
    my @resources = $r->param('resourceid');
    my $resource_names;
    foreach my $id (@resources) {
        my ($name,$subject) = &get_resource_name($id);
        $resource_names .= $name."<br />";
    }
    foreach my $id (@resources) {
        $qry = "delete from resources where id = $id";
        $env{'dbh'}->do($qry);
        $qry = "delete from res_meta where res_id = $id";
        $env{'dbh'}->do($qry);
    }
    return;
}
sub mt {
    # escapes characters to allow html display
    my ($text) = @_;
    $text =~ s/&/&amp;/g;
    $text =~ s/\n/<br \/>/g;
    return ($text);
}
sub mt_url {
    # escapes characters to make legitimate URLs
    my ($text) = @_;
    $text =~ s\&\&amp;\g;
    $text =~ s\ \%20\g;
    return ($text);
}

sub old_category_menu {
    my ($r) = @_;
    my $profile = &get_user_profile();
    my $subject = $$profile{'subject'};
    my $categories = &get_categories($subject);
    $r->print('<form method="post" action="">');
    $r->print('<select name="categoryfilter">');
    $r->print('<option value="0">Select a Category</option>');
    foreach my $category (@$categories) {
        my $selected = '';
        if ($r->param('categoryfilter')) {
            if ($r->param('categoryfilter') eq $$category{'id'}) {
                $selected = ' SELECTED ';
            }
        }
        $r->print('<option value="'.$$category{'id'}.'"'.$selected.'>'.$$category{'category'}.'</option>');
    }
    $r->print('</select>');
    my %fields = ('target'=>'resource');
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" value="Show Category">');
    $r->print('</form>');
}
sub get_framework {
    my ($subject) = @_;
    my @framework;
    my $qry;
    if ($subject eq 'Math') {
        $qry = "select * from math_framework";
    } elsif ($subject eq 'Science') {
        $qry = "select * from science_framework";
    }
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push(@framework,{%$row});
    }
    return \@framework;
}
sub framework_menu {
    my ($r) = @_;
    my $profile = &get_user_profile();
    my $subject = $$profile{'subject'};
    my @options;
    my $code1;
    my $code2;
    my $code3;
    my $code4;
    my $code5;
    if ($r->param('code1')) {
        $code1 = $r->param('code1');
    } else {
        $code1 = "none";
    }
    my $filter_code = $code1;
    # multi-level framework selector
    # first, get the framework
    my $framework = &get_framework($subject);
    push @options,({'Select Framework Entry to Filter Resources'=>'none'});
    foreach my $fw_item(@$framework) {
        if ($$fw_item{'code'} =~ /^1\.\d+$/) {
            push @options,({&mt($$fw_item{'description'})=>$$fw_item{'code'}});
        }
    }
    $r->print('<form name="form1" method="post" action="">');
    my $javascript = ' onchange="form1.submit()" ';
    $r->print(&build_select('code1', \@options, $code1, $javascript));
    if ($code1 ne 'none') {
        if ($r->param('code2')) {
            $code2 = $r->param('code2');
        } else {
            $code2 = "none";
        }
        if ($code2 eq "none") {
            $filter_code = $code1;
        } else {
            $filter_code = $code2;
        }
        @options=();
        push @options,({'Filter more'=>'none'});
        foreach my $fw_item(@$framework) {
            if ($$fw_item{'code'} =~ /^$code1\.\d+$/) {
                push @options,({$$fw_item{'description'}=>$$fw_item{'code'}});
            }
        }
        $r->print('<br />');
        $r->print(&build_select('code2', \@options, $code2, $javascript));
        if ($code2 ne 'none') {
            if ($r->param('code3')) {
                $code3 = $r->param('code3');
            } else {
                $code3 = "none";
            }
            if ($code3 eq "none") {
                $filter_code = $code2;
            } else {
                $filter_code = $code3;
            }
            
            @options=();
            push @options,({'Filter more'=>'none'});
            foreach my $fw_item(@$framework) {
                if ($$fw_item{'code'} =~ /^$code2\.\d+$/) {
                    push @options,({$$fw_item{'description'}=>$$fw_item{'code'}});
                }
            }
            $r->print('<br />');
            $r->print(&build_select('code3', \@options, $code3, $javascript));
                
        }
    }
    my %fields = ('target'=>'resources',
                  'menu'=>$env{'menu'},
                  'submenu'=>$env{'submenu'});
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
    return($filter_code);
}
sub save_fave {
    my ($r) = @_;
    my $user_id = $env{'user_id'};
    my %fields = ('resource_id'=>$r->param('resourceid'),
                'user_id'=>$user_id);
    &save_record('fav_resources',\%fields);
    return;
}
sub delete_fave {
    my ($r) = @_;
    my $user_id = $env{'user_id'};
    my $resource_id = $r->param('resourceid');
    my %fields = ('resource_id'=>$r->param('resourceid'),
                'user_id'=>$user_id);
    my $qry = "delete from fav_resources where resource_id = $resource_id and user_id = $user_id";
    $env{'dbh'}->do($qry);
    return;
}
sub get_course_resources {
    my $qry = "SELECT distinct resource_id FROM course_sequence";
    my $sth = $env{'dbh'}->prepare($qry);
    my %return_hash;
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        $return_hash{$$row{'resource_id'}} = 1;
    }
    return(%return_hash);
}
sub get_fave_resources {
    my $user_id = $env{'user_id'};
    my $qry = "select resource_id from fav_resources where user_id = $user_id";
    my $sth = $env{'dbh'}->prepare($qry);
    my %return_hash;
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        $return_hash{$$row{'resource_id'}} = 1;
    }
    return(%return_hash);
}
sub resource_box {
    my ($r,$box_type) = @_;
    my $upload_dir_url = "../resources";
    my $box_title;
    my $box_records;
    my $menu = $r->param('menu');
    my $direction;
    my $url="";
    my $cur_page;
    my $profile_hashref = &get_user_profile();
    my $subject = $$profile_hashref{'subject'};
    my $favorites;
    my $link_text;
    if ($r->param('favorites')) {
        $favorites = $r->param('favorites');
        $cur_page = $r->param('curpage');
    } else {
        $favorites = 'no';
    }
    if ($r->param('curpage')) {
        $cur_page = $r->param('curpage');
    } else {
        $cur_page = 1;
    }
    my $page_size = 15;
    $box_title = "Resources";
    # retrieve all the resources 
    my %fields = (
        'token' => $env{'token'},
        'target' => 'resources',
        'menu' => $env{'menu'},
        'submenu' => $env{'submenu'}
    );
    &alpha_menu($r,undef,\%fields);
    # &category_menu($r);
    my $filter_code = &framework_menu($r);
    my $num_rows = &get_count_resources($r,$subject,$favorites,$filter_code);
    $box_records = &get_resources($r, $$profile_hashref{'subject'},$favorites, $cur_page,$page_size,$filter_code);
    my %fav_records = &get_fave_resources();
    my %course_records = &get_course_resources();
    $r->print('<form method="post" action="'.$url.'">'."\n");
    $r->print('<table><caption><font size="2">'.$$profile_hashref{'subject'}.' Resources</font>'."\n");
    if ($r->param('alphafilter')) {
        $fields{'alphafilter'} = $r->param('alphafilter');
    }
    $r->print(" $num_rows total ");
    if ($cur_page > 1) {
        $fields{'curpage'}=$cur_page - 1;
        $url = &build_url("",\%fields);
        $r->print('<a href="'.$url.'">[Prev]</a> ');
    }
    if ($num_rows > (($page_size * $cur_page)+1)) {
        $fields{'curpage'} = $cur_page + 1;
        $url = &build_url("",\%fields);
        $r->print('<a href="'.$url.'">[Next]</a> ');
    }
    if ($favorites eq 'yes') {
        $fields{'favorites'} = 'no';
        $link_text = 'Show All';
    } else {
        $fields{'favorites'} = 'yes';
        $link_text = 'Show Favorites';
    }
    $fields{'curpage'} = $cur_page;
    $url = &build_url("",\%fields);
    $r->print('<a href="'.$url.'">['.$link_text.']</a> ');
    $r->print('</caption><thead>'."\n");
    $r->print('<tr>'."\n");   
    $r->print('<th align="left" valign="top">Title</th>'."\n");
    $r->print('<th align="left" valign="top">Description</th>'."\n");
    $r->print('<th align="left" valign="top">Contributor</th></tr>'."\n");
    $r->print('</thead>'."\n");
    my $row_alt = 0;
    my $clip_count;
    foreach my $resource (@$box_records) {
        my $row_class;
        if ($row_alt eq 0) {
            $row_alt = 1;
            $row_class = "";
        } else {
            $row_alt = 0;
            $row_class = ' class="rowAlternate" ';
        }
        if ($$resource{'clips'}) {
            $clip_count = $$resource{'clips'}.' clip(s)';
        } else {
            $clip_count = "";
        }
        $r->print('<tr '.$row_class.'>');
        # $r->print('<td align="left" ><a href="editor?target=video&amp;token='.$env{'token'}.'&amp;resource='.$$resource{'id'}.'">'.&mt($$resource{'title'}).$clip_count.'</a></td>');
        if ($$resource{'type'} eq 'Video') {
            my $icon = "../images/resourcelist_video.png";
            $r->print('<td align="left" valign="middle"><a href="editor?target=video&amp;token='.
                        $env{'token'}.'&amp;resource='.$$resource{'id'}.'">'.&mt($$resource{'title'}).
                        "<img src='$icon' alt='Video' />".'</a></td>'."\n");
        } elsif ($$resource{'type'} eq 'Web URL') {
            my $icon = "../images/resourcelist_web.png";
            # $r->print('<td align="left" valign="middle"><a target="new" href="'.&mt($$resource{'location'}).'">'.&mt($$resource{'title'}).$clip_count.'</a></td>');
            %fields = ('token'=>$r->param('token'),
                    'target'=>'redirect',
                    'resourceid'=>$$resource{'id'},
                    'url'=> &mt($$resource{'location'}));
            $url = &build_url('home',\%fields);
            $r->print('<td align="left" valign="middle">
                    <a target="new" 
                    href="'.$url.'">'.&mt($$resource{'title'}).$clip_count.
                    "<img src='$icon' alt='WWW Link' />".
                    '</a></td>');
        } elsif ($$resource{'type'} eq 'Video/Slide') {
            my $icon = "../images/resourcelist_video.png";
            # create proper link to video/slide (Flash application);
            %fields = ('token'=>$r->param('token'),
                    'resourceid'=>$$resource{'id'},
                    'target'=>'resources',
                    'menu'=>$env{'menu'},
                    'submenu'=>'showvidslide',
                    'action'=>'showvidslide',
                    'showname'=>$$resource{'location'},
                    'url'=> &mt($$resource{'location'}));
            $url = &build_url('',\%fields);
            $r->print('<td align="left" valign="middle">
                    <a  
                    href="'.$url.'">'.&mt($$resource{'title'}).$clip_count.
                    "<img src='$icon' alt='Video' />".
                    '</a></td>');
            
        } else {
            my $icon = "../images/resourcelist_doc.png";
            print '<td align="left" valign="middle"><a target="new" href="'.$upload_dir_url.
            '/'.&mt_url($$resource{'location'}).'.'.$$resource{'id'}.'">'.
            &mt($$resource{'title'}).$clip_count.
            "<img src='$icon' alt='Document' />".
            '</a></td>';
        }
        $r->print('<td align="left" >'.&mt($$resource{'comments'}));
        if (&get_user_roles() =~ m/Editor/) {
            my $alpha_filter;
            $alpha_filter = ($r->param('alphafilter'))?$r->param('alphafilter'):"";
            my %fields = ('token'=>$r->param('token'),
                    'target'=>'resources',
                    'resourceid'=>$$resource{'id'},
                    'alphafilter'=>$alpha_filter,
                    'submenu'=>'edit',
                    'menu'=>'resources');
            $url = &build_url('editor',\%fields);
            $r->print('<a href="'.$url.'" >[Edit]</a>'."\n");
            $fields{'action'}='delete';
            $url = &build_url('editor',\%fields);
            $r->print('<a href="'.$url.'" onclick="javascript:return confirm(\'Delete this resource?\')">[Delete]</a>'."\n");
            
        }
        if ($course_records{$$resource{'id'}}) {
            $r->print('<img src="../images/resourcelist_course01.gif" alt="In a course" />');
        }
        if ($fav_records{$$resource{'id'}}) {
            %fields = ('token'=>$env{'token'},
                        'target'=>'resources',
                        'resourceid'=>$$resource{'id'},
                        'action'=>'removefave');
        if ($r->param('alphafilter')) {
            $fields{'alphafilter'} = $r->param('alphafilter');
        }
            $url = &build_url('',\%fields);
            
            $r->print('<a href="'.$url.'">[Remove favorite]</a>'."\n");
        } else {
            %fields = ('token'=>$r->param('token'),
                        'target'=>'resource',
                        'menu'=>$env{'menu'},
                        'submenu'=>$env{'submenu'},
                        'resourceid'=>$$resource{'id'},
                        'action'=>'makefave');
        if ($r->param('alphafilter')) {
            $fields{'alphafilter'} = $r->param('alphafilter');
        }
            $url = &build_url('',\%fields);
            
            $r->print('<a href="'.$url.'">[Make favorite]</a>');
        }
        $r->print('</td>');
        # $r->print('<td align="left" ><a href="'.$url.'?token='.$env{'token'}.';target=resource;menu='.$menu.';action=profile;userid='.$$resource{'contributor'}.'">'.$$resource{'lastname'}.'</a></td>'."\n");
        %fields = ('token'=>$r->param('token'),
                    'target'=>'profiledisplay',
                    'profileid'=>$$resource{'contributor'});
        $url = &build_url('home',\%fields);
        $r->print('<td><a href="javascript:;" onClick=
                "window.open(\''.$url.'\',\'profile\',\'left=0, top=0, height=480, width=640\')">'.$$resource{'lastname'}.'</a></td>');
        $r->print('</tr>');
    }
    $r->print('');
    $r->print('</table>');
    $r->print('<input type="hidden" name="token" value="'.$env{'token'}.'" />');
    $r->print('<input type="hidden" name="target" value="resource" />');
    $r->print('<input type="hidden" name="menu" value="browse" />');
    $r->print('</form>'."\n");
    return 'ok';
}
sub edit_resource {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my $resource_id = $r->param('resourceid');
    my $url = &get_base_url($r);
    $qry = "select * from resources where id = $resource_id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $resource_hashref = $sth->fetchrow_hashref;
    &update_resource_form($r,$resource_hashref);
    return 'ok';
}
sub resource_summary {
    #retrieves summary of resources applicable to interests of user identified
    my ($r) = @_;
    my %summary;
    return \%summary;
}
sub fix_filename {
    my ($file_name) = @_;
    if ($file_name=~/\\/) { #has back-slashes
        $file_name=~/(.*\\)(.*$)/;
        $file_name=$2;
    }
    return $file_name;    
}
sub index_for_search {
    my ($row) = @_;
    my $qry;
    my %words_index;
    my @words = (split (/\s/,$$row{'title'}));
    foreach my $word(@words) {
        $words_index{uc($word)} += 1;
    }
    undef @words;
    @words = (split (/\s/,$$row{'description'})); 
    foreach my $word(@words) {
        $words_index{uc($word)} += 1;
    }
    foreach my $key (keys (%words_index)) {
        my $save_word = uc($key);
        if ($key =~ /[A-Z][A-Z]/) {
            $qry = "insert into doc_code (doc_id, word, count) values (".$$row{'id'}.",".&fix_quotes($save_word).",".$words_index{$key}.")";
            $env{'dbh'}->do($qry);
        }
    }
}
sub save_resource {
    my ($r) = @_;
    my %fields;
    my $qry;
    my $title;
    my $file_name = $r->param('resource');
    %fields = ('title' => &fix_quotes($r->param('title')),
               'author' => &fix_quotes($r->param('author')),
               'time_commitment' => $r->param('timecommitment'),
               'intended_use' => $r->param('intendeduse'),
               'subject' => &fix_quotes($r->param('subject')),
               'comments' => &fix_quotes($r->param('comments')),
               'contributor' => $env{'user_id'},
               'type' => &fix_quotes($r->param('type'))
               );
    if ($r->param('resource') eq "") { # if no file is uploaded
        $fields{'location'} = &fix_quotes($r->param('location'));
        $fields{'id'} = &save_record ('resources',\%fields,'id');
        &index_for_search(\%fields);
    } else {
        $fields{'location'} = &fix_quotes($file_name);
        $file_name = &fix_filename($file_name);
        my $resource_id = &save_record ('resources',\%fields,'id');
        # send resource_id to append to file name, assuring unique name
        # not sure if that's smart
        if (&handle_upload($r, $resource_id)) {
            &index_for_search(\%fields);
        }
    }
    return 'ok';
}

sub handle_upload {
    my ($r, $resource_id, $course_only) = @_;
    my $upload_dir;
    my $return = 0;
    if ($course_only) {
        $upload_dir = "/var/www/html/resources";
    } else {
        $upload_dir = "/var/www/html/resources";
    }
    my $upload_filehandle = $r->upload('resource');
    my $file_name = $r->param('resource');
    $file_name = &fix_filename($file_name);
    #doubtless need to handle dos filenames or maybe rename with index values
    if (open UPLOADFILE, "> $upload_dir/$file_name.$resource_id") {
        binmode UPLOADFILE;
        while ( <$upload_filehandle> ) { 
            print UPLOADFILE; 
        } 
        close UPLOADFILE;
        $return = 1;
    } else {
        &logthis("unable to open file $upload_dir/$file_name.$resource_id");
    }
    return($return);
}
sub view_edit_resource {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my $resource_id = $r->param('resourceid');
    my $url = &get_base_url($r);
    $qry = "select * from resources where id = $resource_id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $resource_hashref = $sth->fetchrow_hashref;
    &update_resource_form($r, $resource_hashref);
    $qry = "select * from res_meta, tags where res_id = $resource_id and tag_id = tags.id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        &edit_tag_form($r, $row);
    }
    return 'ok';
}

sub edit_tag_form {
    my ($r, $tag_hashref) = @_;
    my $url = &get_base_url($r);
    print '<table width="100%" border="0" cellspacing="0" cellpadding="10">';
    print '<tr><td align="left" valign="top">';
    print '<FORM ACTION="'.$url.'" METHOD="post" ENCTYPE="multipart/form-data">';
    print '<table width="100%" border="0" cellpadding="0" cellspacing="0" bgcolor="#006634">';
    print '<tr><td align="center" valign="middle" bgcolor="#006634"><table width="100%" border="0" cellspacing="1" cellpadding="2">';
    print '<tr><td colspan="2" class="header"><font color="#FFFFFF">Update Resource Tag</font></td></tr>';
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>Description:</strong></td><td align="left">';
    print '<input type="text" size="50" name="description" value="'.$$tag_hashref{'description'}.'"></tr>';
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>Location:</strong></td><td align="left">';
    print '<input type="text" size="50" name="location" value="'.$$tag_hashref{'location'}.'"></tr>';
    print '<tr align="center" valign="middle" bgcolor="#FFFFFF" class="content">';
    print '<td colspan="2">';
    print '<input type="hidden" name="token" value="'.$env{'token'}.'">';
    print '<input type="hidden" name="target" value="resource">';
    print '<input type="hidden" name="menu" value="resources">';
    print '<input type="hidden" name="action" value="update">';
    print '<input type="submit" name="Submit" value="Submit Resource"></td></tr>';
    print '</table></td></tr></table></form>';
    print '<p class="content"><span class="content"><br />';
    print '</p></td></tr></table>';
    return 'ok';
}
sub get_count_resources {
    my ($r, $subject, $favorites, $filter_code) = @_;
    my $alphafilter;
    my $user_id = $env{'user_id'};
    my $qry;
    my $reg_var = 'ORDER';
    my $row;
    my $where_clause;
    $where_clause = " WHERE subject = '$subject' \n";
    if ($r->param('alphafilter')) {
        $alphafilter = $r->param('alphafilter');
    } else {
        $alphafilter = "";
    }
    if ($filter_code ne 'none') {
        $where_clause .= " AND id in (select res_id from res_framework where framework_code like '$filter_code%') ";
    } else {
        if ($favorites ne 'no') {
            $where_clause .= " AND id in (select resource_id from fav_resources where user_id = $user_id) \n";
        }
        if ($alphafilter) {
            $where_clause .= " AND title >='$alphafilter' "
        }
    }
    $qry = "select count(*) as count from resources $where_clause"; 
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $row = $sth->fetchrow_hashref();
    return $$row{'count'};
}
sub build_get_resources_qry {
    my ($r,$subject,$favorites,$cur_page,$page_size,$filter_code) = @_;
    my $qry;
    my $alpha_filter;
    if ($r->param('alphafilter')) {
        $alpha_filter = $r->param('alphafilter');
    } else {
        $alpha_filter = "";
    }
    my $filter = "";
    my $category_filter = "";
    if ($subject) {
        $filter = " WHERE (t1.subject = '$subject') ";
    }
    if ($r->param('categoryfilter')) {
        $category_filter = " WHERE t5.category_id = ".$r->param('categoryfilter')." ";
    }
    if ($alpha_filter) {
        if ($filter =~ /WHERE/) {
            $filter .= " AND t1.title >= '".$alpha_filter."' "
        } else {
            $filter = " WHERE (t1.title >= '$alpha_filter') ";
        }
    }
    if ($favorites eq 'yes') {
        if ($filter =~ /WHERE/) {
            $filter .= " AND t3.user_id = ".$env{'user_id'}." ";
        } else {
            $filter = " WHERE t3.user_id = ".$env{'user_id'}." ";
        }
    }
    if ($filter_code ne 'none') {
        if ($filter =~ /WHERE/) {
            $filter .= " AND t1.id IN (select res_framework.res_id from res_framework where framework_code LIKE '".$filter_code."%') ";
        } else {
            $filter = " WHERE t1.id IN (select res_framework.res_id from res_framework where framework_code LIKE '".$filter_code."%') ";
        }
        
    }
    if ($filter =~ /WHERE/) {
        $filter .= " AND t1.course_id IS NULL ";
    } else {
        $filter = " WHERE t1.course_id IS NULL ";
    }
    # here's the base qry:
    $qry = "select t1.title, t1.subject, type, t1.comments, t1.location, t2.lastname, t2.firstname, 
                t1.contributor, t1.id
                FROM resources t1 
                LEFT JOIN users t2 ON t2.id = t1.contributor ";
    # now need optional join for favorites filtering
    if ($favorites eq 'yes') {
        $qry .= "LEFT JOIN fav_resources t3 ON t1.id = t3.resource_id ";
    }
#    # now need optional join for framework code filtering
#    if($filter_code) {
#        $qry .= "LEFT JOIN res_framework t4 on t1.id = t4.res_id ";
#    }
    $qry .= $filter;
    # finish the qry
    $qry .= " ORDER by t1.title ";
    
    if ($cur_page) {
        my $start = ((($cur_page - 1) * $page_size));
        my $end = ($start + $page_size) - 1; 
        $qry .= "LIMIT $start, $page_size;";
    }
                # change to limit by 1,10 (say)
    return $qry;
}
sub get_resources {
    my ($r, $subject, $favorites, $cur_page, $page_size, $filter_code) = @_;
    my $user_id = $env{'user_id'};
    my $alpha_filter = $r->param('alphafilter');
    my $sth;
    my @all_resources;
    my $qry = &build_get_resources_qry($r,$subject,$favorites, $cur_page,$page_size,$filter_code);
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $resource = $sth->fetchrow_hashref) {
        push @all_resources, {%$resource};
    }
    return (\@all_resources);
}
sub get_resources_select_all {
    my ($subject) = @_;
    my $sth;
    my @all_resources;
    my $qry = 'select id, title from resources where subject = "'.$subject.'" order by title';
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $resource = $sth->fetchrow_hashref) {
        
        push @all_resources, {$$resource{'title'}=>$$resource{'id'}};
    }
    return (\@all_resources);
}
sub get_course_only_resources {
    my ($course_id) = @_;
    my $sth;
    my @course_resources;
    my $qry = "select id, title from resources where course_id = $course_id order by title";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $resource = $sth->fetchrow_hashref) {
        push @course_resources, {$$resource{'title'}=>$$resource{'id'}};
    }
    return (\@course_resources);
}
sub browse_resources {
    my ($r) = @_;
    my $qry = "select * from resources";
    my $sth;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $resource = $sth->fetchrow_hashref) {
        print $$resource{'title'}."<br />";
    }
    return 'ok';
}
sub update_resource {
    my ($r) = @_;
    my %fields;
    my %id;
    $id{'id'} = $r->param('resourceid');
    $fields{'title'} = &fix_quotes($r->param('title'));
    $fields{'type'} = &fix_quotes($r->param('type'));
    $fields{'author'} = &fix_quotes($r->param('author'));
    $fields{'location'} = &fix_quotes($r->param('location'));
    $fields{'time_commitment'} = $r->param('timecommitment');
    $fields{'intended_use'} = $r->param('intendeduse');
    $fields{'comments'} = &fix_quotes($r->param('comments'));
    $fields{'subject'} = &fix_quotes($r->param('subject'));
    &update_record('resources', \%id, \%fields); 
    return 'ok';
}
sub get_categories {
    my ($subject) = @_;
    my $where_clause = "";
    if ($subject) {
        $where_clause = " where subject = '$subject' ";
    }
    my $qry = "select * from categories $where_clause";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my @all_categories;
    while (my $category = $sth->fetchrow_hashref) {
        push @all_categories, {%$category};
    }
    return \@all_categories;
}
sub get_resource_categories {
    my ($resource_id) = @_;
    my $qry = "select t2.category, t2.id from resource_cats t1, categories t2 
                WHERE t1.category_id = t2.id and t1.resource_id = $resource_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my @all_categories;
    while (my $category = $sth->fetchrow_hashref) {
        push @all_categories, {%$category};
    }
    return \@all_categories;
}
sub get_resource_types {
    my $qry = "select description from types_lu ";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my @all_types;
    while (my $row = $sth->fetchrow_hashref) {
        my $key = $$row{'description'};
        push @all_types, $$row{'description'};
    }
    return \@all_types;
}
sub get_resource_name {
    my ($resource_id) = @_;
    my $qry = "select title, subject from resources where id = $resource_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return ($$row{'title'},$$row{'subject'});
}
sub get_resource_type {
    my ($resource_id) = @_;
    my $qry = "SELECT type FROM resources t1
               WHERE id = $resource_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return ($$row{'type'});
}

sub edit_resource_categories {
    my ($r) = @_;
    my %fields;
    if ($env{'action'} eq 'savecategory') {
        %fields = ('subject'=>&fix_quotes($r->param('subject')),
                      'category'=>&fix_quotes($r->param('category')));
        &save_record('categories',\%fields);
    }
    if ($env{'action'} eq 'saveresourcecat') {
        %fields = ('resource_id'=>$r->param('resourceid'),
                      'category_id'=>$r->param('categoryid'));
        $r->print('Saving resource category');
        &save_record('resource_cats',\%fields);
    }
    if ($env{'action'} eq 'removeresourcecat') {
        %fields = ('resource_id'=>$r->param('resourceid'),
                      'category_id'=>$r->param('categoryid'));
        my $qry = "delete from resource_cats where 
                    resource_id = ".$r->param('resourceid')." and category_id = ".$r->param('categoryid');
        $env{'dbh'}->do($qry); 
        $r->print('Removing resource category');
    }
    my ($resource_name,$resource_subject) = &get_resource_name($r->param('resourceid'));
    $r->print('<br />Editing categories for <br />');
    $r->print($resource_name." a ".$resource_subject." resource");
    $r->print('<form method="post" action="">');
    $r->print('<input type="text" name="category" />');
    $r->print('<select name="subject">');
    $r->print('<option value="Math">Math</option>');
    $r->print('<option value="Science">Science</option>');
    $r->print('</select>');
    $r->print('<input type="submit" value="Add Category">');
    %fields = ('menu'=>'resources',
                'resourceid' => $r->param('resourceid'),
                  'submenu' => 'categories',
                  'action'=>'savecategory');
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
    my $categories = &get_categories();
    $r->print('<strong>All Categories</strong><br />');
    foreach my $category(@$categories) {
        %fields = ('token' => $env{'token'},
                'resourceid' =>  $r->param('resourceid'),
                'categoryid' => $$category{'id'},
                'menu' => 'resources',
                'submenu' => 'categories',
                'action' => 'saveresourcecat');
        my $url = &build_url("editor",\%fields);
        $r->print('<a href="'.$url.'">'.$$category{'category'}."</a><br />");
    }
    my $resource_categories = &get_resource_categories($r->param('resourceid'));
    $r->print('<strong>Resource Categories</strong><br />');
    foreach my $category(@$resource_categories) {
        %fields = ('token' => $env{'token'},
                'resourceid' =>  $r->param('resourceid'),
                'categoryid' => $$category{'id'},
                'menu' => 'resources',
                'submenu' => 'categories',
                'action' => 'removeresourcecat');
        my $url = &build_url("editor",\%fields);
        $r->print('<a href="'.$url.'">'.$$category{'category'}."</a><br />");
    }
    return 'ok';
}   
sub update_user_form {
    my ($r, $user_hashref) = @_;
    my $output = qq~
    <div class="vpdRecordForm">
        <form method="post" action="">
        <font color="#000000">Update a User</font>
        <div class="vpdRecordInputRow">
            <div class="vpdRecordTitle">PROM/SE ID:
                
            </div>
            <div class="vpdRecordInput">
                <input class="vpdRecord" type="text" size="30" name="promseid" value="$$user_hashref{'PROMSE_ID'}" />
            </div>
        </div>
        <div class="vpdRecordInputRow">
            <div class="vpdRecordTitle">Last Name:
                
            </div>
            <div class="vpdRecordInput">
                <input class="vpdRecord" type="text" size="30" name="lastname" value="$$user_hashref{'LastName'}" />
            </div>
        </div>
        <div class="vpdRecordInputRow">
            <div class="vpdRecordTitle">First Name:
                
            </div>
            <div class="vpdRecordInput">
                <input class="vpdRecord" type="text" size="30" name="firstname" value="$$user_hashref{'FirstName'}" />
            </div>
        </div>
        <div class="vpdRecordInputRow">
            <div class="vpdRecordTitle">Email:
                
            </div>
            <div class="vpdRecordInput">
                <input class="vpdRecord" type="text" size="30" name="email" value="$$user_hashref{'Email'}" />
            </div>
        </div>
        <div class="vpdRecordInputRow">
            <div class="vpdRecordTitle">Alt. Email:
                
            </div>
            <div class="vpdRecordInput">
                <input class="vpdRecord" type="text" size="30" name="emailwork" value="$$user_hashref{'Emailwork'}" />
            </div>
        </div>
        <div class="vpdRecordInputRow">
            <div class="vpdRecordTitle">User Name:
                
            </div>
            <div class="vpdRecordInput">
                <input class="vpdRecord" type="text" size="30" name="username" value="$$user_hashref{'username'}" />
            </div>
        </div>
        <div class="vpdRecordInputRow">
            <div class="vpdRecordTitle">Content:
                
            </div>
            <div class="vpdRecordInput">
    ~;
    $r->print($output);
    my @options = ({'Math'=>'Math'},{'Science'=>'Science'});
    $r->print(&build_select("subject",\@options,$$user_hashref{'subject'}));
    $output = qq~
                
            </div>
        </div>
        <div class="vpdRecordInputRow">
            <div class="vpdRecordTitle">Bio:
                
            </div>
            <div class="vpdRecordInput">
                <textarea class="vpdTextArea" name="bio" cols="40" rows="5">$$user_hashref{'Bio'}</textarea>
            </div>
        </div>
   ~;
    $r->print($output);
    my %fields = ('submenu'=>'edituser',
                  'userid'=>$$user_hashref{'id'},
                  'menu'=>'users',
                  'action'=>'update'
                  );
    $r->print(&hidden_fields(\%fields));
    $r->print('<input class="vpdRecordButton" type="submit" name="Submit" value="Update User" />'."\n");
    $r->print('</form>');
    $fields{'target'} = 'userlocations';
    $fields{'token'} = $env{'token'};
    my $url = &build_url("admin",\%fields);
    $r->print('<a href="'.$url.'">Manage User Locations</a>');
    $r->print('</div>');
    return 'ok';   
}
sub manage_user_locations {
    my ($r) = @_;
    if ($env{'action'} eq 'updatelocation') {
        my %fields = ('user_id'=>$r->param('userid'),
                      'loc_id'=>$r->param('locationid'),
                      'year'=>$r->param('year')
                    );
        &save_record('user_locs',\%fields);
        $r->print('Saving New location');
    }
    my @locations = &get_user_locations($r->param('userid'));
    if ($env{'action'} eq 'deletelocation') {
        my @checked_locations = $r->param('location');
        foreach my $l(@checked_locations) {
            my $delete_location = $locations[$l];
            my $year = $$delete_location{'year'};
            my $user_id = $r->param('userid');
            my $loc_id = $$delete_location{'location_id'};
            my $qry = "DELETE FROM user_locs WHERE year = $year AND
                         user_id = $user_id AND loc_id = $loc_id";
            $env{'dbh'}->do($qry);
        }
        @locations = &get_user_locations($r->param('userid'));
    }
    my $user_profile = &get_user_profile($r->param('userid'));
    my $display_name = $$user_profile{'firstname'}." ".$$user_profile{'lastname'};
    my @districts = &get_districts();
    my $district_pulldown = &build_select('districtid',\@districts,"",' onChange="retrieveSchools()" ');
    my @years = ({'2004'=>'2004'},
                {'2005'=>'2005'},
                {'2006'=>'2006'},
                {'2007'=>'2007'},
                  {'2008'=>'2008'},
                  {'2009'=>'2009'});  
    my $year_select = &build_select('year',\@years,"",'',' 4em ');
    my $javascript = qq ~
    <script type="text/javascript" >
        var token="$Apache::Promse::env{'token'}";
        populateFormFirst();
        var districtid;
        function populateFormFirst() {
            try {
                districtid = document.getElementById("districtid").value;
                clearTimeout(t);
                retrieveSchools();
            } 
            catch (e) {
                return;
            }
        }
        var t=setTimeout("populateFormFirst()",200)
        function retrieveSchools() {
            var xmlHttp;
            document.getElementById("statusMessage").innerHTML="Loading";
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
                    document.getElementById("statusMessage").innerHTML="&nbsp;";  
                    // timedMsg();     
                }
            }
            var districtid = document.getElementById("districtid").value;
            xmlHttp.open("GET","/promse/flash?token="+token+";action=getdistrictschools;districtid="+districtid,true);
            xmlHttp.send(null);
        }        
                
        function timedMsg() {
            var t=setTimeout("ajaxFunction()",5000)
        }  
      
    </script>
    <img id="spacer" src="../images/spacer.gif" />
    ~;
    $r->print($javascript);
    $r->print('<div class="userLocationForm">');
    $r->print('<form method="post" action="">');
    $r->print('Editing Location Information for: <strong>'.$display_name.'</strong>');
    $r->print('<span id="statusMessage"></span>');
    $r->print('<div class="formRow">');
    $r->print('<div class="fieldTitle">District:</div>');
    $r->print('<div class="fieldInput">');
    $r->print($district_pulldown);
    $r->print('</div>');
    $r->print('</div>');
    $r->print('<div class="formRow">');
    $r->print('<div class="fieldTitle">School:</div>');
    $r->print('<div class="fieldInput">');
    $r->print('<span id="schoolselectspan"></span>');
    $r->print('</div>');       
    $r->print('</div>'); 
    $r->print('<div class="formRow">');
    $r->print('<div class="fieldTitle">Year:</div>');
    $r->print('<div class="fieldInput">');
    $r->print($year_select);
    $r->print('</div>');       
    $r->print('</div>'); 
       
    my %fields = ('target'=>'userlocations',
                  'userid'=>$r->param('userid'),
                  'action'=>'updatelocation',
                  'menu'=>'userroles');
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" value="Add User Location" />');
    $r->print('</form>');
    $r->print('</div>');
    $r->print('<div>');
    my $counter = 0;
    $r->print('<form method="post" action="" >');
    $r->print('Current locations');
    foreach my $location (@locations) {
        $r->print('<div>');
        $r->print('<input type="checkbox" name="location" value="'.$counter.'" />');
        $r->print($$location{'school'}.$$location{'year'});
        $r->print('</div>');
        $counter ++;
    }
    %fields = ('target'=>'userlocations',
                  'userid'=>$r->param('userid'),
                  'action'=>'deletelocation',
                  'menu'=>'userroles');
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" value="Remove Location(s)" />');
    $r->print('</form>');
    $r->print('</div>');
    return 1;
}
sub update_user  {
    my ($r) = @_;
    print STDERR "\n ***** updating user ****** \n";
    my $promseid = &fix_quotes($r->param('promseid'));
    my $firstname = &fix_quotes($r->param('firstname'));
    my $lastname = &fix_quotes($r->param('lastname'));
    my $email = &fix_quotes($r->param('email'));
    my $altemail = &fix_quotes($r->param('altemail'));
    my $state = &fix_quotes($r->param('state'));
    my $password = &fix_quotes($r->param('userpassword'));
    my $username = &fix_quotes($r->param('username'));
    my $bio = &fix_quotes($r->param('bio'));
    my $level = &fix_quotes($r->param('level'));
    my $subject = &fix_quotes($r->param('subject'));
    my $userid = $r->param('userid');
	my $tj_class_id = $r->param('tjclassid');
    my %id = ('id' => $userid);
    my %fields = ('PROMSE_ID' => $promseid,
                  'FirstName' => $firstname,
                  'LastName' => $lastname,
                  'Email' => $email,
                  'Emailwork' => $altemail,
                  'State' => $state,
                  'username' => $username,
                  'Bio' => $bio,
                  'level' => $level,
                  'subject' => $subject);
    my $err = &update_record('users',\%id, \%fields);
	$err = $err?$err:'';
    # now have to deal with the location setting
    # for now we'll allow only one location for a user, so start by removing existing
    # location setting
    my $qry = "delete from user_locs where user_id = $userid";
    $env{'dbh'}->do($qry);
    my $location_id = $r->param('locationid')?$r->param('locationid'):0;
    if (!$location_id) {
       $location_id = $r->param('districtid')?$r->param('districtid'):0;
    }
    %fields = ('user_id'=>$userid,
               'loc_id'=>$location_id);
    &save_record('user_locs',\%fields);
	$qry = "DELETE FROM tj_user_classes WHERE tj_user_classes.user_id = $userid";
	$env{'dbh'}->do($qry);
	foreach my $tj_class($r->param('tjclassid')) {
		$qry = "INSERT INTO tj_user_classes (user_id, class_id) VALUES ($userid, $tj_class)";
		$env{'dbh'}->do($qry);
	}
    return ($err);
}
sub update_resource_form {
    my ($r, $resource_hashref) = @_;
    print '<form method="post" action="">';
    print '<table width="90%" border="0" cellspacing="1" cellpadding="2">';
    print '<tr><td colspan="2" class="header"><font color="#000000">Update a Resource</font></td></tr>'."\n";
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>Title:</strong></td><td align="left">'."\n";
    print '<input type="text" size="50" name="title" value="'.$$resource_hashref{'title'}.'" /></tr>'."\n";
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>Author:</strong></td><td align="left">'."\n";
    print '<input type="text" size="50" name="author" value="'.$$resource_hashref{'author'}.'" /></tr>'."\n";
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>URL:</strong></td><td align="left">'."\n";
    print '<input type="text" size="50" name="location" value="'.$$resource_hashref{'location'}.'" /></tr>'."\n";
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>Subject:</strong></td><td align="left">'."\n";
    my @options = ({'Math'=>'Math'},{'Science'=>'Science'});
    $r->print(&build_select("subject",\@options,$$resource_hashref{'subject'}),'','','');
    print '</tr>';
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>Type:</strong></td><td align="left">';
    my $types = &get_resource_types();
    @options = ();
    foreach my $type (@$types) {
        push @options, {($type=>$type)};
    }
    $r->print(&build_select("type",\@options,$$resource_hashref{'type'},'','',''));
    $r->print('</td></tr>');
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>Usage:</strong></td><td align="left">';
    $r->print(&intended_use_select($$resource_hashref{'intended_use'}));
    print '</tr>';
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>Time Commitment:</strong></td><td align="left">';
    $r->print(&time_commitment_select($$resource_hashref{'time_commitment'}));
    print '</tr>';
    print '<tr bgcolor="#EEEEEE" class="content"><td align="left"><strong>Comments:</strong></td>';
    print '<td align="left" valign="top"><textarea name="comments" cols="55" rows="10">'.$$resource_hashref{'comments'}.'</textarea></td></tr>';
    print '<tr align="center" valign="middle" bgcolor="#FFFFFF" class="content">';
    print '<td colspan="2">';
    my %fields;
    if ($env{'submenu'} eq 'editcourseonly') {
        %fields = ('resourceid'=>$$resource_hashref{'id'},
                    'courseid'=>$env{'course_id'},
                      'submenu'=>'build',
                      'menu'=>'courses',
                      'action'=>'updatecourseonly');
    } else {
        %fields = ('target'=>'resource',
                      'resourceid'=>$$resource_hashref{'id'},
                      'submenu'=>'browse',
                      'menu'=>'resources',
                      'action'=>'update');
    }
    $r->print(&hidden_fields(\%fields));
    print '<input type="submit" name="Submit" value="Update Resource" /></td></tr>'."\n";
    print '</table>'."\n";
    print '</form>'."\n";
    return 'ok';
}
sub intended_use_select {
    my ($selected) = @_;
    my $output;
    my @options = ({'Classroom Lesson'=>'1'},{'Classroom Unit'=>'2'},{'Classroom Tool'=>'3'},
                {'Content Brushup'=>'4'},{'Content Tutorial'=>'5'},{'Content Intensive'=>'6'},
                {'Content Extensive'=>'7'});
    $output .= &build_select("intendeduse",\@options,$selected,'','','');
    return($output);
}

sub time_commitment_select {
    my ($selected) = @_;
    my $output;
    my @options = ({'&lt;10 Min.'=>'1'},
                    {'10-30 Min.'=>'2'},
                    {'30-60 Min.'=>'3'},
                    {'1-2 Hrs.'=>'4'},
                    {'2-4 Hrs.'=>'5'},
                    {'1-2 Days'=>'6'},
                    {'2-5 Days'=>'7'});
    $output .= &build_select("timecommitment",\@options,$selected,'','','');
    return($output);
}
sub upload_resource_form {
    my ($r, $resource_hashref) = @_;
    my $url = &get_base_url($r);
    $r->print('<h4>Add a Resource</h4>');
    if ($env{'submenu'} eq 'addcourseonlyresource') {
        $r->print('This resource will be available only with this course.');
    } else {
    }
    $r->print('<div class="resourceFormContainer">');
    $r->print('<form action="'.$url.'" method="post" enctype="multipart/form-data">');
    $r->print('<fieldset>');
    
    $r->print('<div class="resourceFormRow">');
    
    $r->print('<div class="resourceFormField">');
    $r->print('<label>Subject</label>');
    my %option;
    my @options = ({'Math'=>'Math'},{'Science'=>'Science'});
    $r->print(&build_select("subject",\@options,undef));
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<label>Resource Type:</label>');
    my $types = &get_resource_types();
    @options = ();
    foreach my $type (@$types) {
        push @options, {($type=>$type)};
    }
    $r->print(&build_select("type",\@options,undef));
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<label>Time:</label>');
    $r->print(&time_commitment_select());   
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<label>Intended Use:</label>');
    $r->print(&intended_use_select());   
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    print '<label>Select File:</label>';
    print ' <INPUT TYPE="file" NAME="resource" />';
    $r->print('</div>'); # end field
    $r->print('</div>'); # end form row
    
    $r->print('<div class="resourceFormRow">');
    $r->print('<div class="resourceFormField">');
    $r->print('<label>Location (URL):</label>');
    $r->print('<input type="text" size="50" name="location" />');
    $r->print('</div>');
    $r->print('</div>');
    
    $r->print('<div class="resourceFormRow">');
    $r->print('<div class="resourceFormField">');
    $r->print('<label>Title:</label>');
    $r->print('<input type="text" size="30" name="title" />');
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    print '<label>Author:</label>';
    print '<input type="text" size="30" name="author" />';
    $r->print('</div>');
    $r->print('</div>');
    
    $r->print('<div class="resourceFormRow">');
    $r->print('<div class="resourceFormField">');
    print '<label>Comments:</label>';
    print '<textarea name="comments" cols="55" rows="10"></textarea>';
    $r->print('</div>');
    $r->print('<div class="resourceFormSubmit">');
    print '<input type="submit" name="Submit" value="Submit Resource" />';
    $r->print('</div>');
    $r->print('</div>');
    $r->print('</fieldset>');
    my %fields;
    if ($env{'submenu'} eq 'addcourseonlyresource') {
        %fields = ('menu'=>'courses',
                      'submenu'=>'build',
                      'courseid'=>$env{'course_id'},
                      'action'=>'insertcourseonlyresource');
    } else {
        %fields = ('target'=>'resource',
                      'menu'=>'resources',
                      'submenu'=>'browse',
                      'action'=>'upload');
    }             
    $r->print(&hidden_fields(\%fields));
    print '</form>';
    $r->print('</div>'); # close resource form container
    return 'ok';   
}

sub framework_grabber_form {
    my ($r) = @_;
    print '<form method="post" action="mentor">';
    print '<input type="text" name="level">';
    print '<input type="text" name="level">';
    print '<select name="subject"><option value="science">Science</option><option value="math">Math</option></select>';
    print '<input type="hidden" name="token" value="'.$env{'token'}.'">';
    print '<input type="hidden" name="target" value="framework">';
    print '<input type="hidden" name="menu" value="browse">';   
    print '<input type="submit" name="Submit" value="Submit Resource">';

    print '</form>';
    return 'ok';
}
sub standard_gizmo {
    my ($r)= @_;
    my $tag = $env{'action'};
    my $target = $r->param('target');
    my $resource_id = $r->param('resourceid');
    my $click_cell;
    my $subject;
    my $url = &get_base_url;
    my $qry = "";
    my $sth;
    my @benchmark_grades;
    my @indicator_grades;
    my @strands;
    my $benchmark_grade;
    my $strand_id;
    if ($r->param('benchmarkgrade')) {
       $benchmark_grade = $r->param('benchmarkgrade'); 
    } else {
        $benchmark_grade = "k-2";
    }
    if ($r->param('strand')) {
       $strand_id = $r->param('strand'); 
    } else {
        $strand_id = "1";
    }
    
    $qry = 'select * from ohio_math_strands';
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref){
       push @strands, {%$row};  
    }
    
    $qry = 'select distinct grade from ohio_math_benchmarks';
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref){
       push @benchmark_grades, $$row{'grade'};  
    }
    $qry = 'select distinct grade from ohio_math_indicators';
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref){
       push @indicator_grades, $$row{'grade'};  
    }
    $r->print ('<form method="post" action="mentor">');
    $r->print('<select class="wider" name="benchmarkgrade">');
    foreach my $disp_grade(@benchmark_grades) {
        $r->print('<option>'.$disp_grade.'</option>');
    }
    $r->print('</select>');
    $r->print('<select name="strand">');
    foreach my $strand(@strands) {
        $r->print('<option value="'.$$strand{'strand_id'}.'">'.$$strand{'description'}.'</option>');
    }
    $r->print('</select>');
    $r->print('<input type="submit" value="Show Benchmarks">');
    $r->print('<input type="hidden" value="'.$env{'token'}.'" name="token">');
    $r->print('<input type="hidden" value="ohiomath" name="target">');
    $r->print('</form>');
    
    my $java_script = qq ~
    <script type="text/javascript">
    
    </script>
    ~;
    $r->print($java_script);
    $qry = "select * from ohio_math_benchmarks WHERE grade = '$benchmark_grade' and strand_id = $strand_id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<div id="standards">');
    while (my $row = $sth->fetchrow_hashref){
        $r->print($$row{'description'}.'<br />');
        
    }
    $r->print('</div>');
    return 'ok';
}

sub get_user_expertise {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my %expertise;
    $qry = "select * from user_expertise where user_id = ".$env{'user_id'};
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        $expertise{$$row{'subject'}.$$row{'framework_index'}} = $$row{'level'};
    }
    return \%expertise;
}
sub framework_gizmo {
    my ($r, $context)= @_;
    my $expertise;
    my $tag;
    if ($env{'action'}) {
        $tag = $env{'action'};
        if ($tag eq 'Add Tag') {
            $tag = 'tag';
        }
    } else {
        $tag = $context;
    }
    if ($context eq 'expertise') {
        # returns hash ref where key is subject.index and value is level
        $expertise = &get_user_expertise($r);
    }
    my $target = $r->param('target');
    my $resource_id = $r->param('resourceid');
    my $click_cell;
    my $subject;
    my $url = &get_base_url;
    if (defined ($r->param('code'))) {
        $click_cell = $r->param('code');
    } else {
        $click_cell = '1';
    }
    if (defined ($r->param('subject'))) {
        $subject = $r->param('subject');
    } else {
        $subject = 'math';
    }
    my @parent_cell;
    #click sell has the form 1.2.3.4, from this we want to create
    # 1 1.2 1.2.3 1.2.3.4 and 1.2.3.4.*
    $click_cell .= '.n';
    my @mess = split /\./, $click_cell;
    my $build;
    foreach my $seg (@mess) {
        $build .= $seg.'.';
        my $save = $build;
        $save =~ s/\.$//;
        #print "saving $save <br />";
        push @parent_cell, $save;
    }
    if (@parent_cell) {
    } else {
         $parent_cell[0] = '1';
         $parent_cell[1] = '1.1';
    }
    if (defined $subject) {
    } else {
        $subject = 'math'
    }
    if ($tag eq 'tag' || $tag eq 'expertise') {
        print '<form method="post" action="'.$url.'">';
    }
    print '<span><a href="'.$url.'?token='.$env{'token'}.';action='.$tag.';resourceid='.$resource_id.';target='.$target.';subject=math;code=1">';
    if ($subject eq 'math') {
        print '<strong>[ Math ]</strong></a>';
    } else {
        print '[ Math ]</a>';
    }
    print '<a href="'.$url.'?token='.$env{'token'}.';action='.$tag.';resourceid='.$resource_id.';target='.$target.';subject=science;code=1">';
    if ($subject eq 'science') {
        print '<strong>[ Science ]</strong></a>';
    } else {
        print '[ Science ]</a>';
    }
    print '</span>';
    
    print '<table><tr>';
    foreach my $column (@parent_cell) {
        # this will print a table intended to occupy a column in table outside this loop
        print '<td valign="top">';
        &framework_grabber($r, $subject, $column, $context, $expertise);
        print '</td>';
    }
    print '</tr></table>';
    if ($tag eq 'tag') {
        print '<input type="submit" name="submit" value="Tag Resource">';
        print '<input type="hidden" name="token" value="'.$env{'token'}.'">';
        print '<input type="hidden" name="subject" value="'.$subject.'">';
        print '<input type="hidden" name="target" value="resource">';
        print '<input type="hidden" name="resourceid" value="'.$r->param('resourceid').'">';
        print '<input type="hidden" name="menu" value="browse">';
        print '<input type="hidden" name="action" value="tag">';
        print '</form>';
    } elsif ($tag eq 'expertise') {
        print '<input type="submit" name="submit" value="Save Interests">';
        print '<input type="hidden" name="token" value="'.$env{'token'}.'">';
        print '<input type="hidden" name="subject" value="'.$subject.'">';
        print '<input type="hidden" name="target" value="preferences">';
        print '<input type="hidden" name="action" value="expertise">';
        print '</form>';
    }
    return 'ok';
}


sub framework_reporter_grabber {
    my ($r, $subject, $level, $context, $expertise) = @_;
    my $district_id = $r->param('district');
    my $grade = $r->param('grade');
    my $tag;
    if ($env{'action'}) {
        $tag = $env{'action'};
    } else {
        $tag = $context;
    }
    my $resourceid = $r->param('resourceid');
    my $target = $r->param('target');
    # lots to do here!
    # @levels has to be a legit index of a framework element
    # assume to 0 element is highest of hierarchy if only one element
    # then only the top title is shown
    my $table = $subject.'_framework';
    my $bg_color_class;
    my $sql_regexp_sibs;
    my $sql_regexp_child;
    my @return_framework;
    my $url = &get_base_url($r);
    #have to build regexp in form ^level\\.level\\.[0-9]*$
    #first case is no periods in $level (which is the "parent cell")
    #in that case, we select the entire top level stuff
    my @levels = split /\./,$level;
    $sql_regexp_child = '^';
    $sql_regexp_sibs = '^';
    foreach my $sub_level (@levels) {
        $sql_regexp_child .= $sub_level.'\\.';
    }
    $sql_regexp_child .= '[0-9]*$';
    pop @levels; #this removes one of the levels, so we can retrieve the siblings
    foreach my $sub_level (@levels) {
        $sql_regexp_sibs .= $sub_level.'\\.';
    }
    $sql_regexp_sibs .= '[0-9]*$';
    
    my $qry = "select description, code, id, framework_id from $table ";
    $qry .= " LEFT JOIN dist_intended_curriculum as t2 on id = framework_id ";
    $qry .= " and t2.subject = '$subject' and t2.grade = $grade and t2.district_id = $district_id ";
    $qry .= " where code REGEXP '$sql_regexp_sibs' ";
    # print "<br />$qry</br>";
    my $sth;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    print "<table>";
    while (my $framework_description = $sth->fetchrow_hashref) {
        if ($$framework_description{'code'} eq $level) {
            $bg_color_class = 'highlight';
        } else {
            $bg_color_class = 'lowlight';
        }
        print '<tr class="'.$bg_color_class.'"><td colspan="4">';
      
        if ($tag eq 'tag' || $tag eq 'expertise') {
            $r->print('<select name="level"><option>1</option><option>2</option><option>3</option></select>');
            $r->print('<input type="checkbox" name="tagcell" value="'.$$framework_description{'code'}.'" ');
            if (exists $$expertise{$subject.$$framework_description{'code'}}) {
                $r->print(' CHECKED');
            }
            $r->print(' />');
        } 
        print '<span><a href="'.$url.'?token='.$env{'token'}.';action='.$tag.';resourceid='.$resourceid.';target='.$target.';subject='.$subject.';district='.$district_id.';grade='.$grade.';code='.$$framework_description{'code'}.'">'.$$framework_description{'code'}."<br />".$$framework_description{'description'}."</a></span></td></tr>";
        if ($$framework_description{'framework_id'}) {
            $r->print('<tr class="background-color:#c00;" ><td style="background-color:#c00;">&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>');
        }
    }
    print "</table>";
    return 'ok';
}
sub get_partners {
    # returns hash with key=district_name and value = district_id
    my $qry = "";
    my $sth;
    my @return_array;
    $qry = "select partner_id, partner_name from partners order by partner_name";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        my $rec={};
        push @return_array, {$$row{'partner_name'}=>$$row{'partner_id'}}
    }
    return @return_array;
}
sub get_agency_types {
    # returns hash with key=district_name and value = district_id
    my $qry = "";
    my $sth;
    my @return_array;
    $qry = "select id, agency from agency_types order by agency";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        my $rec={};
        push @return_array, {$$row{'agency'}=>$$row{'id'}}
    }
    return @return_array;
}
sub get_tj_teachers {
	my ($r) = @_;
	my @tj_teachers;
	my $qry = "SELECT users.id, users.firstname, users.lastname, tj_classes.class_id, tj_classes.class_name,
					FROM users, tj_classes, tj_user_classes 
					WHERE users.id = tj_user_classes.user_id AND
							tj_user_classes.class_id = tj_classes.class_id
					ORDER BY users.lastname, users.firstname";
	print STDERR $qry . "\n";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	while (my $row = $rst->fetchrow_hashref()) {
		push(@tj_teachers,{%$row});
	}
	return (@tj_teachers);
}
sub get_tj_classes {
    # returns hash with key=district_name and value = district_id
    my ($r) = @_;
    my $qry = "SELECT tj_classes.class_id, tj_classes.class_name, tj_classes.grade, tj_classes.notes 
				FROM tj_classes
				ORDER BY tj_classes.class_name ";
    my $sth;
    my @return_array;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @return_array, {$$row{'class_name'}=>$$row{'class_id'}};
    }
    return @return_array;
}

sub get_districts {
    # returns hash with key=district_name and value = district_id
    my ($r) = @_;
    my $qry = "";
    my $sth;
    my @return_array;
    if ($env{'demo_mode'}) {
        $qry = "select district_id, district_alt_name as district_name from districts order by district_name";
    } else {
        $qry = "select district_id, district_name from districts order by district_name";
    }
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        push @return_array, {$$row{'district_name'}=>$$row{'district_id'}};
    }
    return @return_array;
}
sub get_district_info {
	my($district_id) = @_;
	my $qry = "SELECT * FROM districts where district_id = ?";
	my $sth = $env{'dbh'}->prepare($qry);
	$sth->execute($district_id);
	my $district_info = $sth->fetchrow_hashref();
	return($district_info);
}
sub get_user_locations {
    my ($user_id) = @_;
    my $qry = "";
    my $sth;
    my @locations;
    if ($env{'demo_mode'}) {
        $qry = "SELECT school, district_alt_name as district_name, t1.district_id, t1.location_id, t1.zip, year
                FROM locations t1, user_locs t2, districts t3 ";
    } else {
        $qry = "SELECT school, district_name, t1.district_id, t1.location_id, t1.zip, year
                FROM locations t1, user_locs t2, districts t3 ";
    }
    $qry .=" WHERE t1.location_id = t2.loc_id AND 
                t1.district_id = t3.district_id AND ".$user_id." = t2.user_id
                ORDER BY year desc";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push(@locations,{%$row});
    }
    return @locations;
}
sub get_user_location {
    my $qry = "";
    my $sth;
    print STDERR "user id in get_user_location is " . $env{'user_id'};
    $qry = "SELECT school, district_name, t3.district_id, t1.location_id, t1.zip
            FROM  user_locs t2
            LEFT JOIN locations t1 on t1.location_id = t2.loc_id
            LEFT JOIN districts t3 on (t2.loc_id = t3.district_id) OR
                      (t1.district_id = t3.district_id)
            WHERE $env{'user_id'} = t2.user_id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref;
    return $row;
}
sub survey_link {
    my ($r) = @_;
    #  need to read survey_id from user record somehow.
#    $r->print('We are currently conducting surveys for all teachers. We hope you can spend some time in completing the surveys. ');
#    $r->print('There are a total of three sets of surveys for each teacher. The first set is the same set for both Mathematics and Science teachers.');
#    $r->print('The remaining sets are different. Please click on the links below to begin.<br />');
#    $r->print('Thank you for your time.<br />');
#    $r->print('<a href="apprentice?target=survey&token='.$env{'token'}.'&survey_id=1">For all teachers</a> <br />');
#    $r->print('<a href="apprentice?target=survey&token='.$env{'token'}.'&survey_id=2">2nd set for Mathematics teachers</a> <br />');
#    $r->print('<a href="apprentice?target=survey&token='.$env{'token'}.'&survey_id=3">3rd set for Mathematics teachers</a> <br />');
#    $r->print('<a href="apprentice?target=survey&token='.$env{'token'}.'&survey_id=4">2nd set for Science teachers</a> <br />');
#    $r->print('<a href="apprentice?target=survey&token='.$env{'token'}.'&survey_id=5">3rd set for Science teachers</a> <br />');
    $r->print('<a class="survey" href="apprentice?target=survey;token='.$env{'token'}.';survey_id=6">Brief Technology Survey</a> <br />');
    $r->print('<a class="survey" target="_blank" href="http://www.zoomerang.com/survey.zgi?p=WEB2269TFXN27N" >Facilitator Evaluation - PROM/SE Summer Academies</a><br />');
    
    return 'ok';
}
sub survey_save_answer {
    my ($r) = @_;
    my $q_num = $r->param('q_num');
    my $survey_id = $r->param('survey_id');
    my $qry;
    my %fields;
    my $save_flag;
    my $field_name;
    # need to replace existing answers, or add as needed
    # check if progress shows q_num answered
    $qry = "select * from survey_progress where user_id = ".$env{'user_id'}." and survey_id = $survey_id and q_num = $q_num";
    my $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();

    # $r->print('Saving an answer <br />');
    foreach my $field ($r->param()) {
        if ($field =~ /surv_(.+)/) {
            $field_name = $1;
            # now check if it's an array of values
            my @stuff = $r->param($field);
            foreach my $value(@stuff) {
                if ($value =~ m/.+/) {
                    $fields{'answer'} = &fix_quotes($value);
                    $fields{'field_name'} = &fix_quotes($field_name);
                    $fields{'q_num'} = $q_num;
                    $fields{'user_id'} = $env{'user_id'};
                    $fields{'survey_id'} = $survey_id;
                    &save_record('survey_answers',\%fields);
                }
            }
            $save_flag = 'true';
        }
    }
    if ($save_flag eq 'true') {
        $qry = "delete from survey_answers where answer=''";
        #$env{'dbh'}->do($qry);
        $qry = "delete from survey_progress where user_id = ".$env{'user_id'}." and survey_id = $survey_id and q_num = $q_num";
        $env{'dbh'}->do($qry);
        undef (%fields);
        $fields{'user_id'} = $env{'user_id'};
        $fields{'survey_id'} = $survey_id;
        $fields{'q_num'} = $q_num;
        &save_record('survey_progress',\%fields);
    }
    
    
    # if yes, blow away old answers, and insert new ones
    # if no, then just insert new ones
    return 'ok';
}
sub survey {
    my ($r) = @_;
    # first, will save answer, then display progress, finally offer next question.
    # could enter with no question set, with question answered, or with NEXT question set
    if ($r->param('save_answer')) {
        &survey_save_answer($r);
    }
    my $strong_on;
    my $strong_off;
    my $q_num = 1;
    my $progress = &survey_progress($r);
    foreach my $p (@$progress) {
        if ($$p{'done'}) {
            $q_num = $$p{'q_num'} + 1;
            $strong_on = '<strong>';
            $strong_off = '</strong>';
        } else {
            $strong_on = '';
            $strong_off = '';
        }
        $r->print($strong_on.'['.$$p{'q_num'}.']'.$strong_off);
        if ($$p{'q_num'} == 20) {
            $r->print('<br />');
        }
    }
    
    $r->print('<p>');
    my $qpath = "/var/www/html/questions/";
    my $q_txt = $$progress[$q_num - 1]{'q_txt'};
    open (QIN, "< $qpath"."$q_txt") || $r->print("can't open file $q_txt");
    my $question_text;
    while (<QIN>) {
        $question_text .= $_;
        # $r->print($_);
    }
    close QIN;
    if ($question_text) {
        $r->print('<form method="post" action="">');
        $r->print($question_text);
        $r->print('');
        my %hidden_fields;
        $hidden_fields{'survey_id'} = $r->param('survey_id');
        $hidden_fields{'q_num'} = $q_num;
        $hidden_fields{'target'} = 'survey';
        $hidden_fields{'save_answer'} = 'true';
        $r->print(&hidden_fields(\%hidden_fields));
        $r->print('<br /><input type="submit" value="Submit Answer">');
        $r->print('</form>');
    } else {
        $r->print('Thank you for completing the survey');
    }
    
    return 'ok';
}
sub survey_progress {
    my ($r) = @_;
    my $survey_id = $r->param('survey_id');
    my $i = 0;
    my @survey_path;
    my $qry = "select t1.q_txt, t1.q_num,  t2.q_num as done from survey_defs t1";
    $qry.= " LEFT JOIN survey_progress t2 on t2.user_id = ".$env{'user_id'}." and t1.survey_id = t2.survey_id and t1.q_num = t2.q_num";
    $qry.= " where t1.survey_id = $survey_id order by t1.q_num";
    # $r->print('<br />'.$qry.'<br />');
    my $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push (@survey_path, {%$row});
    }
    #return an array of hashes with keys of q_num, 'done' if done
    return (\@survey_path);
}
sub get_survey_def {
    my ($r) = @_;
    my $survey_id = $r->param('survey_id');
    my $qry = "select * from survey_defs where survey_id = $survey_id order by q_num";
    my $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    my @return_array;
    while (my $row = $sth->fetchrow_hashref()) {
        $return_array[$$row{'q_num'}] = {%$row};
    }
    return (\@return_array);
}
sub check_node {
    my ($district, $code, $children) = @_;
    my $qry = "";
    my $sth;
    my $selected;
    my $below;
    my %grades;
    my %grades_below;
    $qry = "select grade, code, framework_id from dist_intended_curriculum t1, math_framework t2";
    $qry .= " where t1.framework_id = t2.id and $district = district_id and code like '%".$code."' ";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    
    while (my  $row = $sth->fetchrow_hashref) {
        if ($$row{'code'} eq $code) {
            $selected=1;
            $grades{$$row{'grade'}} = 1;
        } else {
            $below=1;
            $grades_below{$$row{'grade'}} = 1;
        }
        
    }
    return ($selected, $below, \%grades, \%grades_below);
}
sub get_curriculum {
    my ($district, $state, $location_id) = @_;
    # returns @all_info, each element contains a hash %row_info
    my $qry = "";
    my $sth;
    my @all_info;
    my %row_info;
    my %grades;
    my %grades_below;
    $qry = "SELECT t2.code as topic_code, t2.id as topic_id, t1.code as dist_code, t1.description, t3.grade as dist_grade, ";
    $qry .= " t4.grade as state_grade, t5.grade as intended_grade, t6.grade as achieved_grade "; 
    $qry .= " from math_framework t1 ";
    $qry .= " JOIN math_topics t2 on t1.code like concat(t2.code,'%') ";
    $qry .= " LEFT JOIN dist_intended_curriculum t3 on t1.id = t3.framework_id and t3.subject = 'math' and t3.district_id = $district ";
    $qry .= " LEFT JOIN intended_curriculum t4 on t4.framework_id = t1.id and t4.state = '$state' ";
    $qry .= " LEFT JOIN implemented_curriculum t5 on t5.framework_id = t1.id and t5.location_id = $location_id ";
    $qry .= " LEFT JOIN achieved_curriculum t6 on t6.framework_id = t1.id and t6.location_id = $location_id ";
    $qry .= "WHERE t1.code like concat(t2.code,'%')  ";
    $qry .= "ORDER by t2.id, t1.id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    return ($sth);
}
sub get_math_topics {
    my ($sort_field) = @_;
    my $qry = "";
    my $sth;
    my @return_array;
    unless ($sort_field) { 
        $sort_field = 'id';
    }
    $qry = "select t1.id, t1.code, description from math_topics t1, math_framework t2 where t1.code = t2.code order by $sort_field";
    $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push @return_array, $row;
    }
    return \@return_array;
}
sub districtid_to_name {
    my ($district_id) = @_;
    my $qry = "";
    my $sth;
    $qry = "select district_name from districts where district_id = $district_id";
    $sth=$env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row=$sth->fetchrow_hashref();
    return $$row{'district_name'};
}
sub display_23 {
    my ($r) = @_;
    my $loc_dist_hashref = &get_user_location($env{'user_id'});
    my $state_id;
    my $state_name;
    my $district_id;
    my $location_id = $$loc_dist_hashref{'location_id'};
    if ($location_id) {
        my $district_name;
        if ($r->param('district')) {
            $district_id = $r->param('district');
            $district_name = &districtid_to_name($district_id);
        } else {
            $district_id = $$loc_dist_hashref{'district_id'};
            $district_name = $$loc_dist_hashref{'district_name'};
        }
        if ($r->param('state')) {
            $state_id = $r->param('state');
            if ($state_id eq 'MI') {
                $state_name = 'Michigan';
            } elsif ($state_id eq 'OH') {
                $state_name = 'Ohio';
            }
        } else {
            $state_id = 'AP';
            $state_name = 'Top Achieving Countries';
        }
        my @grades = (1,2,3,4,5,6,7,8);
        my @districts = &get_districts();
        my %fields;
        $r->print('<br />Your district is '.$$loc_dist_hashref{'district_name'}.' and ');
        $r->print('school is '.$$loc_dist_hashref{'school'}.'<br />');
        $r->print('<form method="post" action="apprentice">');
        $r->print(&build_select('district',\@districts,$district_id));
        $r->print('<select name="state">');
        $r->print('<option ');
        if ($state_id eq "MI") {
            $r->print('SELECTED');
        }
        $r->print('>MI</option>');
        $r->print('<option ');
        if ($state_id eq "OH") {
            $r->print('SELECTED');
        }
        $r->print('>OH</option>');
        $r->print('<option value="AP" ');
        if ($state_id eq "AP") {
            $r->print('SELECTED');
        }
        $r->print('>Top Achieving Countries</option>');
        $r->print('</select>');
        $fields{'target'} = 'frameworkreporter';
        $fields{'menu'} = 'overall';
        $r->print('<input type="submit" value="Change District and State/Top Achieving Countries">');
        $r->print(&hidden_fields(\%fields));
        $r->print('</form>');
        
        $r->print('<img src="../images/0001.gif" alt="" />=Achieved -- ');
        $r->print('<img src="../images/0010.gif" alt="" />=Intended -- ');
        $r->print('<img src="../images/0100.gif" alt="" />='.$district_name.' -- ');
        $r->print('<img src="../images/1000.gif" alt="" />='.$state_name.' ');

#        $r->print('Here is the intended curriculum of <strong>'.$district_name.'('.$district_id.')</strong>:<br />');
#        $r->print('The blue squares are the '.$state_name.' curriculum.');
        if ($state_id eq "AP") {
            $r->print('<br />Note that this alignment is based on the comparison of the common content areas across the curricula.');
        }    
        my $sth = &get_curriculum($district_id, $state_id, $location_id);
        $r->print('<div>');
        $r->print('<table id="tableCurriculum">');
        $r->print('<tr><th></th><th colspan="8" align="center">Grade</th></tr>');
        $r->print('<tr><th align="center">Topic</th><th align="center">');
        $r->print('1</th><th align="center">2</th><th align="center">');
        $r->print('3</th><th align="center">4</th><th align="center">');
        $r->print('5</th><th align="center">6</th><th align="center">');
        $r->print('7</th><th align="center">8</th></tr><tbody id="tbodyCurriculum">');
        my $save_topic_code;
        my $save_sub_code;
        my %row_info;
        my %state_grade_cells;
        my %dist_grade_cells;
        my %intended_grade_cells;
        my %achieved_grade_cells;
        while (my $row=$sth->fetchrow_hashref()) {
            if ($save_topic_code eq $$row{'topic_code'}) {
                if ($$row{'topic_code'} eq $$row{'dist_code'}) {
                   if ($$row{'dist_grade'}) {
                        $dist_grade_cells{$$row{'dist_grade'}} = 'true';
                    } 
                    if ($$row{'state_grade'}) {
                        $state_grade_cells{$$row{'state_grade'}} = 'true';
                    }
                    if ($$row{'intended_grade'}) {
                        $intended_grade_cells{$$row{'intended_grade'}} = 'true';
                    } 
                    if ($$row{'achieved_grade'}) {
                        $achieved_grade_cells{$$row{'achieved_grade'}} = 'true';
                    }
                    
                }
            } else {
                if ($row_info{'description'}) {
                    &write_curriculum_row($r, \%row_info, \%state_grade_cells, \%dist_grade_cells, \%intended_grade_cells, \%achieved_grade_cells);
                    undef %dist_grade_cells;
                    undef %state_grade_cells;
                    undef %intended_grade_cells;
                    undef %achieved_grade_cells;
                    delete $row_info{'description'};
                }
                $save_topic_code = $$row{'topic_code'};
                $row_info{'description'} = $$row{'description'};
                $row_info{'topic_code'} = $$row{'topic_code'};
                if ($$row{'topic_code'} eq $$row{'dist_code'}) {
                    # need to pick the district or state grade info
                    if ($$row{'dist_grade'}) {
                        $dist_grade_cells{$$row{'dist_grade'}} = 'true';
                    } 
                    if ($$row{'state_grade'}) {
                        $state_grade_cells{$$row{'state_grade'}} = 'true';
                    }
                    if ($$row{'intended_grade'}) {
                        $intended_grade_cells{$$row{'intended_grade'}} = 'true';
                    } 
                    if ($$row{'achieved_grade'}) {
                        $achieved_grade_cells{$$row{'achieved_grade'}} = 'true';
                    }
                }
                # new topic, so new row of table begins
            }
        }
        if ($row_info{'description'}) {
           &write_curriculum_row($r, \%row_info, \%state_grade_cells, \%dist_grade_cells,\%intended_grade_cells,\%achieved_grade_cells);
        }
        
        $r->print('</tbody></table>');
        $r->print('</div>');
    } else {
        $r->print('Cannot do it, no location');
    }
    return 'ok';
}

sub write_curriculum_row {
    my ($r, $row_info, $state_grade_cells, $dist_grade_cells, $intended_grade_cells, $achieved_grade_cells) = @_;
    my $loc_dist_hashref = &get_user_location($env{'user_id'});
    my $district_id;
    my $district_name;
    if ($r->param('district')) {
        $district_id = $r->param('district');
        $district_name = &districtid_to_name($district_id);
    } else {
        $district_id = $$loc_dist_hashref{'district_id'};
        $district_name = $$loc_dist_hashref{'district_name'};
    }
    my @grades = (1,2,3,4,5,6,7,8);
    $r->print('<tr><td>');
    $r->print('<a href="apprentice?token='.$r->param('token').'&target=search&district='.$district_id.'&code='.$$row_info{'topic_code'}.'">');
    $r->print($$row_info{'description'}.'</a></td>');
    foreach my $grade (@grades) {
        my $cell_name = '0000';
        if ($$state_grade_cells{$grade}) {
            $cell_name = $cell_name | '1000';
        }
        if ($$dist_grade_cells{$grade}) {
            $cell_name = $cell_name | '0100';
        }
        if ($$intended_grade_cells{$grade}) {
            $cell_name = $cell_name | '0010';  
        }
        if ($$achieved_grade_cells{$grade}){
            $cell_name = $cell_name | '0001';
        }
        $r->print('<td><img src="../images/'.$cell_name.'.gif" alt="" /></td>');
    }
    $r->print('</tr>');
    return 'ok';
}

sub framework_reporter {
    my ($r, $context)= @_;
    my $step = $r->param('step');
    my %hidden_fields;

    my $url;
    $url = "apprentice?token=".$env{'token'}.";target=frameworkreporter";
#    $r->print('<div id="interiorHeader">');
#    $r->print('<h2>District, state, and exemplary curricula . . . </h2>');
#    $r->print('</div>');
    if ($env{'menu'} eq 'overall') {
        print '<a href="'.$url.'&menu=overall" ><strong style="content">[ Compare All Topics ]</strong></a>';
    } else {
        print '<a href="'.$url.'&menu=overall">[ Compare All Topics ]</a>';
    }
    if ($env{'menu'} eq 'topiccompare') {
        print '<a href="'.$url.'&menu=topiccompare"><strong>[ Compare Specific Topic ]</strong></a>';
    } else {
        print '<a href="'.$url.'&menu=topiccompare">[ Compare Specific Topic ]</a>';
    }
    $r->print('<br /><br />');
    if ($env{'menu'} eq 'overall') {
        &display_23($r);
    }
    if ($env{'menu'} eq 'topiccompare') {
        &topic_compare($r);
    }
    return 'ok';
}

sub topic_compare {
    my ($r)= @_;
    my $topics = &get_math_topics('description');
    my $loc_dist_hashref = &get_user_location($env{'user_id'});
    my $state_id;
    if ($r->param('state')) {
        $state_id = $r->param('state');
    } else {
        $state_id = "";
    }
    my $topic_id;
    my $state_name;
    my $district_id;
    my @districts = &get_districts();
    my $location_id = $$loc_dist_hashref{'location_id'};
        my $district_name;
    if ($r->param('district')) {
        $district_id = $r->param('district');
        $district_name = &districtid_to_name($district_id);
    } else {
        $district_id = $$loc_dist_hashref{'district_id'};
        $district_name = $$loc_dist_hashref{'district_name'};
    } 
    $r->print('<br />Your district is '.$$loc_dist_hashref{'district_name'}.' and ');
    $r->print('school is '.$$loc_dist_hashref{'school'}.'<br />');
    $r->print('<form method="post" action="apprentice">');
    $r->print('<select name="topic">');
    $r->print('<h4><OPTION SELECTED>Choose a topic</option>');
    my $select_flag = "";
    foreach my $row (@$topics) {
        if ($r->param('topic')) {
            if ($r->param('topic') eq $$row{'id'}) {
                $select_flag = ' SELECTED ';
            }
        } else {
            $select_flag = ' ';
        }
        $r->print('<option '.$select_flag.'value="'.$$row{'id'}.'">'.$$row{'description'}."</option>\n");
    }
    $r->print('</h4></SELECT><br />');
    $r->print('<select name="district">');
    $r->print(&build_select('district',\@districts,$district_id));
    $r->print('</select><br />');
    $r->print('<select name="state">');
    $r->print('<option ');
    if ($state_id eq "MI") {
        $r->print('SELECTED');
    }
    $r->print('>MI</option>');
    $r->print('<option ');
    if ($state_id eq "OH") {
        $r->print('SELECTED');
    }
    $r->print('>OH</option>');
    $r->print('<option value="AP" ');
    if ($state_id eq "AP") {
        $r->print('SELECTED');
    }
    $r->print('>Top Achieving Countries</option>');
    $r->print('</select>');
    my %fields;
    $fields{'menu'} = 'topiccompare';
    $fields{'target'} = 'frameworkreporter';
    $fields{'ready'} = 'true';
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" value="Display comparison"><br />');
    my %dist_grade_cells;
    my %state_grade_cells;
    my %intended_grade_cells;
    my %achieved_grade_cells;
    if ($r->param('ready') eq 'true') {
        # identify values to compare (topic, user's school dist, comparison dist, state standard)
        my $sth = &get_curriculum($district_id, $state_id, $location_id);
        while (my $row = $sth->fetchrow_hashref()) {
            if (($$row{'topic_id'} eq $r->param('topic')) && ($$row{'topic_code'} eq $$row{'dist_code'})) {
               if ($$row{'dist_grade'}) {
                    $dist_grade_cells{$$row{'dist_grade'}} = 'true';
                } 
                if ($$row{'state_grade'}) {
                    $state_grade_cells{$$row{'state_grade'}} = 'true';
                }
                if ($$row{'intended_grade'}) {
                    $intended_grade_cells{$$row{'intended_grade'}} = 'true';
                } 
                if ($$row{'achieved_grade'}) {
                    $achieved_grade_cells{$$row{'achieved_grade'}} = 'true';
                }
            } 
        }
        my @grades = (1,2,3,4,5,6,7,8,9,10,11,12);
        $r->print('<p align="center">The Result of Comparison</p>');
        $r->print('<table align="center" id="tableTopic">');
        $r->print('<tr><th align="center">Curricula</th><th colspan="12" align="center">Grade</th></tr>');
        $r->print('<tr><th align="center">');
        $r->print('<th>1</th><th>2</th><th>3</th><th>4</th><th>5</th><th>6</th>');
        $r->print('<th>7</th><th>8</th><th>9</th><th>10</th><th>11</th><th>12</th></tr>');
        $r->print('<tr><td>Achieved</td>');
        foreach my $grade (@grades) {
            if ($achieved_grade_cells{$grade}) {
                $r->print('<td>X</td>');
            } else {
                $r->print('<td>&nbsp;</td>');
            }
        }
        $r->print('</tr>');
        $r->print('<tr><td>Intended</td>');
        foreach my $grade (@grades) {
            if ($intended_grade_cells{$grade}) {
                $r->print('<td>X</td>');
            } else {
                $r->print('<td>&nbsp;</td>');
            }
        }
        $r->print('</tr>');
        $r->print('<tr><td>District</td>');
        foreach my $grade (@grades) {
            if ($dist_grade_cells{$grade}) {
                $r->print('<td>X</td>');
            } else {
                $r->print('<td>&nbsp;</td>');
            }
        }
        $r->print('</tr>');
        $r->print('<tr><td>State/Top Achieving Countries</td>');
        foreach my $grade (@grades) {
            if ($state_grade_cells{$grade}) {
                $r->print('<td>X</td>');
            } else {
                $r->print('<td>&nbsp;</td>');
            }
        }
        $r->print('</tr>');
        $r->print('</table>');
    }
    $r->print('<br /><br /><br /><br /><br /><br /><br /><br /><br /><br />');
    return 'ok';
}

sub save_meta_data {
    my ($r) = @_;
    # first have to see if the tag already exists.
    my %fields;
    my $subject = $r->param('subject');
    $fields{'description'} = &fix_quotes($subject." Framework");
    $fields{'location'} = &fix_quotes($r->param('tagcell'));
    $fields{'contributor'} = $env{'user_id'};
    my $new_record_id = &save_record('tags', \%fields, 'id');
    undef %fields;
    $fields{'res_id'} = $r->param('resourceid');
    $fields{'tag_id'} = $new_record_id;
    &save_record('res_meta',\%fields);
    return 'ok';
}
sub toggle_res_framework {
    my ($r) = @_;
    # first have to see if the tag already exists.
    my %fields;
    my $subject = $r->param('subject');
    $fields{'res_id'} = &fix_quotes($r->param('resourceid'));
    $fields{'framework_code'} = &fix_quotes($r->param('framecode'));
    if (!&record_exist('res_framework',\%fields)) {
        &save_record('res_framework',\%fields);
    } else {
        &remove_res_framework($r);
    }
    return 'ok';
}
sub save_res_framework {
    my ($r) = @_;
    # first have to see if the tag already exists.
    my %fields;
    my $subject = $r->param('subject');
    $fields{'res_id'} = &fix_quotes($r->param('resourceid'));
    $fields{'framework_code'} = &fix_quotes($r->param('framecode'));
    if (!&record_exist('res_framework',\%fields)) {
        &save_record('res_framework',\%fields);
    } else {
    }
    return 'ok';
}
sub remove_res_framework {
    my ($r) = @_;
    my $resource_id = $r->param('resourceid');
    my $framework_code = &fix_quotes($r->param('framecode'));
    my $qry = "delete from res_framework where res_id = $resource_id and framework_code = $framework_code";
    $env{'dbh'}->do($qry);
    return 'ok';
}
sub get_base_url {
    my ($r) = @_;
    my $url = $r->self_url();
    if ($url=~/mentor\?/) {
        $url = 'mentor';
    } elsif ($url =~ /apprentice\?/) {
        $url = 'apprentice';
    } elsif ($url =~ /editor\?/) {
        $url = 'editor';
    } elsif ($url=~/home\?/) {
        $url = 'home';
    }
    return($url);
}

sub framework_grabber {
    my ($r, $subject, $level, $context, $expertise) = @_;
    my $tag;
    if ($env{'action'}) {
        $tag = $env{'action'};
    } else {
        $tag = $context;
    }
    my $resourceid = $r->param('resourceid');
    my $target = $r->param('target');
    # lots to do here!
    # @levels has to be a legit index of a framework element
    # assume to 0 element is highest of hierarchy if only one element
    # then only the top title is shown
    my $table = $subject.'_framework';
    my $bg_color_class;
    my $sql_regexp_sibs;
    my $sql_regexp_child;
    my @return_framework;
    my $url = &get_base_url($r);
    #have to build regexp in form ^level\\.level\\.[0-9]*$
    #first case is no periods in $level (which is the "parent cell")
    #in that case, we select the entire top level stuff
    my @levels = split /\./,$level;
    $sql_regexp_child = '^';
    $sql_regexp_sibs = '^';
    foreach my $sub_level (@levels) {
        $sql_regexp_child .= $sub_level.'\\.';
    }
    $sql_regexp_child .= '[0-9]*$';
    pop @levels; #this removes one of the levels, so we can retrieve the siblings
    foreach my $sub_level (@levels) {
        $sql_regexp_sibs .= $sub_level.'\\.';
    }
    $sql_regexp_sibs .= '[0-9]*$';
    
    my $qry = "select description, code from $table where code REGEXP '$sql_regexp_sibs'";
    #print "<br />$qry</br>";
    # my $dbh = &db_connect();
    my $sth;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<table>');
    while (my $framework_description = $sth->fetchrow_hashref) {
        if ($$framework_description{'code'} eq $level) {
            $bg_color_class = 'highlight';
        } else {
            $bg_color_class = 'lowlight';
        }
        $r->print('<tr class="'.$bg_color_class.'"><td>');
      
        if ($tag eq 'tag' || $tag eq 'expertise') {
            $r->print('<select name="level"><option>1</option><option>2</option><option>3</option></select>');
            $r->print('<input type="checkbox" name="tagcell" value="'.$$framework_description{'code'}.'" ');
            if (exists $$expertise{$subject.$$framework_description{'code'}}) {
                $r->print(' CHECKED');
            }
            $r->print(' />');
        } 
        $r->print('<span><a href="'.$url.'?token='.$env{'token'});
        $r->print(';action='.$tag.';resourceid='.$resourceid.';target='.$target);
        $r->print(';subject='.$subject.';code='.$$framework_description{'code'}.'">');   
        $r->print($$framework_description{'code'}."<br />".$$framework_description{'description'}); 
        $r->print('</a></span></td></tr>');
    }
    $r->print('</table>');
    return 'ok';
}
sub mentor_top_questions {
    my ($r) = @_;
    my $qry = "";
    my $mentor_id = $r->param('mentorid');
    my $sth;
    my $text;
    my $firstname;
    my $lastname;
    my $bio;
    $qry = "select t1.content, t2.content as question, firstname, lastname, bio from answers t1
        LEFT JOIN questions t2 on t1.question_id = t2.question_id 
        LEFT JOIN users t3 on t3.id = t1.user_id
        where t1.user_id = $mentor_id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<div id="interiorHeader">');
    $r->print('<h2>Mentor Top Responses</h2>');
    $r->print('<h3>Great ideas are just a click away...</h3>');
    $r->print('</div>');
    $r->print('<h4>Top Mentor Responses</h4>');
    $r->print('<div class="floatLeft">');
    $r->print('<div id="lookupScroller">');
    while (my $row = $sth->fetchrow_hashref()) {
        $firstname = $$row{'firstname'};
        $lastname = $$row{'lastname'};
        $bio = $$row{'bio'};
        $r->print('<strong>Question:</strong><br />');
        $text=$$row{'question'};
        $text=~ s/\n/<br \/>/g;
        $r->print('<p class="content">'.$text.'</p>');
        $r->print('<strong>Answer:</strong><br />');
        $text=$$row{'content'};
        $text=~ s/\n/<br \/>/g;
        $r->print('<p class="content">'.$text.'</p>');
    }
    $r->print('</div></div>');
    $r->print('<div class="floatLeft">');
    $r->print('<h4>About the Top Mentor</h4>');
    $r->print('<div id="lookupScroller">');
    $r->print('<strong>'.$firstname.' '.$lastname.'</strong>');
    $bio =~ s/\n/<br \/>/g;
    $r->print('<p class="content">'.$bio.'</p>');
    $r->print('</div>');
    $r->print('</div>');
    
    return 'ok';
}
sub save_email_pref {
    my ($type_id) = @_;
    my $user_id = $env{'user_id'};
    &delete_email_pref($type_id);
    my $qry = "insert into email_subs (user_id, type_id) values ($user_id, $type_id)";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    return 'ok';
}
sub delete_email_pref {
    my ($type_id) = @_;
    my $user_id = $env{'user_id'};
    my $qry = "delete from email_subs where user_id = $user_id and type_id = $type_id";
    $env{'dbh'}->do($qry);
    return 'ok';
}

sub get_email_preferences {
    my $qry;
    my $sth;
    my $user_id = $env{'user_id'};
    my $prefs;
    $qry = "select * from email_subs where user_id = $user_id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        $prefs .= $$row{'type_id'}.',';
    }
    $prefs =~ s/,$//;
    return $prefs;
}
sub set_email_preferences {
    my ($r) = @_;
    my $checked;
    my $msg;
    if ($env{'action'} eq 'saveemailpref') {
        if ($r->param('emailsub1')) {
            &save_email_pref('1');
        } else {
            &delete_email_pref('1');
        }
        
    }
    my $prefs = &get_email_preferences();
    my %fields=('target'=>'preferences',
                'menu'=>'preferences',
                'submenu'=>'email',
                'action'=>'saveemailpref');
    $r->print('Setting email preferences'."\n");
    $r->print('<form method="post" action="">'."\n");
    if ($prefs =~ m/1/) {
        $checked = " CHECKED ";
        $msg = "Un-check the box to no longer receive email updates of new discussion in your groups."."\n";
    } else {
        $checked = "";
        $msg = "Check the box to receive email notice of new discussions in any of your groups."."\n";
    }
    $r->print('<table><tr><td align="right">'.$msg.'</td>'."\n");
    $r->print('<td align="left"><input type="checkbox" name="emailsub1" value="true"'.$checked.' /></td></tr>'."\n");
    $r->print('</table>');
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" value="Update Email Preferences" />'."\n");
    $r->print('</form>'."\n");
    return 'ok';
}
sub user_preferences_menu {
    my ($r) = @_;
    my $url = $r->self_url();
    if ($url =~ /apprentice\?/) {
        $url = "aprentice?token=".$env{'token'}.";target=preferences";
    } else {
        $url = "home?token=".$env{'token'}.";target=preferences";
    }
    my $menu = $r->param('menu');
    print '<p >';
    if ($menu eq 'profile') {
        print '<span class="nav">[ <a href="'.$url.'&amp;menu=profile"><strong>Profile</strong></a> ]</span>';
    } else {
        print '<span class="nav">[ <a href="'.$url.'&amp;menu=profile">Profile</a> ]</span>';
    }
    # remove professional interest
#    if ($menu eq 'interests') {
#        print '<a href="'.$url.'&amp;menu=interests" ><strong style="content">[ Professional Interests ]</strong></a>';
#    } else {
#        print '<a href="'.$url.'&amp;menu=interests">[ Professional Interests ]</a>';
#    }
    if ($menu eq 'settings') {
        print '<span class="nav">[ <a href="'.$url.'&amp;menu=settings"><strong>Preferences</strong></a> ]</span>';
    } else {
        print '<span class="nav">[ <a href="'.$url.'&amp;menu=settings">Settings</a> ]</span>';
    }
    if ($menu eq 'email') {
        print '<span class="nav">[ <a href="'.$url.'&amp;menu=email"><strong>Email</strong></a> ]</span>';
    } else {
        print '<span class="nav">[ <a href="'.$url.'&amp;menu=email">Email</a> ]</span>';
    }
    
    print '</p>';    
    return 'ok';
}

sub framework_grabber_old {
    my ($r) = @_;
    # lots to do here!
    # @levels has to be a legit index of a framework element
    # assume to 0 element is highest of hierarchy if only one element
    # then only the top title is shown
    my @levels = $r->param('level');
    my $subject = $r->param('subject');
    my $table = $subject.'_framework';
    my $table_index = $table.'_index ';
    my $where_clause;
    my $num_levels = scalar @levels;
    for (my $i = 1; $i < $num_levels; $i++) {
        $where_clause .= 'level_val = '.$levels[($i-1)].' and ';
        $where_clause .= 'level = '.$i.' and ';
    }
    $where_clause .= 'level <> '.($num_levels + 1);
    my $qry = "select description from $table where id in (select id from $table_index where $where_clause)";
    print "<br />$qry</br>";
    # my $dbh = &db_connect();
    my $sth;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $framework_description = $sth->fetchrow_hashref) {
        print $$framework_description{'description'}."<br />";
    }
    return 'ok';
}

sub ohio_standard_grabber {
    my ($r) = @_;
    # lots to do here!
    # @levels has to be a legit index of a framework element
    # assume to 0 element is highest of hierarchy if only one element
    # then only the top title is shown
    my @levels = $r->param('level');
    my $subject = $r->param('subject');
    my $table = $subject.'_framework';
    my $table_index = $table.'_index ';
    my $where_clause;
    my $num_levels = scalar @levels;
    for (my $i = 1; $i < $num_levels; $i++) {
        $where_clause .= 'level_val = '.$levels[($i-1)].' and ';
        $where_clause .= 'level = '.$i.' and ';
    }
    $where_clause .= 'level <> '.($num_levels + 1);
    my $qry = "select description from $table where id in (select id from $table_index where $where_clause)";
    print "<br />$qry</br>";
    # my $dbh = &db_connect();
    my $sth;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $framework_description = $sth->fetchrow_hashref) {
        print $$framework_description{'description'}."<br />";
    }
    return 'ok';
}

sub send_message {
    my ($r, $draft) = @_;
    my %fields;
    my $message_id;
    if ($r->param('reply') eq 'true') {
        my $reply_id = $r->param('replyid');
        $fields{'reply'} = $reply_id;
    }
    if ($draft eq 'draft') {
        my %id;
        $id{'id'} = $r->param('messageid');
        if ($r->param('Submit') eq 'Save Message') {
            $fields{'is_sent'} = '0';
        } else {
            $fields{'is_sent'} = '1';
        }
        $fields{'recipient'} = $r->param('recipient');
        $fields{'subject'} = &fix_quotes($r->param('subject'));
        $fields{'content'} = &fix_quotes($r->param('content'));
        &update_record('comms',\%id,\%fields);
    } else {
        $fields{'date'} = ' now() ';
        if ($r->param('Submit') eq 'Save Message') {
            $fields{'is_sent'} = '0';
        } else {
            $fields{'is_sent'} = '1';
        }
        $fields{'is_read'} = '0';
        $fields{'sender_is_deleted'} = '0';
        $fields{'recipient_is_deleted'} = '0';
        $fields{'type'} =  '1';
        $fields{'sender'} = "$env{'user_id'}";
        $fields{'recipient'} = $r->param('recipient');
        $fields{'subject'} = &fix_quotes($r->param('subject'));
        $fields{'content'} = &fix_quotes($r->param('content'));
        &save_record('comms',\%fields);
    }    
    return 'ok';
}

sub send_question {
    my ($r, $draft) = @_;
    my %fields;
    my $message_id;
    if ($draft eq 'draft') {
        my %id;
        $id{'question_id'} = $r->param('messageid');
        if ($r->param('Submit') eq 'Save Question') {
            $fields{'is_sent'} = '0';
        } else {
            $fields{'is_sent'} = '1';
        }
        $fields{'subject'} = &fix_quotes($r->param('subject'));
        $fields{'content'} = &fix_quotes($r->param('content'));
        $fields{'standard'} = &fix_quotes($r->param('contentarea'));
        &update_record('questions',\%id,\%fields);
    } else {
        $fields{'date'} = ' now() ';
        if ($r->param('Submit') eq 'Save Question') {
            $fields{'is_sent'} = '0';
        } else {
            $fields{'is_sent'} = '1';
        }
        $fields{'is_read'} = '0';
        $fields{'user_id'} = $env{'user_id'};
        $fields{'subject'} = &fix_quotes($r->param('subject'));
        $fields{'content'} = &fix_quotes($r->param('content'));
        $fields{'standard'} = &fix_quotes($r->param('contentarea'));
        my $question_id = &save_record('questions',\%fields, 'id');
        my @framework_codes = $r->param('frameworkcode');
        foreach my $check (@framework_codes) {
            my $qry = "insert into question_framework (question_id, framework_id) values ($question_id, $check)";
            $env{'dbh'}->do($qry);
            
        }
    }    
    return 'ok';
}

sub send_answer {
    #$r->param('messageid') refers to the original question id number
    my ($r, $draft) = @_;
    my %fields;
    my $message_id;
    if ($draft eq 'draft') {
        my %id;
        $id{'id'} = $r->param('messageid');
        if ($r->param('Submit') eq 'Save Answer') {
            $fields{'is_sent'} = '0';
        } else {
            $fields{'is_sent'} = '1';
        }
        $fields{'content'} = &fix_quotes($r->param('content'));
        &update_record('answers',\%id,\%fields);
    } else {
        $fields{'date'} = ' now() ';
        if ($r->param('Submit') eq 'Save Answer') {
            $fields{'is_sent'} = '0';
        } else {
            $fields{'is_sent'} = '1';
        }
        $fields{'user_id'} = $env{'user_id'};
        $fields{'question_id'} = $r->param('messageid');
        $fields{'content'} = &fix_quotes($r->param('content'));
        &save_record('answers',\%fields);
    }    
    return 'ok';
}


sub mentor_question_alert {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    $qry = "select * from questions where is_read = 0";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    if ($sth->rows == 1) {
        print "<span>There is ".$sth->rows." unread question for mentors.</span>";
    } else {
        print "<span>There are ".$sth->rows." unread questions for mentors.</span>";
    }
    return 'ok';
}

sub apprentice_question_form {
my ($r) = @_;    
print qq~
      <table width="100%" border="0" cellspacing="0" cellpadding="10">
        <tr>
          <td align="left" valign="top"> 
            <p><span class="header">Associate Workspace</span><br />
              <span class="subheader">What do you want to learn today?</span></p>
            <p class="content">Please use the form below to ask a Mentor a question:</p>
            <form name="form1" method="post" action="apprentice-question">
              <table width="100%" border="0" cellpadding="0" cellspacing="0" bgcolor="#006634">
                <tr> 
                  <td align="center" valign="middle" bgcolor="#006634"><table width="100%" border="0" cellspacing="1" cellpadding="2">
                      <tr> 
                        <td colspan="2" class="header"><font color="#FFFFFF">Ask 
                          A Question</font></td>
                      </tr>
                      <tr bgcolor="#D9EAE4" class="content"> 
                        <td align="left" valign="top"><strong>Field</strong></td>
                        <td align="left" valign="top"><strong>Data</strong><strong></strong></td>
                      </tr>
                      <tr valign="middle" bgcolor="#EEEEEE" class="content">
                        <td align="left"><strong>Response Time (Days)</strong></td>
                        <td align="left"><select name="select" id="select">
                            <option value="1" selected>1</option>
                            <option value="2">2 </option>
                            <option value="3">3</option>
                            <option value="4">4</option>
                            <option value="5">5</option>
                            <option value="6">6</option>
                            <option value="7">7</option>
                            <option value="8">8</option>
                            <option value="9">9</option>
                            <option value="10">10</option>
                            <option value="11">11</option>
                            <option value="12">12</option>
                            <option value="13">13</option>
                            <option value="14">14</option>
                            <option value="15">15</option>
                            <option value="16">16</option>
                            <option value="17">17</option>
                            <option value="18">18</option>
                            <option value="19">19</option>
                            <option value="20">20</option>
                            <option value="21">21</option>
                          </select></td>
                      </tr>
                      <tr valign="middle" bgcolor="#EEEEEE" class="content"> 
                        <td align="left"><strong>Standard:</strong></td>
                        <td align="left"> <select name="standard" id="standard">
                            <option value="1">1.1.1.1</option>
                            <option value="2" selected>1.1.1.2</option>
                          </select> </td>
                      </tr>
                      <tr valign="middle" bgcolor="#FFFFFF" class="content"> 
                        <td align="left"><strong>Subject:</strong></td>
                        <td align="left"> <input name="subject" type="text" id="subject" value="" size="60"></td>
                      </tr>
                      <tr bgcolor="#EEEEEE" class="content"> 
                        <td align="left" valign="top"><strong>Question:</strong></td>
                        <td align="left" valign="top"><textarea name="question" cols="55" rows="10"></textarea></td>
                      </tr>
                      <tr align="center" valign="middle" bgcolor="#FFFFFF" class="content"> 
                        <td colspan="2"><input name="Submit" type="submit" id="Save Question" value="Save Question">
~;                        
print                        '<input type="hidden" name="token" value="'.$env{'token'}.'">';
print qq~
                          <input type="submit" name="Submit" value="Submit Question"> 
                          </td>
                      </tr>
                    </table></td>
                </tr>
              </table>
            </form>
            <p class="content"><span class="content"><br />
~;
print    '     &lt; <a href="apprentice?token='.$env{'token'}.'">Return to your Inbox</a> </span></p></td>';
print qq~        </tr>
      </table>
~;
}
sub get_location_record {
    my ($location_id) = @_;
    my %location_record;
    my $qry = "SELECT grade_range, nces_id, state_school_id, state_agency_id, district_id, school, 
                    address, city, zip, principal, elem, middle, high, phone 
               FROM locations
               WHERE location_id = $location_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $location_record = $sth->fetchrow_hashref();
    foreach my $key (keys %$location_record) {
        if(!defined $$location_record{$key}) {
            $$location_record{$key} = "";
        }
    } 
    return ($location_record);
}
sub get_district_record {
    my ($district_id) = @_;
    my %district_record;
    my $qry = "SELECT districts.partner_id, district_name, county, county_num, agency_type, students, 
                    free_lunch, reduced_lunch, partner_name
               FROM districts
               LEFT JOIN partners on partners.partner_id = districts.partner_id
               WHERE district_id = $district_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $district_record = $sth->fetchrow_hashref();
    foreach my $key (keys %$district_record) {
        if(!defined $$district_record{$key}) {
            $$district_record{$key} = "";
        }
    } 
    return ($district_record);
}
sub edit_districts {
    my ($r) = @_;
    if ($env{'action'} eq 'updatedistrict') {
        my %fields = ('partner_id' => $r->param('partnerid'),
                      'district_name'=>&fix_quotes($r->param('districtname')),
                      'county'=>&fix_quotes($r->param('county')),
                      'county_num'=>$r->param('countynum'),
                      'agency_type'=>$r->param('agencytypeid'),
                      'students'=>$r->param('students'),
                      'free_lunch'=>$r->param('freelunch'),
                      'reduced_lunch'=>$r->param('reducedlunch')
                      );
        my %id = ('district_id'=>$r->param('districtid'));
        &update_record('districts',\%id,\%fields);
    }
    my @districts = &Apache::Promse::get_districts();
    my $district = $districts[0];
    my @district_names = keys(%$district);
    my $district_id = $$district{$district_names[0]};
    my $district_record = &get_district_record($district_id);
    my $district_pulldown = &Apache::Promse::build_select('districtid',\@districts,"",' onchange="retrieveDistrictRecord()" ');
    my @partners = &Apache::Promse::get_partners();
    my $partner_id = $$district_record{'partner_id'};
    my $agency_type_id = $$district_record{'agency_type'};
    my $partners_pulldown = &Apache::Promse::build_select('partnerid',\@partners,$partner_id,'');
    my @agency_types = &Apache::Promse::get_agency_types();
    my $agency_types_pulldown = &Apache::Promse::build_select('agencytypeid',\@partners,$agency_type_id,'');
    
    my $javascript = qq ~
    <script type="text/javascript" >
        var token="$Apache::Promse::env{'token'}";
        var t=setTimeout("populateFormFirst()",200)
        populateFormFirst();
        function populateFormFirst() {
            try {
                districtid = document.getElementById("districtid").value;
                clearTimeout(t);
                retrieveDistrictRecord();
            } 
            catch (e) {
                return;
            }
        }
        function retrieveAgencyTypes(agencyid) {
            var xmlHttp;
            document.getElementById("statusMessage").innerHTML="Loading";
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
                    document.getElementById("agencytypespulldown").innerHTML=display; 
                    document.getElementById("statusMessage").innerHTML="&nbsp;";  
                    // timedMsg();     
                }
            }
            
            xmlHttp.open("GET","/promse/flash?token="+token+";action=getagencytypes;agencyid="+agencyid,true);
            xmlHttp.send(null);
        }        
        
        function retrievePartners(partnerid) {
            var xmlHttp;
            document.getElementById("statusMessage").innerHTML="Loading";
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
                    document.getElementById("partnerspulldown").innerHTML=display; 
                    document.getElementById("statusMessage").innerHTML="&nbsp;";  
                    // timedMsg();     
                }
            }
            
            xmlHttp.open("GET","/promse/flash?token="+token+";action=getpartners;partnerid="+partnerid,true);
            xmlHttp.send(null);
        }        
                
        function retrieveDistrictRecord() {
            var xmlHttp;
            document.getElementById("statusMessage").innerHTML="Loading";
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
                    var record_xml;
                    record_xml = xmlHttp.responseXML;
                    var partnerid=record_xml.getElementsByTagName("partner_id")[0].childNodes[0].nodeValue;
                    var districtname=record_xml.getElementsByTagName("district_name")[0].childNodes[0].nodeValue;
                    var county=record_xml.getElementsByTagName("county")[0].childNodes[0].nodeValue;
                    var countynum=record_xml.getElementsByTagName("county_num")[0].childNodes[0].nodeValue;
                    var agencytype=record_xml.getElementsByTagName("agency_type")[0].childNodes[0].nodeValue;
                    var students=record_xml.getElementsByTagName("students")[0].childNodes[0].nodeValue;
                    var freelunch=record_xml.getElementsByTagName("free_lunch")[0].childNodes[0].nodeValue;
                    var reducedlunch=record_xml.getElementsByTagName("reduced_lunch")[0].childNodes[0].nodeValue;
                    document.getElementById("partnerid").value=partnerid;
                    document.getElementById("districtname").value=districtname;
                    document.getElementById("county").value=county;
                    document.getElementById("countynum").value=countynum;
                    document.getElementById("students").value=students;
                    document.getElementById("freelunch").value=freelunch;
                    document.getElementById("reducedlunch").value=reducedlunch;
                    document.getElementById("statusMessage").innerHTML="&nbsp;";
                    retrievePartners(partnerid);
                    var districtid = document.getElementById("districtid").value;
                    retrieveAgencyTypes(agencytype);
                }
            }
            var districtid = document.getElementById("districtid").value;
            xmlHttp.open("GET","/promse/flash?action=getdistrictrecord;token="+token+";districtid="+districtid,true);
            xmlHttp.send(null);
        }        
        function timedMsg() {
            var t=setTimeout("ajaxFunction()",5000)
        }  
      
    </script>
    <img id="spacer" src="../images/spacer.gif" />
    ~;
    $r->print($javascript);
    
    my $output = qq~
    <div class="formContainer">
    <form method="post" action="">
    <div class="formRow">
    <span id="statusMessage">&nbsp;</span>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    District
    </div>
    <div class="fieldInput">
    $district_pulldown
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Partner
    </div>
    <div class="fieldInput">
    <span id="partnerspulldown">$partners_pulldown</span>
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    District Name
    </div>
    <div class="fieldInput">
    <input type="text" id="districtname" name="districtname" value="$$district_record{'district_name'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    County
    </div>
    <div class="fieldInput">   
    <input type="text" id="county" name="county" value="$$district_record{'county'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    County Number
    </div>
    <div class="fieldInput">
    <input type="text" id="countynum" name="countynum" value="$$district_record{'county_num'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Agency Type
    </div>
    <div class="fieldInput">
    <span id="agencytypespulldown">$agency_types_pulldown</span>
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Students
    </div>
    <div class="fieldInput">
    <input type="text" id="students" name="students" value="$$district_record{'students'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Free Lunch
    </div>
    <div class="fieldInput">
    <input type="text" id="freelunch" name="freelunch" value="$$district_record{'free_lunch'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Reduced Lunch
    </div>
    <div class="fieldInput">    
    <input type="text" id="reducedlunch" name="reducedlunch" value="$$district_record{'reduced_lunch'}" />
    </div>
    </div>
    ~;
    $r->print($output);
    my %fields = ('target'=>'editdistricts',
                  'action'=>'updatedistrict');
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" name="submit" value="Submit Changes" />');
    $r->print('</form>');
    $r->print('</div>');
    return 'ok'
    
}
sub edit_locations {
    my ($r) = @_;
    if ($env{'action'} eq 'updatelocation') {
        my ($elem, $middle, $high,$nces_id,$state_school_id,$state_agency_id);
        if ($r->param('elem')){$elem = 1}else{$elem = 0};
        if ($r->param('middle')){$middle = 1}else{$middle = 0};
        if ($r->param('high')){$high = 1}else{$high = 0};
        if (!$r->param('ncesid')){$nces_id = ' null '}
        if (!$r->param('stateschoolid')){$state_school_id = ' null '}
        if (!$r->param('stateagencyid')){$state_agency_id = ' null '}
        $r->print('Saving location');
        my %id = ('location_id'=>$r->param('locationid'));
        my %fields = ('grade_range'=>&fix_quotes($r->param('graderange')),
                      'nces_id'=>$nces_id,
                      'state_school_id'=>$state_school_id,
                      'state_agency_id'=>$state_agency_id,
                      'school'=>&fix_quotes($r->param('school')),
                      'address'=>&fix_quotes($r->param('address')),
                      'city'=>&fix_quotes($r->param('city')),
                      'zip'=>&fix_quotes($r->param('zip')),
                      'phone'=>&fix_quotes($r->param('phone')),
                      'principal'=>&fix_quotes($r->param('principal')),
                      'elem'=>$elem,
                      'middle'=>$middle,
                      'high'=>$high);
        &update_record('locations',\%id,\%fields);
    }
    my @districts = &Apache::Promse::get_districts();
    my $district = $districts[0];
    my @schools = (keys(%$district));
    my $district_id = $$district{$schools[0]};
    @schools = &Apache::Promse::get_schools($district_id);
    my $schools_pulldown = &Apache::Promse::build_select('locationid',\@schools,"",' onchange="retrieveLocationRecord()" ');
    my $school = $schools[0];
    my @key = keys(%$school);
    my $location_id = $$school{$key[0]};
    my $selected = "";
    my $javascript ='onchange="retrieveSchools()"';
    my $district_pulldown = &Apache::Promse::build_select('districtid',\@districts,$selected,$javascript);
    $location_id = $r->param('locationid');
    my ($location_record) = &get_location_record($location_id);
    my $elem_checked = "";
    my $middle_checked = "";
    my $high_checked = "";
    if ($$location_record{'elem'}) {
        $elem_checked = ' checked="checked" ';
    } 
    if ($$location_record{'middle'}) {
        $middle_checked = ' checked="checked" ';
    } 
    if ($$location_record{'high'}) {
        $high_checked = ' checked="checked" ';
    } 

    $javascript = qq ~
    <script type="text/javascript" >
        var token="$Apache::Promse::env{'token'}";
        populateFormFirst();
        var locationid;
        function populateFormFirst() {
            try {
                locationid = document.getElementById("locationid").value;
                clearTimeout(t);
                retrieveLocationRecord();
            } 
            catch (e) {
                return;
            }
        }
        var t=setTimeout("populateFormFirst()",200)
        function retrieveSchools() {
            var xmlHttp;
            document.getElementById("statusMessage").innerHTML="Loading";
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
                    retrieveLocationRecord();
                    document.getElementById("statusMessage").innerHTML="&nbsp;";  
                    // timedMsg();     
                }
            }
            var districtid = document.getElementById("districtid").value;
            xmlHttp.open("GET","/promse/flash?token="+token+";action=getdistrictschools;districtid="+districtid,true);
            xmlHttp.send(null);
        }        
                
        function retrieveLocationRecord() {
            var xmlHttp;
            document.getElementById("statusMessage").innerHTML="Loading";
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
                    var record_xml;
                    record_xml = xmlHttp.responseXML;
                    var school=record_xml.getElementsByTagName("school")[0].childNodes[0].nodeValue;
                    var grade_range=record_xml.getElementsByTagName("grade_range")[0].childNodes[0].nodeValue;
                    var nces_id=record_xml.getElementsByTagName("nces_id")[0].childNodes[0].nodeValue;
                    var state_school_id=record_xml.getElementsByTagName("state_school_id")[0].childNodes[0].nodeValue;
                    var state_agency_id=record_xml.getElementsByTagName("state_agency_id")[0].childNodes[0].nodeValue;
                    var address=record_xml.getElementsByTagName("address")[0].childNodes[0].nodeValue;
                    var city=record_xml.getElementsByTagName("city")[0].childNodes[0].nodeValue;
                    var zip=record_xml.getElementsByTagName("zip")[0].childNodes[0].nodeValue;
                    var principal=record_xml.getElementsByTagName("principal")[0].childNodes[0].nodeValue;
                    var phone=record_xml.getElementsByTagName("phone")[0].childNodes[0].nodeValue;
                    var elem=record_xml.getElementsByTagName("elem")[0].childNodes[0].nodeValue;
                    var middle=record_xml.getElementsByTagName("middle")[0].childNodes[0].nodeValue;
                    var high=record_xml.getElementsByTagName("high")[0].childNodes[0].nodeValue;
                    document.getElementById("school").value=school;
                    document.getElementById("graderange").value=grade_range;
                    document.getElementById("ncesid").value=nces_id;
                    document.getElementById("stateschoolid").value=state_school_id;
                    document.getElementById("stateagencyid").value=state_agency_id;
                    document.getElementById("address").value=address;
                    document.getElementById("city").value=city;
                    document.getElementById("zip").value=zip;
                    document.getElementById("principal").value=principal;
                    document.getElementById("phone").value=phone;
                    if (elem == 1) {
                        document.getElementById("elem").checked=true;
                    } else {
                        document.getElementById("elem").checked=false;
                    }  
                    if (middle == 1) {
                        document.getElementById("middle").checked=true;
                    } else {
                        document.getElementById("middle").checked=false;
                    }  
                    if (high == 1) {
                        document.getElementById("high").checked=true;
                    } else {
                        document.getElementById("high").checked=false;
                    } 
                    document.getElementById("statusMessage").innerHTML="&nbsp;"; 
                }
            }
            var locationid = document.getElementById("locationid").value;
            xmlHttp.open("GET","/promse/flash?action=getlocationrecord;token="+token+";locationid="+locationid,true);
            xmlHttp.send(null);
        }        
        function timedMsg() {
            var t=setTimeout("ajaxFunction()",5000)
        }  
      
    </script>
    <img id="spacer" src="../images/spacer.gif" />
    ~;
    $r->print($javascript);
    # <img src="../images/spacer.gif" onload="retrieveLocationRecord()" />

    my $output = qq~
    <div class="formContainer">
    <form method="post" action="">
    <div class="formRow">
    <span id="statusMessage">&nbsp;</span>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    District
    </div>
    <div class="fieldInput">
    $district_pulldown
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    School
    </div>
    <div class="fieldInput">
    <span id="schoolselectspan" >$schools_pulldown</span>
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Grade Range
    </div>
    <div class="fieldInput">
    <input type="text" id="graderange" name="graderange" value="$$location_record{'grade_range'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    NCES-ID
    </div>
    <div class="fieldInput">
    <input type="text" id="ncesid" name="ncesid" value="$$location_record{'nces_id'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    State School ID
    </div>
    <div class="fieldInput">   
    <input type="text" id="stateschoolid" name="stateschoolid" value="$$location_record{'state_school_id'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    State Agency ID
    </div>
    <div class="fieldInput">
    <input type="text" id="stateagencyid" name="stateagencyid" value="$$location_record{'state_agency_id'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    School
    </div>
    <div class="fieldInput">
    <input type="text" id="school" name="school" value="$$location_record{'school'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Address
    </div>
    <div class="fieldInput">
    <input type="text" id="address" name="address" value="$$location_record{'address'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    City
    </div>
    <div class="fieldInput">
    <input type="text" id="city" name="city" value="$$location_record{'city'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Zip
    </div>
    <div class="fieldInput">    
    <input type="text" id="zip" name="zip" value="$$location_record{'zip'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Principal
    </div>
    <div class="fieldInput">
    <input type="text" id="principal" name="principal" value="$$location_record{'principal'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Phone
    </div>
    <div class="fieldInput">
    <input type="text" id="phone" name="phone" value="$$location_record{'phone'}" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Elementary
    </div>
    <div class="fieldInput">
    <input type="checkbox" id="elem" name="elem"  checked="" />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    Middle
    </div>
    <div class="fieldInput">
    <input type="checkbox" id="middle" name="middle" $middle_checked />
    </div>
    </div>
    <div class="formRow">
    <div class="fieldTitle">
    High
    </div>
    <div class="fieldInput">
    <input type="checkbox" id="high" name="high"  $high_checked />
    </div>
    </div>
    ~;
    $r->print($output);
    my %fields = ('target'=>'editlocations',
                  'action'=>'updatelocation');
    $r->print(&hidden_fields(\%fields));
    $r->print('<input type="submit" name="submit" value="Submit Changes" />');
    $r->print('</form>');
    $r->print('</div>');
    return 'ok'
}
sub compose_message_form {
    my ($r) = @_;    
    my $message_id = $r->param('messageid');
    my $reply_id;
    my $destination_menu;
    my $sender;
    my $recipient;
    my $subject;
    my $content;
    my $selected;
    my $message_hashref;
    my $action = $env{'action'};
    $destination_menu = 'outbox';
    if ($r->param('menu') eq 'drafts') {
        print "<h4>Editing a draft</h4>";
        $message_hashref = &retrieve_message($r->param('messageid'));
        $subject = $$message_hashref{'subject'};
        $content = $$message_hashref{'content'};
        $recipient = $$message_hashref{'recipient'};
        $destination_menu = 'drafts';
    }
    my $url = "home";
    print '<h4>Compose A Message</h4>'."\n";          
    print '<form name="form1" method="post" action="'.$url.'">';
    print '<fieldset><label>To:</label><br />'."\n";
    my $address_book_hashref = &get_address_book($r);
    if ($action eq 'Reply') {
        $message_hashref = &retrieve_message($message_id);
        $subject = $$message_hashref{'subject'};
        $subject = 'Re: '.$subject;
        $content = $$message_hashref{'content'};
        $recipient = $$message_hashref{'sender'};
        $sender = $$message_hashref{'recipient'};
        $reply_id = $message_id;
        print &userid_to_display_name($recipient);
    } else {
        print '<select name="recipient">'."\n";
        foreach my $row (sort keys %$address_book_hashref) {
            if ($$address_book_hashref{$row}{'id'} eq $recipient) {
                $selected = "selected";
            } else {
                $selected = "";
            }
            print '<option '.$selected.' value="'.$$address_book_hashref{$row}{'id'}.'">'.$$address_book_hashref{$row}{'lastname'}.'</option>'."\n";
        }
        print '</select>'."\n";
    }
    print '<div><label>Subject:</label>'."\n";
    print '<input name="subject" type="text" id="subject" value="'.$subject.'" size="60" /></div>'."\n";
    $r->print('<div><label>Message:</label></div>'."\n");
    $r->print('<div><textarea name="content" cols="55" rows="10">'.$content.'</textarea></div>'."\n");
    $r->print('</fieldset>'."\n");
    print '<input class="buttonGroup" name="Submit" type="submit" id="Save Message" value="Save Message" />'."\n";
    print '<input type="hidden" name="token" value="'.$env{'token'}.'" />'."\n";
    if ($action eq 'Reply') {
        print '<input type="hidden" name="reply" value="true" />'."\n";
    }
    print '<input type="hidden" name="messageid" value="'.$message_id.'" />'."\n";
    print '<input type="hidden" name="replyid" value="'.$reply_id.'">';
    print '<input type="hidden" name="recipient" value="'.$recipient.'" />'."\n";
    print '<input type="hidden" name="target" value="message" />'."\n";
    print '<input type="hidden" name="menu" value="'.$destination_menu.'" />'."\n";
    print '<input type="hidden" name="action" value="send" />'."\n";
    print '<input type="submit" name="Submit" value="Submit Message" />'."\n";
    $r->print('</form>');
    return 'ok';
}
sub question_progress {
    my ($r) = @_;
    $r->print('<strong>Subject Area: </strong>'.$r->param('contentarea').'<br />');
    $r->print('<strong>Question Summary: </strong>'.$r->param('subject').'<br />');
    $r->print('<strong>Question: </strong>'.$r->param('content').'<br />');
    return 'ok';
}

sub compose_question_form {
    my ($r) = @_;    
    my $message_id = $r->param('messageid');
    my %hidden_fields;
    my $subject;
    my $content;
    my $content_area;
    my $action = $env{'action'};
    my $step = $r->param('step');
    $r->print('<div id="composeQuestion" align =left>');
    $r->print('<form name="form1" method="post" action="apprentice">');
    $r->print('<fieldset>');
    $r->print('<legend>Subject area </legend><label><input type="radio" name="contentarea" value="math" />');
    $r->print('Math </label><label> <input type="radio" name="contentarea" value="science" /> Science</label>');
    $r->print('<p></p>');
    $r->print('<label>Title');
    $r->print('<input type="text" maxlength="150" size="30" name="subject" /></label><br />');
    $r->print('<label>Write your question below. ');
    $r->print('<textarea name="content" rows="10" cols="80" /></textarea></label><br />');
    $r->print('</fieldset>');
    #$r->print('<br />Select the areas of the '.$r->param('contentarea').'framework that this question involves.<br />');
    #$r->print('<div id="frameworkSelector" align = "right">');
    # call to framework_selector temporarily disabled
    # &framework_selector($r, 'math');
    #$r->print('</div><br />');
    $content =~ s/"/&quot;/g;
    $hidden_fields{'action'} = 'send';
    $hidden_fields{'menu'} = 'questions';
    $hidden_fields{'submenu'} = 'questions';
    $r->print(&hidden_fields(\%hidden_fields));
    $r->print('<br />');
    $r->print('<center><input type="Submit" name="Submit" value="Send Question!"></center>');
    $r->print('</div>');
    $r->print('</form>');
    return 'ok';
}

sub lesson_lab_page {
    my ($r) = @_;
    $r->print('<div id="interiorHeader">');
    $r->print('<h2>Welcome to the PROM/SE LessonLab page</h2>');
  #	$r->print('<h3>Don'."'".'t Panic! You are not alone...</h3>');
    $r->print('</div>');
    
  #	$r->print('<a href="http://zuma.lessonlab.com:8080/remoteUserService/visibilityProxy?userName='.$env{'username'}.'&customerId=MISU001&destination=new3.lessonlab.com/llport.nsf?OpenDatabase%26login">Click Here</a>Once you have registered for your classes.');
		$r->print('<a href="http://zuma.lessonlab.com:8080/visibilityProxy?userName='.$env{'username'}.'&customerId=MISU001&destination=new3.lessonlab.com/llport.nsf?OpenDatabase%26login"><h6 align="right">Access LessonLab courses</h6></a><br />');
	# just a try	$r->print('<a href="http://zuma.lessonlab.com:8080/portal/main.do?userName='.$env{'username'}.'&password=password"><h4 align="right">Access LessonLab courses</h4></a><br />');
	  $r->print('<div>');
    $r->print('<div>');
    $r->print('To register for a course, navigate to the following URL:');
    $r->print('</div>');
    $r->print('<div>');
    $r->print('<a href="http://orders.lessonlab.com/msu.htm">Order lesson from LessonLab</a>');
    $r->print('</div><br />');    
    $r->print('Registering for a Break Through Math Course');
    $r->print('</div>');
    $r->print('<div>');
  #	$r->print('COURSE DEADLINES: ');    
    $r->print('</div>');
    $r->print('<table><tr><td colspan="3">COURSE DEADLINES: </td></tr>');
    $r->print('<tr><td>REGISTRATION DEADLINE</td><td>COURSE START DATE</td><td>COURSE COMPLETION DATE</td></tr>');
    $r->print('<tr><td>November 7, 2005</td><td>November 15, 2005</td><td>December 23, 2005</td></tr>');
    $r->print('<tr><td>December 28, 2005 </td><td>January 5, 2006</td><td>February 15, 2006</td></tr>');
    $r->print('<tr><td>February 10, 2006</td><td>February 15, 2006</td><td>March 30, 2006</td></tr>');
    $r->print('<tr><td>March 25, 2006</td><td>March 30, 2006</td><td>May 5, 2006</td></tr>');
    $r->print('<tr><td>April 25, 2006</td><td>May 5, 2006</td><td>June 15, 2006</td></tr>');
    $r->print('</table>');                 

    $r->print('<div>');
    $r->print('At this registration website, you will be able to select the course you wish to participate in and will also be asked to supply a mailing address (you must supply a street address, not a P.O. Box) and phone number so that LessonLab can ship you the course materials you will need before the online course begins.');
    $r->print('</div>');
    $r->print('<div>');
    $r->print('Please note: The course selections will not be available on the website after the registration deadline, so you must register by the registration deadline in order to take the course.');
    $r->print('</div>');
    $r->print('</frameset>');
    return;
}

sub compose_answer_form {
    my ($r) = @_;    
    my $message_id = $r->param('messageid');
    my $reply_id;
    my $destination_menu;
    my $sender;
    my $recipient;
    my $subject;
    my $content;
    my $selected;
    my $message_hashref;
    my $action = $env{'action'};
    $destination_menu = 'outbox';
    if ($r->param('menu') eq 'drafts') {
        print "<span>Editing a draft</span>";
        $message_hashref = &retrieve_message($r->param('messageid'));
        $subject = $$message_hashref{'subject'};
        $content = $$message_hashref{'content'};
        $recipient = $$message_hashref{'recipient'};
        $destination_menu = 'drafts';
    }
    my $url = "mentor";    
    $r->print('<div id="composeAnswer">');  
    print '<form name="form1" method="post" action="'.$url.'">';
    $r->print('<fieldset>');
    print '<label>Compose Answer:<textarea name="content" cols="55" rows="10">'.$content.'</textarea></p>';
    print '</fieldset>';
    print '<p><input name="Submit" type="submit" id="Save Answer" value="Save Answer">';
    print '<input type="hidden" name="token" value="'.$env{'token'}.'">';
    if ($action eq 'Reply') {
        print '<input type="hidden" name="reply" value="true">';
    }
    print '<input type="hidden" name="messageid" value="'.$message_id.'">';
    print '<input type="hidden" name="replyid" value="'.$reply_id.'">';
    print '<input type="hidden" name="target" value="questions">';
    print '<input type="hidden" name="menu" value="'.$destination_menu.'">';
    print '<input type="hidden" name="action" value="send">';
    print '<input type="submit" name="Submit" value="Submit Answer"></form></p>';
    print '</div>';
#    $r->print('</td></tr></table>');
}

sub add_address_book {
    my ($r) = @_;
    my @add_users = $r->param('adduser');
    # my $dbh = &db_connect();
    my $qry;
    foreach my $recipient_id (@add_users) {
        $qry = "insert into address_book (user_id, recipient_id) values (".$env{'user_id'}.", $recipient_id)";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
    }
    return 'ok';
}
sub delete_address_book {
    my ($r) = @_;
    my @del_users = $r->param('deluser');
    # my $dbh = &db_connect();
    my $qry;
    my $where_clause;
    foreach my $recipient_id (@del_users) {
        $where_clause .= " recipient_id = $recipient_id or";
    }
    $where_clause =~ m/(.*)(or$)/;
    $qry = "delete from address_book where user_id = ".$env{'user_id'}." and (".$1.")";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    return 'ok';
}
sub get_address_book {
    my ($r) = @_;
    my %address_book_hash;
    my $qry = "select id, lastname, firstname from users, address_book where user_id = ".$env{'user_id'}." and id = recipient_id order by lastname, firstname";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
       $address_book_hash{$$row{'lastname'}.$$row{'firstname'}.$$row{'id'}}={%$row};
    }
    return \%address_book_hash;
}
sub address_book {
    my ($r) = @_;
    # start by showing all users, will need to filter later (soon, I hope!)
    my $qry = "select id, lastname, firstname from users where id <> ALL ";
    $qry.= "(select recipient_id from address_book where user_id = ".$env{'user_id'}." ) order by lastname, firstname";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<h4>Address Book</h4>'."\n");
    $r->print('<div class="floatLeft">'."\n");
    $r->print('<div id="addressScroller">'."\n");
    $r->print('<table><caption>All Users</caption>'."\n");
    $r->print('<thead><tr><th scope="col">Select</th>'."\n");
    $r->print('<th scope="col">Name to Add</th>'."\n");
    $r->print('</tr>'."\n");
    $r->print('</thead>'."\n");
    $r->print('<tbody>'."\n");
    while (my $row = $sth->fetchrow_hashref) {
        print '<tr><td scope="row"><a href="home?token='.$env{'token'}.'&menu=address&action=addname&target=message&adduser='.$$row{'id'}.'">Add</a></td>';
        print '<td>'.$$row{'firstname'}." ".$$row{'lastname'}."</td></tr>";
    }
    $r->print('<tr class="bottomRow"><td colspan="2"></td></tr>'."\n");
    $r->print('</tbody></table>'."\n");
    $r->print('</div></div>'."\n");
    $qry = "select id, lastname, firstname from users, address_book where user_id = ".$env{'user_id'}." and id = recipient_id order by lastname, firstname";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $r->print('<div class="floatLeft">');
    $r->print('<div id="addressScroller">'."\n");
    $r->print('<table><caption>My Address Book</caption>'."\n");
    $r->print('<thead><tr><th scope="col">Select</th>'."\n");
    $r->print('<th scope="col">Name to Remove</th>'."\n");
    $r->print('</tr>'."\n");
    $r->print('</thead>'."\n");
    $r->print('<tbody>'."\n");
    if ($sth->rows) {
        
        while (my $row = $sth->fetchrow_hashref) {
            print '<tr><td scope="row"><a href="home?token='.$env{'token'}.'&menu=address&action=delname&target=message&deluser='.$$row{'id'}.'">Delete</a></td>';
            print '<td>'.$$row{'firstname'}." ".$$row{'lastname'}."</td></tr>";
        }
       
        
    } else {
        print "<span>There are no names in your address book</span>";
    }
    $r->print('<tr class="bottomRow"><td colspan="2"></td></tr>'."\n");
    $r->print('</tbody></table>'."\n");
    $r->print('</div></div>'."\n");
    $r->print('<div class="clear"></div>');
    return ;
}

sub admin_form {
    my ($r) = @_;
    my $offset;
    my $records = 150;
    my $where_clause;
    my $previous_offset;
    my $next_offset;
    my $start_letter;
    my $token = $env{'token'};
    if ($r->param('offset')) {
        $offset = $r->param('offset');
        $next_offset = $offset + $records;
        $previous_offset = $offset - $records;
        if ($previous_offset < 0) {$previous_offset = 0;}
    } else {
        $offset = 0;
        $next_offset = $records;
        $previous_offset = 0;
    }
    if ($r->param('letter')) {
        $start_letter = $r->param('letter');
        $where_clause = " where lastname >= '".$r->param('letter')."' ";
        
    } else {
        $start_letter = 'A';
        $where_clause = " where lastname >= 'A' ";
    }
    my $jscript = qq~
    <script type="text/javascript">
    <!--
    t=setTimeout("dummy()",1);
    var filterString = "";
    function dummy() {
    }
    function filterTimer(str) {
        filterString = str;
        clearTimeout(t);
        var t=setTimeout("filterName(filterString)",500);
    }
    function filterName(str) {
        var xmlHttp;
        document.getElementById("statusMessage").innerHTML="Filtering . . .";
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
                var display = "";
                xmlHttp.responseText;
                display = xmlHttp.responseText;
                document.getElementById("namelist").innerHTML=display; 
                document.getElementById("statusMessage").innerHTML="&nbsp;";  
                // timedMsg();     
            }
        }
        filter = str;
        records = "$records";
        token = "$token";
        xmlHttp.open("GET","/promse/flash?token="+token+";action=getfilterednames;filter="+filter+";records="+records,true);
        xmlHttp.send(null);
    }
    function confirmDelete()
    {
        var agree=confirm("Are you sure you wish to delete this user?");
        if (agree)
        return true ;
        else
        return false ;
    }
    // -->
    </script>
    ~;
    $r->print($jscript);
    my @alpha = qw(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z);
    my $light_color = ' class="adminFormRow" ';
    my $dark_color = ' class="adminFormRowAlternate" ';
    my $row_color = $light_color;
    foreach my $letter(@alpha) {
        $r->print('<span>[<a class="alphaMenu" href="admin?token='.$env{'token'}.'&amp;menu=users&amp;submenu=roles&amp;letter='.$letter.'">'.$letter.'</a>]</span>');
    }
    $r->print('<br /><span>[ <a href="admin?token='.$env{'token'}.'&amp;menu=users&amp;submenu=roles&amp;letter='.$start_letter.'&amp;offset='.$previous_offset.'">Previous Page</a> ]</span>');
    $r->print('<span>[ <a href="admin?token='.$env{'token'}.'&amp;menu=users&amp;submenu=roles&amp;letter='.$start_letter.'&amp;offset='.$next_offset.'">Next Page</a> ]</span>');
    $r->print('<div>Filter By Last Name<input type="text" id="namefilter" name="namefilter" onkeyup="filterTimer(this.value)"/><span id="statusMessage">&nbsp;</span></div>');
    my $qry = "select users.id, lastname, firstname, active, ";
    $qry .= "(select group_concat(roles.role) from userroles, roles where userroles.user_id  = users.id and roles.id = userroles.role_id) as roles from users ";
    $qry .= $where_clause." order by lastname, firstname LIMIT $offset, $records";
    my $sth = $env{'dbh'}->prepare($qry) or &logthis($Mysql::db_errstr);
    $sth->execute();
	my @roles = &get_roles();
	
    $r->print('<div class="adminFormContainer">');
    $r->print('<div class="adminFormHeader" style="width:100%">'."\n");    
    $r->print('<div class="adminFormColHeadName">Name (Edit User)</div>');
	foreach my $role(@roles) {
    	$r->print('<div class="adminFormColHead">' . $$role{'short_name'} . '</div>');
	}
    $r->print('<div class="adminFormColHeadButton">Update</div>');
    $r->print('<div class="adminFormColHeadButton">Delete</div>');
    $r->print('</div>'."\n"); # end the adminFormHeader
    $r->print('<div class="adminFormScroller" style="width:100%" id="namelist">');
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
			$r->print(&make_admin_form_checkbox($role));
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
                      'letter'=>$start_letter
                     );
        $r->print(&hidden_fields(\%fields));
        $r->print('</form>');
    }
    $r->print('</div>'."\n"); # end adminFormScroller
    $r->print('</div>'."\n"); # end adminFormContainer
}
sub make_admin_form_checkbox {
	my($role) = @_;
	my $row = '<div class="adminFormColHead">';
	$row .= '<input class="adminFormCheck" name="role" type="checkbox" value="' . $$role{'role'} . '" ' . $$role{'checked'} . ' />';
    $row .= '</div>'."\n";
	return ($row);
}
sub log_visit {
    my ($r) = @_;
    my $resource_id;
    my %fields;
    if (!$env{'user_id'}) {
       $env{'user_id'} = '0'; 
    }
    $fields{'user_id'} = $env{'user_id'};
    $fields{'date'} = ' now() ';
    $fields{'resource_id'} = &fix_quotes($r->self_url());
    &save_record ('activity_log', \%fields);
    return 'ok';
}

sub reset_password {
    my ($r) = @_;
    my $target_user_id = $r->param('userid');
    if ($r->param('stage') eq 'two') {
        $r->print('resetting password');
        my %id;
        my %fields;
        $id{'id'}=$target_user_id;
        $fields{'password'}= " 'password' ";
        &update_record('users', \%id, \%fields);
    } else {
        $r->print('Are you sure you want to reset the password?');
    }
    
    return 'ok';
}
sub set_environment {
    my ($r) = @_;
    return 'ok';
}
sub validate_user {
    # validates user and sets environment variables
    # user_id, username, token, target, action, 
    # menu, submenu, group_id, group_count, course_id,
    # thread_id resource_id etc.   
    # also updates activity_log table and users_on
    my ($r) = @_;
    %env = ();
    my $qry;
    my $sth;
    my @row_ary;
    my $row_hashref;
    my $response;
    if ($r->param('POSTDATA')) {
        # handles calls from Angularjs stuff
        # POSTDATA contains JSON string
        my $coder = JSON::XS::->new;
        $env{'POSTDATA'} = $coder->decode($r->param('POSTDATA'));
        $env{'action'} = $env{'POSTDATA'}{'action'};
        my @field_names = keys(%{$env{'POSTDATA'}});
        foreach my $field_name (@field_names) {
            $env{$field_name} = $env{'POSTDATA'}{$field_name};
        }
        $env{'password'} = $env{'password'}?$env{'password'}:'undefined';
 
    } else {
        $env{'action'} = $r->param('action')?$r->param('action'):'undefined';
        $env{'password'} = $r->param('password')?$r->param('password'):'undefined';
        $env{'token'} = $r->param('token')?$r->param('token'):'undefined';
        $env{'username'} = $r->param('username')?$r->param('username'):'undefined';
    }
    $env{'help_topic'} = 'none';
    $env{'dbh'} = &db_connect();
    $env{'target'} = $r->param('target')?$r->param('target'):'undefined';
    $env{'submenu'} = $r->param('submenu')?$r->param('submenu'):'undefined';
    if ($env{'target'} eq 'preferences') {
        $env{'help_topic'} = 'preferences';
    }
    &purge_idle_users();
    $qry = "select demo_mode from config limit 1";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    $row_hashref = $sth->fetchrow_hashref();
    $env{'demo_mode'} = $$row_hashref{'demo_mode'};
    $env{'thread_id'} = $r->param('threadid')?$r->param('threadid'):'undefined';
    $env{'course_id'} = $r->param('courseid')?$r->param('courseid'):'undefined';
    $env{'resource_id'} = $r->param('resourseid')?$r->param('resourseid'):'undefined';
    $env{'curriculum_id'} = $r->param('curriculumid')?$r->param('curriculumid'):'undefined';
    if (($env{'token'} ne 'undefined' && $env{'password'} eq 'undefined' )) {
        print STDERR "token present, password absent \n";
        $env{'token'} = $r->param('token')?$r->param('token'):$env{'POSTDATA'}{'token'};
        # assumption is we're maintaining a connection
        $qry = "SELECT user_id, token, login, last_act, logout 
                FROM log 
                WHERE token = '".$env{'token'}."'";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute;
        if ($row_hashref = $sth->fetchrow_hashref) {
            # for now, simply finding the token is sufficient
            # later we'll check how old it is
            $env{'user_id'} = $$row_hashref{'user_id'};
            $env{'username'} = &token_to_username($env{'token'});
            $env{'user_roles'} = &get_user_roles;
            
            # update the log table with current time
            $qry = "update log set last_act = now() where token = '".$env{'token'}."'";
            $sth = $env{'dbh'}->prepare($qry);
            $sth->execute;
            $qry = "FLUSH TABLE log";
            $env{'dbh'}->do($qry);
        } else {
            $env{'user_id'} = 0;
        }
        my $profile = &get_user_profile(0); # 0 asks for logged in user's profile
        $env{'photo'} = $$profile{'photo'};
        $env{'subject'} = $$profile{'subject'};
        $env{'refresh'} = $r->param('refresh')?$r->param('refresh'):'refresh';
        $env{'menu'} = $r->param('menu')?$r->param('menu'):'undefined';
        $env{'submenu'} = $r->param('submenu')?$r->param('submenu'):'undefined';
		$env{'display_name'} = $$profile{'firstname'} . ' ' . $$profile{'lastname'};
        if ($r->param('groupid')) {
            $env{'group_id'} = $r->param('groupid');
            my $group_ids = &get_user_groups($env{'user_id'});
            my $found_one;
            foreach my $key(keys(%$group_ids)) {
                $found_one++;
            }
            if (!$found_one) {
                $env{'group_count'} = 0;
            } elsif ($found_one gt 1) {
                $env{'group_count'} = $found_one - 1;
            }
        } else {
           # need to assign group_id if user belongs to only one group
            # let's assign a group if you are a member of only one group
            my $group_ids = &get_user_groups($env{'user_id'});
            my $found_one = 0;
            my $group_id;   
            foreach my $key(keys(%$group_ids)) {
                $found_one++;
            }
            if (!$found_one) {
                $env{'group_id'} = 'none';
            } elsif ($found_one eq 2) {
                # here if there is only one group
                # select the group
                delete($$group_ids{'exists'});
                $env{'group_count'} = $found_one - 1;
                foreach my $key (keys %$group_ids) { # only one key
                    $group_id = $$group_ids{$key};
                    $env{'group_id'} = $group_id;
                }
            } else {
                $env{'group_count'} = $found_one - 1;
                # more than one group found, have user select
                delete($$group_ids{'exists'});
                $env{'group_id'} = 'undefined';
            }
        }
        # set the environment variables
    } elsif ($env{'password'} ne 'undefined') {
        print STDERR "password is not undefined \n";
        print STDERR $env{'password'} . " is password \n";
        print STDERR $env{'username'} . " is user name \n";
        if ($env{'password'} eq 'password') {
            $response .= 'password';
        }
		if (length($env{'password'}) eq 32) {
        	$qry = "select Firstname, Lastname, username, id, subject, password from users where username = ? and password = ? AND active = 1";
			
		} else {
        	$qry = "select Firstname, Lastname, username, id, subject, password from users where username = ? and password = md5(?) AND active = 1";
		}
        $sth = $env{'dbh'}->prepare($qry);  
        $sth->execute($env{'username'},$env{'password'});
        if ($sth->rows) {
            print STDERR "found user in validate \n";
            # grab the info from the users table and save it
            $row_hashref = $sth->fetchrow_hashref;
            if (!$$row_hashref{'subject'}) {
                $response .= 'subject';
            }
            $env{'username'} = $$row_hashref{'username'};
			$env{'display_name'} = $$row_hashref{'firstname'} . ' ' . $$row_hashref{'lastname'};
            $env{'user_id'} = $$row_hashref{'id'};
            $env{'md5pwd'} = $$row_hashref{'password'};
			$env{'user_roles'} = &get_user_roles;
            # use the username address to create the token through md5
            # later we'll add a random element to the token to avoid hackers
            $qry = "select md5(".&fix_quotes($env{'username'}).")";
            $sth = $env{'dbh'}->prepare($qry);
            $sth->execute;
            @row_ary = $sth->fetchrow_array;
            $env{'token'} = $row_ary[0];
            # add record to log table
            my %fields;
            $qry = "delete from log where user_id = ".$env{'user_id'};
            $env{'dbh'}->do($qry);
            $qry = "FLUSH TABLE log";
            $env{'dbh'}->do($qry);
            $fields{'login'} = " now() ";
            $fields{'user_id'} = " ".$env{'user_id'}." ";
            $fields{'token'} = "'".$env{'token'}."'";
            $fields{'last_act'} = " now() ";
            &save_record('log', \%fields);
            if ($r->param('menu')) {
                $env{'menu'} = $r->param('menu');
            } else {
                $env{'menu'} = 'undefined';
            }
        } else {
            # no match with username and password
            $env{'username'} = 'not_found';
        }
    } else {
        # no idea why it would get here
        $env{'username'} = 'not_found';
    }
    &log_visit($r);
	if (! $env{'user_id'}) {
		$response = "no_user_id";
	}
    return($response);
}   

sub activate_user {
    # toggles active boolean in users table for user
    my ($r) = @_;
    my $return_message;
    my $user_id = $r->param('userid');
    my $qry = "update users set active = NOT(active) where id = $user_id";
    # my $dbh = &db_connect();
    my $sth = $env{'dbh'}->prepare($qry);  
    $sth->execute;
    $return_message .= $sth->errstr;
    #$qry = "delete from userroles where user_id = $user_id";
    #$sth = $env{'dbh'}->prepare($qry);  
    #$sth->execute;
    #$return_message .= $sth->errstr;
    return $return_message;
}
sub update_user_roles {
    my ($r, $user_id) = @_;
    unless ($user_id) {
        $user_id = $r->param('userid');
    }
    my @roles = $r->param('role');
    # my $dbh = &db_connect();
    my $qry;
    my $sth;
    my $where_clause;
    # first we will get rid of existing roles
    $qry = "delete from userroles where user_id = $user_id";
    $env{'dbh'}->do($qry);
    # now need to retrieve the role id numbers from userroles
    foreach my $role (@roles) {
        $where_clause .= " role = '".$role."' or";
    }
    $where_clause =~ m/(.*)(or$)/;
    $qry = "select * from roles where ".$1;
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    while (my @roleids = $sth->fetchrow_array) {
        $qry = "insert into userroles (user_id, role_id) values ('".$user_id."',".$roleids[0].")";
        $env{'dbh'}->do($qry);
        #$r->print ("adding".$roleids[0]."<br />");
    }
    return $qry;
}
sub get_roles {
	my $qry = "SELECT id, role,short_name FROM roles ORDER BY role ";
	my @roles;
	my $sth = $env{'dbh'}->prepare($qry);
	$sth->execute();
	while (my $row = $sth->fetchrow_hashref) {
		push @roles, {%$row};
	}
	return (@roles);
}
sub retrieve_users {
    my $qry = "select * from users t1,"; 
    return 'ok';
}
sub authenticate {
    my ($role) = @_;
    # my $dbh = &db_connect();
    my $qry;
    my $sth;
    # check if user has authority to access this role function
    $qry = "select * from userroles, roles where user_id = '".$env{'user_id'}."' and userroles.role_id = roles.id and roles.role = '$role'";
	print STDERR "\n $qry \n";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my $num_rows = $sth->rows;
    if ($num_rows > 0) {
        return 'ok';
    } else {
        return 'not ok';
    }
}
sub llab_authenticate {
    my ($role) = @_;
    &Apache::Authenticate::llab_;
    return;
}
sub username_to_userid {
    my ($username) = @_;
    my $user_id;
    # my $dbh = &db_connect();
    my $sth;
    my $qry = "select id from users where username = '$username'";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my @row = $sth->fetchrow_array;
    $user_id = $row[0];
    return $user_id;
}

sub add_new_user {
    my ($r) = @_;
    my $qry;
    my $sth;
    my %fields;
    my $email=$r->param("email");
    my $upload_dir = "/var/www/html/images/userpics";
    my $upload_filehandle = $r->upload('photo');
    my $file_name = $r->param('photo');
    $file_name = &fix_filename($file_name);
    # this gets the user into the MySQL database
    $fields{'firstname'}=&fix_quotes($r->param("firstname"));
    $fields{'lastname'}=&fix_quotes($r->param("lastname"));
    $fields{'email'}=&fix_quotes($r->param('email'));
    $fields{'state'}=&fix_quotes($r->param("state"));
    $fields{'username'}=&fix_quotes($r->param("username"));
    $fields{'photo'}=&fix_quotes($file_name);
    $fields{'password'}= &fix_quotes($r->param("password"));
    $fields{'bio'}=&fix_quotes($r->param("textarea"));
    my $user_id = &save_record('users',\%fields, 'id');
    # next, create the entry in the LessonLab LDAP
    
    # now handle the picture upload
    open UPLOADFILE, ">$upload_dir/$file_name";
    binmode UPLOADFILE;
    while ( <$upload_filehandle> ) { 
        print UPLOADFILE; 
    } 
    close UPLOADFILE;
    $qry = "select id from roles where role = 'Apprentice'";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    if (my @roleids = $sth->fetchrow_array) {
        undef %fields;
        $fields{'user_id'}=$user_id;
        $fields{'role_id'}=$roleids[0];
        &save_record('userroles',\%fields);
    }
    # now we read record from database for absolute confirmation that record was stored
    $qry = "select * from users where username ='".$env{'username'}."'";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my $saved_record = $sth->fetchrow_hashref;
    return $saved_record;
}
sub user_name_exist {
    my ($username) = @_;
    my $status = 1; # 0 is ok, 1 is name exists
    my %fields;
    $fields{'llab_cn'} = &fix_quotes($username);
    # checks if username is available both in ldap and users table;
    if (@{&Apache::Promse::record_exist('users', \%fields)}==0) {
        # here if record doesnt' exist in MySQL
        # now check LDAP
        undef %fields;
        $fields {'cn'} = $username;
        if (&Apache::Authenticate::llab_ldap_search(\%fields) == 0) {
            $status = 0;
        } else {
            $status = 2;
        }
    }
    return $status;
}
sub record_exist {
    my ($table, $fields) = @_;
    my $where_clause;
    my $qry = "select * from $table where ";
    foreach my $field_name (keys(%{$fields})){
        $where_clause .= $field_name."=".${$fields}{$field_name}.' and ';
    }
    $where_clause =~ s/ and $//;
    $qry .= $where_clause;
    my $sth = $env{'dbh'}->prepare($qry);  
    $sth->execute;
    if (my @found_record = $sth->fetchrow_array()) {
        return (\@found_record);
    } else {
        return (0);
    }
}
sub token_to_userid {
    my ($token) = @_;
    my $user_id;
    my $qry;
    # my $dbh = &db_connect();
    $qry = "select user_id from log where token = '".$token."'";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my @rs_userid = $sth->fetchrow_array;
    $user_id = $rs_userid[0];
    return $user_id;
}
sub userid_to_display_name {
    my ($user_id) = @_;
    my $display_name;
    my $qry = "select lastname, firstname from users where id = $user_id.";
    # my $dbh = &db_connect();
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my $row = $sth->fetchrow_hashref;
    $display_name = $$row{'firstname'}." ".$$row{'lastname'};
    return $display_name;    
}
sub username_to_display_name {
    my ($username)=@_;
    my $display_name;
    my $qry = "select lastname, firstname from users where username = ".&fix_quotes($username);
    # my $dbh = &db_connect();
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my $row = $sth->fetchrow_hashref;
    $display_name = $$row{'firstname'}." ".$$row{'lastname'};
    return $display_name;    
}
sub token_to_username {
    my ($token)=@_;
    my $username;
    my $qry;
    # my $dbh = &db_connect();
    my $user_id = &token_to_userid($token);
    $qry = "select username from users where id = '".$user_id."'";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute;
    my @rs_username = $sth->fetchrow_array;
    $username = $rs_username[0];
    return $username;
}
sub html_head_content {
    my ($r) = @_;
    my $url;
    my $output = q~
    <head>
    <!-- Unicode encoding -->
     ~;
    if ($env{'refresh'}) {
        if (!(defined($url))) {
            $url='';
        }
        $output .= '<META HTTP-EQUIV="Refresh" CONTENT="'.$env{'refresh'};
        $output .= '; '.$url.'" />';
     }
     #     <style type="text/css" media="all">@import "../_stylesheets/advanced.css";</style>

    $output .= q~
    
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <title>PROMSE</title>
    <meta name="keywords" content="prom/se, PROM/SE, promse, PROMSE, K-12, K-12 mathematics, K-12 science, K-12 education, math, science" />
    <!-- Use the import to use more sophisticated css. Lower browsers (less then 5.0) do not process the import instruction, will default to structural markup -->
    <style type="text/css" media="all">@import "../_stylesheets/advanced.css";</style>
    <script src="../_scripts/general.js" type="text/javascript" charset="utf-8"></script>
    <script src="//ajax.googleapis.com/ajax/libs/jquery/1.11.0/jquery.min.js"></script>
	<link rel="stylesheet" href="//ajax.googleapis.com/ajax/libs/jqueryui/1.10.4/themes/smoothness/jquery-ui.css" />
	<script src="//ajax.googleapis.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js"></script>
	<script src="../_scripts/video.js" type="text/javascript" charset="utf-8"></script>
    <SCRIPT type="text/javascript">
    //Redirect if Mac IE
    if (navigator.appVersion.indexOf("Mac")!=-1 && navigator.appName.substring(0,9) == "Microsoft") {
    	window.location="mac_ie_note.html";
    }
    </SCRIPT>
~;
    $output .= &dynamic_css($r);
    $output .=   '<style type="text/css" media="all">@import "../_stylesheets/ng_editor.css";</style>';

    $output .= '</head>';
    return ($output);    
}
sub top_of_page_menus {
    my ($r, $screen, $tab_menu) = @_;
    my $display_name = &username_to_display_name($env{'username'});
    my $user_roles = &get_user_roles($env{'token'});
    my $teacher_associate;
    if (($user_roles =~ m/Teacher/)  && ($user_roles !~ m/Apprentice/)) {
        $teacher_associate = "Teacher";
    } elsif ($user_roles =~ m/Apprentice/) {
        $teacher_associate = "Associate";
    }
    print $r->header(-type => 'text/html',
                    -expires => 'now');
    my $output = q~
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
    <html lang="en" xml:lang="en">
    <!-- Above is the Doctype for strict xhtml -->
    ~;
    $r->print($output);
    $r->print(&html_head_content($r));
    $output = q~
    <body onload="onloadFunctions('Home','NULL');">
     ~;
    $r->print($output);
    $r->print("\n".'<div id="wrapperColumn">'."\n");
    # $r->print('<img src="../_images/BannerTop.gif" alt="" /><br />');
    $r->print('<a href="http://www.promse.msu.edu"><img src="../_images/BannerTopWide.jpg" alt="" /></a>');
    if ($env{'token'} ne ''){ 
        if (!$tab_menu) {
            $r->print ('<p align="right">'."\n");
            $r->print ('Welcome, '.$display_name.' <a href="logout?token='.$env{'token'}.'">Logout</a></p>'."\n");
        } else {
            $r->print ('<p id="logoutLink" >'."\n");
            $r->print ('Welcome, '.$display_name.' <a href="logout?token='.$env{'token'}.'">Logout</a></p>'."\n");
            $r->print ('<p>&nbsp;</p>');
#            $output = qq~
#            <p align="right">
#            <div id="logoutLink">Welcome, $display_name <a href="logout?token=$env{'token'}">Logout</a></div>
#            </p>
#            ~;
#            $r->print($output);
        }
        if ($tab_menu) {
            $r->print ('<div id="shiftWrapper">');
            $r->print($tab_menu);
            $r->print(&tabbed_menu_end);
        } else {
            $r->print ('<div id="noShiftWrapper">');
        }
    } else {	
    	$r->print ('<p align = right>'."\n");
    	$r->print ('Welcome, Please login</p>'."\n");
    }
    $output=q~
                </h3>
		<span class="noShow">PROM/SE: Promoting Rigorous Outcomes in Mathematics and Science Education</span>
     ~;

        $r->print('<div id="navcolumn">'."\n");
        $r->print('<table width="55" border="0" cellpadding="0" cellspacing="0" id="navigation">'."\n");
        $r->print('<tr>'."\n");
        $r->print('<td width="50" bgcolor="#eeeeee">&nbsp;<br />'."\n");
        $r->print('&nbsp;<br /></td>'."\n");
        $r->print('</tr>'."\n");
        $r->print('<tr>'."\n");
        $r->print('<td width="50" bgcolor="#eeeeee">'."\n");
        $r->print('<a href="home?menu=home;token='.$env{'token'}.'" class="navText" title = "Home"><img src="../images/promse_icons_home.gif" width="32" height="32" alt="Home" /></a>&nbsp;'."\n");
        $r->print("\n");
        $r->print('</td>'."\n");
        $r->print('</tr>'."\n");
        $r->print('<tr>'."\n");
        $r->print('<td width="50" bgcolor="#eeeeee">'."\n");
        $r->print('<br/><a href="home?menu=resources;token='.$env{'token'}.'&amp;target=resources" class="navText" title = "Recommended Resources"><img src="../images/promse_icons_resources.gif" width="32" height="32" alt="Resources" /></a>&nbsp;'."\n");
        $r->print("\n");
        $r->print('</td>'."\n");
        $r->print('</tr>'."\n");
#        $r->print('<tr>'."\n");
#        $r->print('<td width="50" bgcolor="#eeeeee"><a href="javascript:;" class="navText" title = "Partners"><img src="../images/Shake0a.gif" width="32" height="32" alt="Partners" /></a>&nbsp;</td>'."\n");
#        $r->print('</tr>'."\n");
        $r->print('<tr>'."\n");
        $r->print('<td width="50" bgcolor="#eeeeee">
                    <a href="home?token='.$env{'token'}.'&amp;target=groups" class="navText" title = "Working Groups"><img src="../images/promse_icons_group.gif" width="28" height="32" alt="Groups" /></a></td>'."\n");
        $r->print('</tr>'."\n");
        $r->print('<tr>'."\n");
        $r->print('<td width="50" bgcolor="#eeeeee">
                <a href="home?token='.$env{'token'}.';target=help;helptopic='.$env{'help_topic'}.'" class="navText" title = "Info Center"><img src="../images/promse_icons_info.gif" width="32" height="32" alt="Information" /></a></td>'."\n");
        $r->print('</tr>'."\n");
        $r->print('<tr>'."\n");
        $r->print('<td height="24" bgcolor="#eeeeee"> '."\n");
        $r->print('<span class="navText style7"><br />
            <a href="home?token='.$env{'token'}.'&amp;menu=data;submenu=tabular" class="navText" title = "District Data"><img src="../images/promse_icons_data.gif" width="32" height="36" alt="Data" /></a></span>'."\n");
        $r->print('</tr>');
        if ($user_roles =~ m/Admin/) {
            my %fields;
            %fields = ('token' => $env{'token'},
                       'submenu' => 'roles',
                       'menu' => 'users');
            my $url = &build_url('admin',\%fields);
            $r->print('<tr><td height="24" bgcolor="#eeeeee"> '."\n");
            $r->print('<a href="'.$url.'">Admin</a>');
            $r->print('</td></tr>');
        }
        if ($user_roles =~ m/Editor/) {
            my %fields = ('token'=>$env{'token'},
                           'menu'=>'curriculum',
                           'submenu'=>'browse');
            my $url = &build_url('editor',\%fields);
            $r->print('<tr><td height="24" bgcolor="#eeeeee"> '."\n");
            $r->print('<a href="'.$url.'">Editor</a>');
            $r->print('</td></tr>');
        }
        if ($user_roles =~ m/Mentor/) {
            my %fields = ('token' => $env{'token'},
                          'menu' => 'questions',
                          );
            my $url = &build_url('mentor',\%fields);
            $r->print('<tr><td height="24" bgcolor="#eeeeee"> '."\n");
            $r->print('<a href="'.$url.'">Mentor</a>');
            $r->print('</td></tr>');
        }
        if ($user_roles =~ m/Reviewer/) {
            my %fields = ('token' => $env{'token'},
                          'menu' => 'curriculum',
                          );
            my $url = &build_url('reviewer',\%fields);
            $r->print('<tr><td height="24" bgcolor="#eeeeee"> '."\n");
            $r->print('<a href="'.$url.'">Reviewer</a>');
            $r->print('</td></tr>');
        }
        if (($user_roles =~ m/Apprentice/)||($user_roles =~ m/Teacher/) ){
            my %fields = ('token' => $env{'token'},
                          'menu' => 'home');
            my $url = &build_url('apprentice',\%fields);
            $r->print('<tr><td height="24" bgcolor="#eeeeee"> '."\n");
            $r->print('<a href="'.$url.'">Teacher</a>');
            $r->print('</td></tr>');
        }
        
        $r->print('<tr>'."\n");
        $r->print('<td width="50" bgcolor="#eeeeee">&nbsp;<br />');
        $r->print('&nbsp;<br /></td></tr>');
        $r->print('<tr><td bgcolor="#eeeeee">&nbsp;</td></tr>');
        $r->print('<tr><td bgcolor="#eeeeee">&nbsp;</td>');
        $output=q~
            </tr>
        </table>
           ~;
        $r->print($output);
        $r->print('</div>'); # close the nav column
        my $big_content;
        if ($env{'menu'} eq 'curriculum') {
            $big_content = ' style="width: 1024px;height: 768px" ';
        } else {
            $big_content = '';
        }
    $r->print('<div id="interiorContent"'.$big_content.' >'."\n");
    # we start the page (with menus) but leave
    # four <div>s opened that need closing elsewhere 
    # (wrapper, wrapperColumn,shiftWrapper (or noShiftWrapper, mainColumn and interiorContent)
    return 'ok';
}
sub purge_idle_users {
    return();
	# disable the routine 
    my $qry;
    my $sth;
    my $row;
    my %fields;
    # first, select all users in log with lastactivity more than two hours ago
    $qry = "select user_id from log where date_sub(now(),interval 1 hour) > last_act";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    # for each found, write a record in the activity log indicating auto log out
    while ($row = $sth->fetchrow_hashref()) {
        my $user_id = $$row{'user_id'};
        %fields = ('user_id'=>$user_id,
                      'date'=> ' now() ',
                      'resource_id'=>" 'Auto Logout' ");
        &save_record('activity_log',\%fields);
        # then delete the record from the log
        $qry = "DELETE FROM log WHERE user_id = $user_id ";
        $env{'dbh'}->do($qry);
        # release any locks on curriculum grades
        $qry = "DELETE FROM checkout WHERE user_id = $user_id ";
        $env{'dbh'}->do($qry);
    }
}
sub admin_stats {
    my ($r) = @_;
    my $qry;
    my $sth;
    my $row;
    my %fields;
    if ($env{'action'} eq 'purgelog') {
        # first, select all users in log with lastactivity more than two hours ago
        $qry = "select user_id from log where date_sub(now(),interval 2 hour) > last_act";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        # for each found, write a record in the activity log indicating auto log out
        while ($row = $sth->fetchrow_hashref()) {
            my $user_id = $$row{'user_id'};
            %fields = ('user_id'=>$user_id,
                          'date'=> ' now() ',
                          'resource_id'=>" 'Auto Logout' ");
            &save_record('activity_log',\%fields);
            # then delete the record from the log
            $qry = "delete from log where user_id = $user_id ";
            $env{'dbh'}->do($qry);
        }
        
        $r->print('purged log <br />');
    }
    if ($env{'action'} eq 'toggledemo') {
        if ($env{'demo_mode'}) {
            $qry = "update config set demo_mode = 0";
            $env{'demo_mode'} = 0;
        } else {
            $qry = "update config set demo_mode = 1";
            $env{'demo_mode'} = 1;
        }
        $env{'dbh'}->do($qry);
        
    }
    # let's get the count of all users
    $qry = "select count(id) total from users";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $row = $sth->fetchrow_hashref();
    my $total_users = $$row{'total'};
    $qry = "select min(date) earliest from activity_log";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $row = $sth->fetchrow_hashref();
    my $earliest_time = $$row{'earliest'};   
    $qry = "SELECT count( distinct user_id) userson FROM activity_log";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $row = $sth->fetchrow_hashref();
    my $users_on = $$row{'userson'};    
    $qry = "select count(*) hits from activity_log where date_sub(now(),interval 1 hour) < date";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $row = $sth->fetchrow_hashref();
    my $hits_last_hour = $$row{'hits'};    
    $qry = "SELECT count( distinct user_id) userson FROM log";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    $row = $sth->fetchrow_hashref();
    my $users_logged_on = $$row{'userson'};
    if ($r->param('fullstats')) {
        my ($mean_sessions, $max_sessions, $clicks_per_session, $time_on_page, $length_of_session) = &get_usage(undef,undef);
        $r->print("mean number of sessions: $mean_sessions <br />");
        $r->print("max number of sessions: $max_sessions <br />");
        $r->print("clicks per sessions: $clicks_per_session <br />");
        $r->print("seconds per session: $length_of_session <br />");
    }
    $r->print('<div class="statInfo">');
    $r->print('Total users in database: '.$total_users.'<br />');
    $r->print('Number of users logged on: '.$users_logged_on.'<br />');
    $r->print('Number of users in activity log: '.$users_on.'<br />');
    $r->print('Number of hits in last hour: '.$hits_last_hour.'<br />');
    $r->print('Earliest time recorded in activity log: '.$earliest_time.'<br />');
    $r->print('</div>');
    %fields = ('target'=>'stats',
                  'token'=>$env{'token'},
                  'menu'=>'stats',
                  'submenu'=>'system', 
                  'action'=>'toggledemo');
    my $url = &build_url("admin",\%fields);              
    if ($env{'demo_mode'}) {
        $r->print('<a href="'.$url.'">Demo mode is on, click to turn off</a><br />');
    } else {
        $r->print('<a href="'.$url.'">Demo mode is off, click to turn on</a><br />');
    }
    %fields = ('target'=>'stats',
                  'token'=>$env{'token'},
                  'action'=>'purgelog',
                  'submenu'=>'system', 
                  'menu'=>'stats');
    $url = &build_url("admin",\%fields);
    $r->print('<a href="'.$url.'">Purge log of users idle more than 2 hours</a><br />');
    &who_is_on($r);
    return 'ok';
}
sub click_array_to_sessions {
    my ($clicks) = @_;
    my $session_count = 1;
    my $previous_click = shift(@$clicks);
    my $done = 0;
    my $session_click_count = 0;
    my $session_time_total = 0;
    my @sessions; #array of hashes 'num_clicks'=>n,'average_time_on_page'=>n seconds
    while (!$done) {
        my $current_click = shift(@$clicks);
        if (defined $current_click) {
            my $prev_time = $$previous_click{'date'};
            my $current_time = $$current_click{'date'};
            my $qry = "select time_to_sec(timediff('$current_time','$prev_time')) as diff";
            my $sth = $env{'dbh'}->prepare($qry);
            $sth->execute();
            my $row = $sth->fetchrow_hashref();
            my $time_on_page = $$row{'diff'};
            if (!($$current_click{'session_end'} || ($time_on_page > 600))) {
                $session_click_count += 1;
                $session_time_total += $time_on_page;
            } else {
                $time_on_page = ($time_on_page > 600)?600:$time_on_page;
                # here we figure the mean time per click
                if ($session_click_count) {
                    my $session_average_time = $session_time_total / $session_click_count;
                    push @sessions, {'num_clicks'=>$session_click_count,
                                    'average_time_on_page'=>$session_average_time};
                }
                $session_click_count = 0;
                $session_time_total = 0;
            }
            $previous_click = $current_click;
        } else {
            # finish up processing current session
            if ($session_click_count) {
                my $session_average_time = $session_time_total / $session_click_count;
                push @sessions, {'num_clicks'=>$session_click_count,
                                 'average_time_on_page'=>$session_average_time};
            }
            $done = 1;
        }
    }
    
    return(\@sessions);
}
    
sub get_usage {
    my ($earliest,$latest) = @_;
    my $stats;
    my $qry;
    my $sth;
    my @users;
    my @click_counts;
    my $total_sessions;
    # get all the users in the activity log
    $qry = 'SELECT DISTINCT user_id FROM activity_log WHERE user_id <> 0 ORDER BY user_id DESC';
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push @users,$$row{'user_id'};
    }
    my $n_users = scalar(@users);
    my $total_clicks;
    my $max_sessions;
    my $time_on_page;
    my $length_of_session;
    my $total_session_time;
    foreach my $user_id (@users) {
        # get all the clicks of particular user
        $qry = "SELECT date, (resource_id regexp 'logout') as session_end FROM activity_log WHERE user_id = $user_id order by date";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my @user_clicks;
        while (my $row = $sth->fetchrow_hashref()) {
            push @user_clicks, {%$row};
        }
        my $sessions = &click_array_to_sessions(\@user_clicks);
        $max_sessions = ($max_sessions < scalar @$sessions)?scalar(@$sessions):$max_sessions;
        $total_sessions += scalar(@$sessions);
        foreach my $session(@$sessions) {
            $total_clicks += $$session{'num_clicks'};
            $total_session_time += $$session{'num_clicks'} * $$session{'average_time_on_page'};
        }
    }
    my $mean_sessions = $total_sessions / $n_users;
    my $clicks_per_session = $total_clicks / $total_sessions;
    $length_of_session = $total_session_time / $total_sessions;
    # return(\@click_counts);
    return($mean_sessions, $max_sessions, $clicks_per_session, $time_on_page, $length_of_session);
}
sub get_course_notebook {
    my ($user_id) = @_;
    my @notebook;
    my $qry = "select * from course_notebook where user_id = $user_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push(@notebook, {%$row});
    }
    return(\@notebook);
}
sub get_segment_notebook {
    my ($user_id, $segment_id) = @_;
    my @notebook;
    my $qry = "select * from course_notebook where user_id = $user_id and segment_id = $segment_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $got_one = 0;
    while (my $row = $sth->fetchrow_hashref()) {
        push(@notebook, {%$row});
        $got_one = 1;
    }
    if (!$got_one) { # create new entry if one does not exist
        $qry = "insert into course_notebook (user_id, segment_id, course_id, date_started, date_updated)
                values ($user_id, $segment_id, $env{'course_id'}, now(), now())";
        $env{'dbh'}->do($qry);
        $qry = "select * from course_notebook where user_id = $user_id and segment_id = $segment_id";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        push(@notebook, {%$row});
    }       
    return(\@notebook);
}
sub update_segment_notebook {
    my ($r) = @_;
    my $content = &fix_quotes($r->param('content'));
    my $segment_id = $r->param('segment');
    my $course_id = $env{'course_id'};
    my $user_id = $env{'user_id'};
    my $qry = "update course_notebook set content = $content, date_updated = now() WHERE
               segment_id = $segment_id and course_id = $course_id and user_id = $user_id";
    $env{'dbh'}->do($qry);
}
sub course_study {
    my ($r) = @_;
    my $segment = $r->param('segment')?$r->param('segment'):&get_last_segment($env{'user_id'},$env{'course_id'});
    $r->print('<div style="float: left;width: 300px;height: 500px;display: block;">');
    $r->print(&Apache::Promse::show_course_segments($env{'course_id'},'study'));
    $r->print('</div>');
    $r->print('<div style="float: right;width: 350px;height: 495px;display: block;">');
    my $segment_notebook = &get_segment_notebook($env{'user_id'},$segment);
    foreach my $entry (@$segment_notebook) {
        $r->print("started: ".$$entry{'date_started'}.'<br />');
        $r->print("updated: ".$$entry{'date_updated'}.'<br />');
        $r->print('<form method="post" action="">'."\n");
        $r->print('<input type="submit" value="Save Changes" /><br />');
        $r->print('<textarea name="content" rows="25" cols="45">');
        $r->print($$entry{'content'});
        $r->print('</textarea>');
        my %fields = ('menu'=>'courses',
                      'submenu'=>'study',
                      'courseid'=>$env{'course_id'},
                      'action'=>'updatesegmentnotebook',
                      'segment'=>$r->param('segment'));
        $r->print(&hidden_fields(\%fields));
        $r->print('</form>'."\n");
    }
    $r->print('</div>');    
}
sub admin_menu {
    my ($r) = @_;
    $r->print('<span class="nav">[ <a href="admin?token='.$env{'token'}.'&amp;target=stats" id="navAdmin" >Stats </a> ]</span> ');
    $r->print('<span class="nav">[ <a href="admin?target=userroles;token='.$env{'token'}.'" >User Roles</a> ]</span>');
    $r->print('<span class="nav">[ <a href="admin?target=schedule&amp;token='.$env{'token'}.'&amp;menu=browse">Announcements</a> ]</span>');
    $r->print('<span class="nav">[ <a href="admin?token='.$Apache::Promse::env{'token'}.'&amp;target=addvpdrecord">Add User</a> ]</span>');
    $r->print('<span class="nav">[ <a href="admin?token='.$Apache::Promse::env{'token'}.'&amp;target=editdistricts">Districts</a> ]</span>');
    $r->print('<span class="nav">[ <a href="admin?token='.$Apache::Promse::env{'token'}.'&amp;target=editlocations">Locations</a> ]</span>');
    $r->print('<span class="nav">[ <a href="admin?token='.$Apache::Promse::env{'token'}.'&amp;target=rss">RSS</a> ]</span>');
    $r->print('<br /><br />');
    return 'ok';
}
sub apprentice_menu {
    my ($r) = @_;
    $r->print('<div>');
    $r->print('<span class="nav">[ <a href="apprentice?token='.$env{'token'}.';target=search;menu=inbox" title="Search">Search</a> ]</span>');
    $r->print('<span class="nav">[ <a href="apprentice?token='.$env{'token'}.';target=framework;menu=browse" title="Framework">Framework</a> ]</span>');
    # $r->print('[ <a href="apprentice?token='.$env{'token'}.';target=frameworkreporter;step=1" title="Alignment">Alignment</a> ]');
    $r->print('<span class="nav">[ <a href="apprentice?token='.$env{'token'}.';target=minicourse" title="Mini-Courses">Mini-Courses</a> ]</span>');
    $r->print('<span class="nav">[ <a href="apprentice?token='.$env{'token'}.';target=questions;menu=inbox" title="Questions">Questions</a> ]</span>');
    $r->print('</div>');
    return 'ok';
}
sub course_menu {
    my ($r) = @_;
    my $output = qq~
        <script type="text/javascript">
        function sizeWindow() {
            window.screenX = 0;
            window.screenY = 0;
            window.innerWidth = 800;
            window.innerHeight = 600;
            open("http://vpddev.educ.msu.edu/promse/login","newwindow");
        }
        </script>
    ~;
    # $r->print($output);
    $r->print('<span class="nav">[ <a href="javascript:sizeWindow()" title="Notebook">Notebook</a> ]</span>');
    #$r->print('<span class="nav">[ <a href="apprentice?token='.$env{'token'}.';target=framework;menu=browse" title="Framework">Framework</a> ]</span>');
    #$r->print('[ <a href="apprentice?token='.$env{'token'}.';target=frameworkreporter;step=1" title="Alignment">Alignment</a> ]');
    #$r->print('<span class="nav">[ <a href="apprentice?token='.$env{'token'}.';target=minicourse" title="Mini-Courses">Mini-Courses</a> ]</span>');
    #$r->print('<span class="nav">[ <a href="apprentice?token='.$env{'token'}.';target=questions;menu=inbox" title="Questions">Questions</a> ]</span>');
    return 'ok';
}
sub mentor_menu {
    my ($r) = @_;
    $r->print('<span class="nav">[ <a href="mentor?token='.$env{'token'}.';target=questions;menu=inbox;sortfield=date" title="Questions">Questions</a> ]</span>'."\n");
    $r->print('<span class="nav">[ <a href="mentor?token='.$env{'token'}.';target=questions;menu=drafts;sortfield=date" title="drafts">Drafts</a> ]</span>'."\n");
    $r->print('<span class="nav">[ <a href="mentor?token='.$env{'token'}.';target=resource;menu=browse" title="Resources">Resources</a> ]</span>'."\n");
    $r->print('<span class="nav">[ <a href="mentor?token='.$env{'token'}.';target=framework;menu=browse" title="Framework">Framework</a> ]</span>'."\n");
    $r->print('<span class="nav">[ <a href="mentor?token='.$env{'token'}.';target=ohiomath;menu=browse" title="Ohio Math">Ohio Math</a> ]</span>'."\n");
    return 'ok';
}

sub editor_menu {
    my ($r) = @_;
    $r->print('<span class="nav">[ <a href="editor?token='.$env{'token'}.';target=resource;menu=browse" title="Resources">Resources</a> ]</span>'."\n");
    $r->print('<span class="nav">[ <a href="editor?token='.$env{'token'}.';target=minicourse;tablayer=courses" title="Mini-Courses">Mini-Courses</a> ]</span>'."\n");
    
#    $r->print('<li><span class="nav"><a href="editor?token='.$env{'token'}.';target=keyword;menu=browse" title="Keywords">Keywords</a></span></li>'."\n");
#   $r->print('<li><span class="nav"><a href="editor?token='.$env{'token'}.';target=curriculum;step=1" title="Keywords">Curriculum</a></span></li>'."\n");

    return 'ok';
}


sub interior_header {
    my($r,$head_text)= @_;
    $r->print('<div id="interiorHeader">'."\n");
    $r->print('<h2>'.$head_text.'</h2>'."\n");
    $r->print('</div>'."\n");
    return 'ok';
}
sub footer {
    my ($r) = @_;
    $r->print('</div>'."\n"); # close interiorContent
    # $r->print("</div>"); # close  mainColumn 
          
    my $output = q~
        <div id="wrapperFooter">
            <hr />
            <ul id="footerPartnerList">
            <li id="footerLiNSF"><a href="http://www.promse.msu.edu/overview/partners.asp#NSF" title="National Science Foundation"><span>National Science Foundation</span></a></li>
            <li id="footerLiSMART"><a href="http://www.promse.msu.edu/overview/partners.asp#SMART" title="SMART Consortium"><span>SMART Consortium</span></a></li>
            <li id="footerLiAIMS"><a href="http://www.promse.msu.edu/overview/partners.asp#AIMS" title="High AIMS Consortium"><span>High AIMS Consortium</span></a></li>
            <li id="footerLiIngham"><a href="http://www.promse.msu.edu/overview/partners.asp#Ingham" title="Ingham County Intermediate School District"><span>Ingham County Intermediate School District</span></a></li>
            <li id="footerLiCalhoun"><a href="http://www.promse.msu.edu/overview/partners.asp#Calhoun" title="Calhoun County Intermediate School District"><span>Calhoun County Intermediate School District</span></a></li>
            <li id="footerLiStClair"><a href="http://www.promse.msu.edu/overview/partners.asp#StClair" title="St. Clair County Regional Educational Service Agency"><span>St. Clair County Regional Educational Service Agency</span></a></li>
            <li id="footerLiMSU"><a href="http://www.promse.msu.edu/overview/partners.asp#MSU" title="MSU PROM/SE Project"><span>MSU PROM/SE Project</span></a></li>
            <li id="footerLiMSUInfo">© MSU PROM/SE Project, Michigan State University, 236 Erickson Hall, East Lansing, MI 48824, phone 517/353-4884, fax 517/432-0132.</li>
            </ul>
            <p>
            www.promse.msu.edu. PROM/SE is funded by the National Science Foundation under Cooperative Agreement Grant No. EHR-0314866.
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
    <title>PROMSE</title>
    <meta name="description" content="PROM/SE - Promoting rigorous outcomes in K-12 mathematics and science education" />
    <meta name="keywords" content="prom/se, PROM/SE, promse, PROMSE, K-12, K-12 mathematics, K-12 science, K-12 education, math, science" />
    <!-- Use the import to use more sophisticated css. Lower browsers (less then 5.0) do not process the import instruction, will default to structural markup -->
    <style type="text/css" media="all">@import "../_stylesheets/advanced.css";</style>
    <style type="text/css" media="all">@import "../_stylesheets/ng_editor.css";</style>

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
    $r->print('<img src="../_images/BannerTopWide.jpg" alt="" />');   

    my $screen = 'home';
    
    $r->print('<div id="noShiftWrapper">'."\n");
    $r->print("&nbsp;");
    $r->print('<div id ="navcolumn">'."\n");
    $r->print('<br /><br /><br /><br /><br /><br /><br /><br /><br /><br />&nbsp;');
    $r->print('</div>'."\n");
    $r->print('<div id="interiorContent">'."\n");
    return ();
}    

sub get_locations {
    my ($r) = @_;
    my $qry = "";
    my $sth;
    $qry = "select location_id, school, Grade_range from locations order by school";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    return $sth;
}
sub get_course_segments {
    my($course_id) = @_;
    my @course_segments;
    # following query gets first segment(previous eq 0)
    my $qry = "select t1.id, t1.resource_id, t1.course_id, t1.next, t1.previous, t2.title, 
             t1.organizer,  t2.comments, t2.type, t2.location, t1.resource_type FROM
             course_sequence t1, resources t2 WHERE
             $course_id = t1.course_id and previous = 0 and t1.resource_id = t2.id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $done = 0;
    my $next;
    if (my $row = $sth->fetchrow_hashref()) {
        push(@course_segments,{%$row});
        if ($$row{'next'} eq 0) {
            $done = 1;
        } else {
            $next = $$row{'next'};
        }
            
    } else {
        $done = 1;
    }
    while (!$done) {
        $qry = "select t1.id, t1.resource_id, t1.course_id, t1.next, t1.previous, t2.title, t1.organizer,  
                t2.comments, t2.type, t2.location, t1.resource_type FROM
                course_sequence t1, resources t2
                WHERE $course_id = t1.course_id and 
                        t1.id = $next and t1.resource_id = t2.id";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        if (my $row = $sth->fetchrow_hashref()) {
            push(@course_segments,{%$row});
            if ($$row{'next'} eq 0) {
                $done = 1;
            } else {
                $next = $$row{'next'};
            }
        } else {
            $done = 1;
        }
    }
    return \@course_segments;
}
sub remove_course_segment {
    my ($segment_id)= @_;
    my $qry;
    my $sth;
    my $new_next;
    my $new_previous;
    $qry = "select previous, next from course_sequence where id = $segment_id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    my $previous = $$row{'previous'};
    my $next = $$row{'next'};
    $qry = "delete from course_sequence where id = $segment_id";
    $env{'dbh'}->do($qry);
    if ($previous) {
        if ($next) {
            $new_next = $next;
        } else {
            $new_next = 0;
        }
        $qry = "update course_sequence set next = $new_next where id = $previous";
        $env{'dbh'}->do($qry);
    }
    if ($next) {
        if ($previous) {
            $new_previous = $previous;
        } else {
            $new_previous = 0;
        }
        $qry = "update course_sequence set previous = $new_previous where id = $next";
        $env{'dbh'}->do($qry);
    }
    return ();
}
sub add_course_segment {
    my ($course_id, $resource_id, $position, $type, $organizer) = @_;
    $organizer = $organizer?$organizer:"";
    # first get existing segments in order
    my $sequence = &get_course_segments($course_id);
    my $sequence_length = scalar(@$sequence);
    if ($position eq "") {
        # if no specification of position then add at end
        $position = $sequence_length + 1;
    }
    my %fields;
    if ($sequence_length eq 0) {
        # creating new sequence so next and previous are both 0
        %fields = ('resource_id'=>$resource_id,
                        'course_id'=>$course_id,
                        'resource_type'=>&fix_quotes($type),
                        'organizer'=>&fix_quotes($organizer),
                        'previous'=>0,
                        'next'=>0
                        );
        &save_record('course_sequence',\%fields,1);
    } else {
        # adding to an existing sequence so need to modify
        # existing records
        # three possibilities 1. insert in first position
        # 2. insert in middle, 3. append to end of sequence
        if ($position eq 1) {
            # need to modify record with previous eq 0 so previous = new record id
            %fields = ('resource_id'=>$resource_id,
                        'course_id'=>$course_id,
                        'resource_type'=>&fix_quotes($type),
                        'organizer'=>&fix_quotes($organizer),
                        'previous'=>0,
                        'next'=>$$sequence[0]{'id'}
                        );
            my $new_id = &save_record('course_sequence',\%fields,1);
            my $qry = "update course_sequence set previous = $new_id where id = $$sequence[0]{'id'}";
            $env{'dbh'}->do($qry);
        } elsif ($position le $sequence_length) {
            # inserting in the middle means changing 'next' of prior segment and 'previous' of 
            # following segment
            %fields = ('resource_id'=>$resource_id,
                        'course_id'=>$course_id,
                        'resource_type'=>&fix_quotes($type),
                        'organizer'=>&fix_quotes($organizer),
                        'previous'=>$$sequence[$position - 2]{'id'},
                        'next'=>$$sequence[$position - 1]{'id'}
                        );
            my $new_id = &save_record('course_sequence',\%fields,1);
            my $qry = "update course_sequence set next = $new_id where id = ".$$sequence[$position - 2]{'id'};
            $env{'dbh'}->do($qry);
            $qry = "update course_sequence set previous = $new_id where id = ".$$sequence[$position - 1]{'id'};
            $env{'dbh'}->do($qry);
        } else {
            # this appends to the end of the linked list
            %fields = ('resource_id'=>$resource_id,
                        'course_id'=>$course_id,
                        'resource_type'=>&fix_quotes($type),
                        'organizer'=>&fix_quotes($organizer),
                        'previous'=>$$sequence[$sequence_length - 1]{'id'},
                        'next'=>0
                        );
            my $new_id = &save_record('course_sequence',\%fields,1);
            my $qry = "update course_sequence set next = $new_id where id = $$sequence[$sequence_length - 1]{'id'}";
            $env{'dbh'}->do($qry);
        }
        
    }
    return();
}
sub delete_course {
    my ($course_id) = @_;
    my $qry;
    my $sth;
    my $return_msg;
    # first check if anybody has taken the course
    $qry = "select user_id from course_users where course_id = $course_id limit 1";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    if (my $row = $sth->fetchrow_hashref) {
        # found someone who's taking the course
        $return_msg = "Course user found";
    } else {
        $qry = "delete from courses where id = $course_id";
        $env{'dbh'}->do($qry);
        $qry = "delete from course_sequence where course_id = $course_id";
        $env{'dbh'}->do($qry);
        $return_msg = "Course Deleted";
    }
    return($return_msg);
}
sub get_course_title {
    my ($course_id) = @_;
    my $qry;
    my $sth;
    my $course_title;
    $qry = "select name from courses where id = $course_id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $course_title = $$row{'name'};
    return ($course_title);
}
sub edit_course {
    my ($r, $course_id) = @_;
    my $qry;
    my $sth;
    my $output;
    my $checked;
    $qry = "select name, description, published from courses where id = $course_id";
    $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    my $name = $$row{'name'};
    my $description = $$row{'description'};
    my $published = $$row{'published'};
    if ($published) {
        $checked = ' checked="checked" ';
    }
    $output = <<END_HTML;
    <div class="miniCourseForm">
    
    <form method="post" action="editor">
    <fieldset><legend>Edit Existing Course</legend>
    <label>Course Name:
    <input name="name" type="text" style="width: 500px" value="$name" /></label>
    <label>Course Description:
    <textarea name="description" rows="8" style="width: 500px" >$description</textarea></label>
    <label>Publish: (Make Course Available)
    <input type=checkbox name="published" $checked value="1" /></label>
    <input class="redButton" name="updatecourse" type="submit" value="Save Changes" />
    </fieldset>
END_HTML
    my %fields = ('menu'=>'courses',
                    'submenu'=>'existing',
                    'action'=>'updatecourse',
                    'courseid'=>$course_id);
    $r->print($output);
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
    $r->print('</div>');
    return();
}
sub course_only_resource_form {
    my ($r) = @_;
    my $course_id = $r->param('courseid');
    my $course_title = &get_course_title($course_id);
    $r->print('<div class="uploadCourseOnlyForm">');
    $r->print('Adding resource for <strong>'.$course_title.'</strong>');
    my %fields = ('courseid'=>$course_id,
                  'menu'=>'courses',
                  'submenu'=>'build',
                  'target'=>'minicourse',
                  'action'=>'insertcourseonlyresource'
                );
    $r->print('<form method="post" action="" ENCTYPE="multipart/form-data">');
    $r->print('<fieldset>');
    $r->print('<label>Resource Name</label><input type="text" name="name" /><br />');
    $r->print('<label>Time Commitment</label>'.&time_commitment_select().'<br />');
    $r->print('<label>Intended Use</label>'.&intended_use_select().'<br />');
    $r->print('<label>URL (only if web resource)</label><input type="text" name="location" /><br />');
    $r->print('<label>File to Upload</label><input type="file" name="resource" /><br />');
    my $types = &get_resource_types();
    my @options = ();
    foreach my $type (@$types) {
        push @options, {($type=>$type)};
    }
    $r->print(&build_select("type",\@options,undef));
    
    $r->print('<input type="submit" value="Upload Course Only Resource" name="insertcourseonlyresource" />');
    $r->print('</fieldset>');
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>');
    $r->print('</div>');
    return('ok');
}
sub dynamic_css {
    my ($r) = @_;
    my $output;
    my %properties;
    $output .= &styleOpen();
    %properties = ('font-family'=>'Arial, Helvetica, sans-serif',
                    'font-size'=>'19px',
                    'color'=>'red',
                    'border-color'=>'black',
                    'border-width'=>'1px',
                    'border-style'=>'solid',
                    'background-color'=>'#eeeeee',
                    'padding'=>'10px');
    $output .= &cssStyle('div', 'class', 'errorMessage', \%properties,undef);
    # all of the menu styles first
    %properties = ('font-family'=>'Arial, Helvetica, sans-serif',
                   'font-size'=>'11px',
                   'text-align'=>'left',
                   'margin-top'=>'0px',
                   'margin-right'=>'auto',
                   'margin-bottom'=>'0px',
                   'margin-left'=>'auto',
                   'width'=>'1090px',
                   'padding'=>'0px',
                  'height'=>'40px',
                  'color'=>'#333333');
    $output .= &cssStyle('div', 'class', 'tabNavWrapper', \%properties,undef);
    %properties = ('margin'=>'0px',
                'padding'=>'0px',
                'font-family'=>'Arial, Helvetica, sans-serif',
                'font-size'=>'12px',
                'color'=>'#333333',
                'height'=>'20px',
                'display'=>'block',
                'width'=>'1090px');
    $output .= &cssStyle('div', 'class', 'tabTopContainer', \%properties,undef);    
    %properties = ('margin'=>'0px',
                'padding'=>'0px',
                'font-family'=>'Arial, Helvetica, sans-serif',
                'font-size'=>'12px',
                'color'=>'#333333',
                'height'=>'20px',
                'background'=>'white',
                'display'=>'block',
                'width'=>'1090px');
    $output .= &cssStyle('div', 'class', 'tabBottomContainer', \%properties,undef);    
    %properties = ('width'=>'10em',
                   'float'=>'left',
                   'padding'=>'0px',
                   'border-width'=>'1px',
                   'border-style'=>'solid',
                   'border-bottom-color'=>'black',
                   'border-left-color'=>'#999999',
                   'border-right-color'=>'#999999',
                   'border-top-color'=>'#999999',
                  'height'=>'18px',
                  'color'=>'black',
                  'display'=>'block',
                  'background-color'=>'#cccccc');
    $output .= &cssStyle('div', 'class', 'tabTop', \%properties,undef);
    %properties = ('width'=>'100%',
                  'height'=>'16px',
                  'color'=>'green',
                  'text-decoration'=>'none',
                  'display'=>'block',
                  'background-color'=>'#cccccc');
    $output .= &cssStyle('div', 'class', 'tabTop', \%properties, 'a');
    %properties = ('width'=>'100%',
                   'float'=>'left',
                   'height'=>'18px',
                   'width'=>'10em',
                   'border-width'=>'1px',
                   'border-top-color'=>'black',
                   'border-left-color'=>'black',
                   'border-right-color'=>'black',
                   'border-style'=>'solid',
                   'border-bottom-color'=>'white',
                   'display'=>'block');
    $output .= &cssStyle('div', 'class', 'tabTopActive', \%properties,undef);
    %properties = ( 'width'=>'100%',
                    'height'=>'16px',
                    'color'=>'green',
                    'display'=>'block',
                    'text-decoration'=>'none',
                    'background-color'=>'#ffffff');
    $output .= &cssStyle('div', 'class', 'tabTopActive', \%properties, 'a');
    %properties = ('background-color'=>'#eeeeee');
    $output .= &cssStyle('div', 'class', 'tabTop', \%properties, 'a:hover');
    %properties = ( 'float'=>'left',
                    'display'=>'block',
                    'color'=>'#ccc',
                    'border-color'=>'#555',
                    'border-right-width'=>'1px',
                    'border-right-style'=>'dotted',
                    'border-right-color'=>'#555',
                    'height'=>'18px',
                    'width'=>'100px');
    $output .= &cssStyle('div', 'class', 'tabBottom', \%properties, undef);
    %properties = ( 'color'=>'#dddddd',
                    'display'=>'block',
                    'height'=>'100%',
                    'width'=>'100%',
                    'text-decoration'=>'none');
    $output .= &cssStyle('div', 'class', 'tabBottom', \%properties, 'a');
    %properties = ('color'=>'black');
    $output .= &cssStyle('div', 'class', 'tabBottom', \%properties, 'a:hover');
    %properties = ( 'float'=>'left',
                    'display'=>'block',
                    'color'=>'black',
                    'border-color'=>'#555',
                    'border-right-width'=>'1px',
                    'border-right-style'=>'dotted',
                    'border-right-color'=>'#555',
                    'height'=>'18px',
                    'width'=>'100px');
    $output .= &cssStyle('div', 'class', 'tabBottomActive', \%properties, undef);
    %properties = ('color'=>'black',
                'text-decoration'=>'none',
                'float'=>'left',
                'height'=>'18px',
                'width'=>'100%');
    $output .= &cssStyle('div', 'class', 'tabBottomActive', \%properties, 'a');
    %properties = ('border'=>'none');
    $output .= &cssStyle('div', 'class', 'tabBottomContainer:last-child', \%properties, 'div');
    %properties = ('float'=>'left',
                    'width'=>'4px',
                    'height'=>'20px',
                    'display'=>'block',
                    'border-style'=>'solid',
                    'border-left-width'=>'0px',
                    'border-right-width'=>'0px',
                    'border-top-width'=>'0px',
                    'border-bottom-width'=>'1px',
                    'border-bottom-color'=>'black');
    $output .= &cssStyle('div', 'class', 'tabTopSeparator', \%properties, undef);
    %properties = ('float'=>'left',
                    'height'=>'20px',
                    'display'=>'block',
                    'border-style'=>'solid',
                    'border-left-width'=>'0px',
                    'border-right-width'=>'0px',
                    'border-top-width'=>'0px',
                    'border-bottom-width'=>'1px',
                    'border-bottom-color'=>'black');
    $output .= &cssStyle('div', 'class', 'tabTopLineRight', \%properties, undef);
    
    # some course building styles
    %properties = ('float'=>'left',
                    'display'=>'block',
                    'width'=>'600px',
                    'margin-left'=>'10px');    
    $output .= &cssStyle('div', 'class', 'showCourseSegments', \%properties, undef);
    %properties = ('display'=>'block',
                    'border-style'=>'solid',
                    'border-width'=>'1px 0px 0px',
                    'border-color'=>'black');    
    $output .= &cssStyle('div', 'class', 'showSegments', \%properties, undef);
    %properties = ('height'=>'20px',
                    'text-align'=>'left',
                    'display'=>'block',
                    'font-weight'=>'bold',
                    'color'=>'#111111',
                    'background'=>'#efeeee',
                    'padding-top'=>'5px',
                    'padding-left'=>'5px',
                    'border-width'=>'0px');    
    $output .= &cssStyle('div', 'class', 'showSegmentsTitle', \%properties, undef);
    %properties = ('display'=>'block',
                    'border-style'=>'solid',
                    'border-width'=>'1px',
                    'border-left-width'=>'1px',
                    'border-color'=>'black',
                    'width'=>'370px',
                    'margin-left'=>'0px',
                    'padding'=>'0px');
    $output .= &cssStyle('div', 'class', 'coursesContainer', \%properties, undef);
    %properties = ('display'=>'block',
                    'width'=>'100%',
                    'border-width'=>'0px 0px 1px',
                    'border-style'=>'solid',
                    'border-color'=>'black',
                    'height'=>'24px',
                    'text-align'=>'left',
                    'margin'=>'0px',
                    'padding'=>'0px');
    $output .= &cssStyle('div', 'class', 'controller', \%properties, undef);
    %properties = ('display'=>'none',
                    'width'=>'100%',
                    'float'=>'none',
                    'min-height'=>'24px',
                    'border-width'=>'0px 0px 1px',
                    'border-style'=>'solid',
                    'border-color'=>'black',
                    'text-align'=>'left',
                    'margin'=>'0px',
                    'padding'=>'0px');
    $output .= &cssStyle('div', 'class', 'collapser', \%properties, undef);
    %properties = ('display'=>'block',
                    'float'=>'left',
                    'text-align'=>'center',
                    'width'=>'20px',
                    'height'=>'20px',
                    'padding-top'=>'4px');
    $output .= &cssStyle('div', 'class', 'iconSpacer', \%properties, undef);
    %properties = ('display'=>'block',
                    'cursor'=>'pointer',
                    'float'=>'left',
                    'text-align'=>'center',
                    'width'=>'20px',
                    'height'=>'20px',
                    'padding-top'=>'4px');
    $output .= &cssStyle('div', 'class', 'arrowSpacer', \%properties, undef);
    %properties = ('display'=>'block',
                    'float'=>'left',
                    'text-align'=>'left',
                    'width'=>'75%',
                    'height'=>'20px',
                    'padding-top'=>'4px');
    $output .= &cssStyle('div', 'class', 'segmentSpacer', \%properties, undef);
    %properties = ('display'=>'none',
                    'position'=>'absolute',
                    'top'=>'20px',
                    'left'=>'20px',
                    'text-align'=>'left',
                    'width'=>'450px',
                    'height'=>'300px',
                    'padding'=>'0px');
    $output .= &cssStyle('div', 'class', 'popUpForm', \%properties, undef);
    %properties = ('display'=>'none',
                    'border-bottom-style'=>'solid',
                    'border-bottom-width'=>'1px',
                    'border-bottom-color'=>'black',
                    'text-align'=>'left',
                    'padding-left'=>'5px',
                    'width'=>'595px',
                    'min-height'=>'20px',
                    'padding'=>'0px');
    $output .= &cssStyle('div', 'class', 'showDetailsRow', \%properties, undef);
    %properties = ('display'=>'block',
                    'width'=>'60px',
                    'height'=>'20px',
                    'text-align'=>'center',
                    'float'=>'right',
                    'padding-top'=>'4px');
    $output .= &cssStyle('div', 'class', 'deleteLinkSpace', \%properties, undef);
    %properties = ('display'=>'block',
                    'width'=>'50px',
                    'height'=>'20px',
                    'text-align'=>'center',
                    'float'=>'left',
                    'padding-top'=>'4px');
    $output .= &cssStyle('div', 'class', 'editLinkSpace', \%properties, undef);
    if ($env{'menu'} eq 'courses' && $env{'submenu'} eq 'build') {
        my $fullWidth = 600;
        my $fullHeight = 145;
        my $optionWidth = 100;
        my $optionsContainerHeight = 26;
        my $optionHeight = $optionsContainerHeight;
        %properties = ('width'=>$fullWidth.'px',
                      'border-width'=>'1px',
                      'border-style'=>'solid',
                      'border-color'=>'black',
                      'padding-bottom'=>'5px',
                      'margin-top'=>'20px',
                      'margin-left'=>'0px',
                      'margin-bottom'=>'5px',
                      'background-color'=>'#ffeeee');
        $output .= &cssStyle('div', 'class', 'courseBuildContainer', \%properties);
        %properties = ('width'=>'140px',
                      'height'=>'100%',
                      'cursor'=>'pointer',
                      'float'=>'left');
        $output .= &cssStyle('div', 'class', 'optionsContainer', \%properties);
        %properties = ('width'=>'100%',
                      'height'=>$optionsContainerHeight.'px',
                      'border-color'=>'black',
                      'border-style'=>'solid',
                      'border-left-width'=>'0px',
                      'border-right-width'=>'0px',
                      'border-top-color'=>'black',
                      'border-top-width'=>'1px',
                      'border-bottom-width'=>'1px');
        $output .= &cssStyle('div', 'class', 'resourceSelectorContainer', \%properties);
        %properties = ('width'=>'100%',
                      'padding-top'=>'0px',
                      'display'=>'none');
        $output .= &cssStyle('div', 'class', 'optionContainer', \%properties);
        %properties = ('text-align'=>'left',
                        'padding-bottom'=>'5px',
                        'padding-left'=>'3px',
                        'padding-top'=>'5px');
        $output .= &cssStyle('div', 'class', 'segmentEditTitle', \%properties);
    }
    $output .= &styleClose();
    return($output);
}
sub build_course {
    my($r) = @_;
    my $subject;
    my $profile = &get_user_profile();
    $subject = $$profile{'subject'};
    # first, allow the addition of a segment to the sequence
    my $course_title = &get_course_title($env{'course_id'});
    $r->print(qq~
<script type="text/javascript">
<!--
var vpdStyle;
var courseOnlyStyle;
var vpdMessageStyle;
var courseOnlyStyle;
var courseOnlyMessageStyle;
var buildingCourse = 'true';
function buildCourseInitialize() {
    vpdStyle = document.getElementById("resource").style;
    selectorRowStyle = document.getElementById("vpdMessage").style;
    courseOnlyStyle = document.getElementById("courseonlyresource").style;
    vpdMessageStyle = document.getElementById("vpdOptionContainer").style;
    courseOnlyMessageStyle = document.getElementById("courseOnlyOptionContainer").style;
    selectorRowStyle.backgroundColor = "#ffeeee";
    vpdStyle.display = "block";
    courseOnlyStyle.display = "none";
    vpdMessageStyle.display = "block";
    courseOnlyMessageStyle.display ="none";
}
function vpdOptionClick()
{
    if (vpdStyle.display == "none") {
        vpdStyle.display = "block";
        courseOnlyStyle.display = "none";
        vpdMessageStyle.display = "block";
        selectorRowStyle.backgroundColor = "#ffeeee";
        courseOnlyMessageStyle.display ="none";
        document.forms[0].courseOnlyResource.selectedIndex = 0;
    } else {
        vpdStyle.display = "none";
        selectorRowStyle.backgroundColor = "#eeeeff";
        courseOnlyStyle.display = "block";
        vpdMessageStyle.display = "none";
        courseOnlyMessageStyle.display ="block";
        document.forms[0].resource.selectedIndex = 0;
    }
}
function optionClick()
{
    if (vpdStyle.display == "none") {
        vpdStyle.display = "block";
        courseOnlyStyle.display = "none";
        vpdMessageStyle.display = "block";
        selectorRowStyle.backgroundColor = "#ffeeee";
        courseOnlyMessageStyle.display ="none";
        document.forms[0].courseOnlyResource.selectedIndex = 0;
    } else {
        vpdStyle.display = "none";
        selectorRowStyle.backgroundColor = "#eeeeff";
        courseOnlyStyle.display = "block";
        vpdMessageStyle.display = "none";
        courseOnlyMessageStyle.display ="block";
        document.forms[0].resource.selectedIndex = 0;
    }
}

function courseOnlyOptionClick()
{
    if (vpdStyle.display == "none") {
        vpdStyle.display = "block";
        selectorRowStyle.backgroundColor = "#ffeeee";
        courseOnlyStyle.display = "none";
        vpdMessageStyle.display = "block";
        courseOnlyMessageStyle.display ="none";
        
    } else {
        vpdStyle.display = "none";
        selectorRowStyle.backgroundColor = "#eeeeff";
        courseOnlyStyle.display = "block";
        vpdMessageStyle.display = "none";
        courseOnlyMessageStyle.display ="block";
    }
}
</script>
~);


    $r->print('<div class="courseBuildContainer" >');
    $r->print('<div class="segmentEditTitle">Adding/Editing segments for course: <b>'.$course_title.'</b></div>');
    my %fields = ('action'=>'addcoursesegment',
                'menu'=>'courses',
                'submenu'=>'build',
                'courseid'=>$env{'course_id'});
    $r->print('<form method="post" action="editor">');
    my $resource_arrayref = &get_resources_select_all($subject);
    unshift (@$resource_arrayref,{'Select VPD Resource'=>'0'});
    $r->print('<div class="resourceSelectorContainer" id="vpdMessage">'."\n");
    $r->print('<div onclick="optionClick();" class="optionsContainer" id="vpdOptionSelector">'."\n");
    $r->print('<div class="optionContainer" id="vpdOptionContainer">'."\n");
    $r->print('<div style="float: left;margin-left: 3px;"><img src="../_images/exchange3.png" /></div>');
    $r->print('<div style="float: left;margin-left: 3px;margin-top: 4px;"><b>VPD</b></div>'."\n");
    $r->print('</div>'); # closing first optionContainer
    $r->print('<div style="display: none;" class="optionContainer" id="courseOnlyOptionContainer">'."\n");
    $r->print('<div style="float: left;margin-left: 3px;"><img src="../_images/exchange3.png" /></div>'."\n");
    $r->print('<div style="float: left;margin-left: 3px;margin-top: 4px;"><b>Course Only</b></div>'."\n");
    $r->print('</div>'."\n"); #close second option container
    $r->print('</div>'."\n"); #close options container
    $r->print('<div style="margin-top: 3px;">');
    $r->print(&build_select('resource',$resource_arrayref,undef,undef,460));
    $r->print('</div>');
    my $course_resource_arrayref = &get_course_only_resources($env{'course_id'});
    unshift (@$course_resource_arrayref,{'Select Course Only Resource'=>'0'});
    $r->print('<div style="margin-top: 3px;">');
    $r->print(&build_select('courseonlyresource',$course_resource_arrayref,undef,undef,460));
    $r->print('</div>');
    $r->print('</div>'."\n"); # close resourceSelectorContainer
    $r->print('<div style="margin-top: 5px;">'); # drop the input field
    $r->print('<label>Segment Introduction:<textarea rows="2" cols="50" name="organizer"></textarea></label>');
    $r->print('</div>'."\n"); # close textarea containing div
    $r->print('<br /><label>Insert Segment Number (Leave blank to add segment to end of list.)<input type="text" name="segmentnum" size="4" /></label><br />'."\n");
    $r->print('<input type="submit" value="Add Selected Resource to Course" />'."\n");
    $r->print(&hidden_fields(\%fields));
    $r->print('</form>'."\n");
    $r->print('</div>'."\n");
    return('ok');
}
sub mini_course {
    my ($r) = @_;
    my $subject;
    my $profile = &get_user_profile();
    my $content;
    my $error_message;
    my $resource_id;
    # here only if $env{'menu'} eq 'courses'
    $subject = $$profile{'subject'};
    if ($env{'action'} eq 'insertcourseonlyresource') {
        my $location;
        if (!$r->param('location')) {
            $location = $r->param('resource');
        } else {
            $location = $r->param('location');
        }
        if ($r->param('title')) {
            my %fields = ('title'=>&fix_quotes($r->param('title')),
                          'location'=>&fix_quotes($r->param('location')),
                          'author'=>&fix_quotes($r->param('author')),
                          'subject'=>&fix_quotes($r->param('subject')),
                          'comments'=>&fix_quotes($r->param('comments')),
                          'time_commitment'=>$r->param('timecommitment'),
                          'intended_use'=>$r->param('intendeduse'),
                          'type'=>&fix_quotes($r->param('type')),
                          'course_id'=>$env{'course_id'}
                          );
            $resource_id = &save_record('resources',\%fields,'id');
        } else {
            $error_message = "Unable to add resource with no name.";
        }
        if ($r->param('resource')) {
            &handle_upload($r, $resource_id, 'course');
        }
    } elsif ($env{'action'} eq 'addcoursesegment') {
        my $segment_type;
        my $resource_id;
        if (!($r->param('courseonlyresource') eq '0')) {
            $resource_id = $r->param('courseonlyresource');
            $segment_type = 'CO';
        } else {
            $resource_id = $r->param('resource');
            $segment_type = 'VPD';
        }
        my $position = $r->param('segmentnum');
        &add_course_segment($env{'course_id'}, $resource_id, $position,$segment_type,$r->param('organizer'));
    } elsif  ($env{'action'} eq 'removesegment') {
        &remove_course_segment($r->param('segment'));
    } elsif ($env{'action'} eq 'submitnewcourse') {
        my $published = 0;
        if ($r->param('published')) {
            $published = 1;
        }
        my %fields = ('name'=>&fix_quotes($r->param('name')),
                      'description'=>&fix_quotes($r->param('description')),
                      'published'=>$published,
                      'author'=>$env{'user_id'}
                        );
        $env{'course_id'} = &save_record('courses',\%fields,1);
    } elsif ($env{'action'} eq 'deletecourse') {
            my $delete_return_msg = &delete_course($r->param('courseid'));
            if (!($delete_return_msg eq 'Course Deleted')) {
                $r->print($delete_return_msg);
            }
    } elsif ($env{'action'} eq 'updatecourse') {
        my $name = &fix_quotes($r->param('name'));
        my $description = &fix_quotes($r->param('description'));
        my $published = &fix_quotes($r->param('published'));
        my $qry = "update courses set name = $name, description = $description, published = $published
                    WHERE id = $env{'course_id'}";
        $env{'dbh'}->do($qry);
    } elsif ($env{'action'} eq 'updateorganizer') {
        my $organizer = &fix_quotes($r->param('organizer'));
        my $segment_id = $r->param('segmentid');
        my $qry = "update course_sequence set organizer = $organizer
                    WHERE id = $segment_id";
        $env{'dbh'}->do($qry);
    } elsif ($env{'action'} eq 'updatecourseonly') {
        &update_resource($r);
    }
    if ($error_message) {
        $r->print('<div class="errorMessage">'.$error_message.'</div>');
    }
    if ($env{'submenu'} eq 'existing') {
        $content .= &Apache::Promse::show_courses($r);
        $r->print($content);
    } elsif ($env{'submenu'} eq 'add') {
        $r->print(&Apache::Promse::new_mini_course_form($r));
    } elsif ($env{'submenu'} eq 'edit') {
        &edit_course($r, $env{'course_id'});
    } elsif ($env{'submenu'} eq 'build') {
        $r->print('<div style="margin-left: 10px;">');
        &build_course($r);
        $r->print(&show_course_segments($env{'course_id'},'edit'));
        $r->print('</div>');
    } elsif ($env{'submenu'} eq 'addcourseonlyresource') {
        #&course_only_resource_form($r);
        &upload_resource_form($r);
    } elsif ($env{'submenu'} eq 'editcourseonly') {
        my $resource_id = $r->param('resourceid');
        my $qry = "select * from resources where id = $resource_id";
        my $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $resource_hashref = $sth->fetchrow_hashref;
        &update_resource_form($r,$resource_hashref);
    }
}

sub cssStyle {
    # $type is class or id
    # ($tag, $type, $name, $height, $width, $background_color,
    # $properties is hash ref with keys like above and values set as desired
    my ($tag, $type, $name, $properties, $child_element) = @_;
    $child_element = $child_element?$child_element:"";
    my $output;
    $output .= "$tag.$name $child_element {\n";
    foreach my $key (keys(%$properties)) {
        $output .= $key.': '.$$properties{$key}.";\n";
    }
    $output .= "}\n";
    return($output);
}
sub styleOpen {
    my $output;
    $output .= '<style type="text/css">';
    return($output);
}
sub styleClose {
    my $output;
    $output .= '</style>';
    return($output);
}


sub new_mini_course_form {
    my ($r) = @_;
    my %fields;
    my $output;
    $output .= '<div class="miniCourseForm">';
    $output .= '<form method="post" action="editor">'."\n";
    $output .= "<fieldset>\n";
    $output .= "<legend>New Mini-Course Details</legend>\n";
    $output .= '<label>Course Name:</label><input type="text" maxlength="100" size="35" name="name"/>'."\n";
    $output .= '<label>Course Description</label><textarea rows="8" cols="30" name="description" ></textarea>'."\n";
    $output .= '<label>Publish<input type="checkbox" name="published" /></label>'."\n";
    $output .= '<input class="redButton" type="submit" value="Add Mini-Course" />'."\n";
    %fields = ('target'=>'minicourse',
                'menu' =>'courses',
                'submenu' => 'existing',
                'action'=>'submitnewcourse');
    $output .= "</fieldset>\n";
    $output .= &hidden_fields(\%fields);
    $output .= "</form>\n";
    $output .= '</div>';
    return($output);
}
sub show_course_only_resources {
    my ($course_id, $mode) = @_;
    my $output;
    my $courses = &get_course_only_resources($course_id);
    foreach my $course(@$courses) {
        $output .= $$course{'name'};
    }
    return($output);
}
sub get_segment {
    my ($segment_id) = @_;
    my $qry = "select * from course_sequence where id = $segment_id";
    my $sth = $env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return($row);
}
sub edit_organizer_form {
    my ($segment_id) = @_;
    my $output;
    my $segment = &get_segment($segment_id);
    my $organizer = $$segment{'organizer'};
    my %fields = ('menu'=>'courses',
                    'submenu'=>'build',
                    'action'=>'updateorganizer',
                    'courseid'=>$env{'course_id'},
                    'segmentid'=>$segment_id);
    $output .= '<form method="post" action="">';
    $output .= '<textarea name="organizer" rows="3" cols="60">';
    $output .= $organizer;
    $output .= '</textarea>';
    $output .= '<input type="submit" value="Update Organizer" />';
    $output .= &hidden_fields(\%fields);
    $output .= '</form>';
    return($output);
}
sub show_course_segments {
    my ($course_id, $mode) = @_;
    my %fields;
    my $output;
    my $course_title = &get_course_title($course_id);
    my $course_segments = &get_course_segments($course_id);
    my $segment_number = 1;
    my $upload_dir_url = "../resources";
    my $url;
#    $output .= qq~
#        <script type="text/javascript">
#        function infoReveal(segmentId, segmentNum) {
#           var arrowTest = /BannerRightArrow/;
#           var arrowImage = document.getElementById(segmentId + 'Image' + segmentNum);
#           var divCollapse = document.getElementById(segmentId + 'Collapser' + segmentNum);
#           var divControl = document.getElementById(segmentId + 'Controller' + segmentNum);
#           var divContainer = document.getElementById(segmentId + 'Container' + segmentNum);
#            if (arrowTest.test(arrowImage.src)) {
#                arrowImage.src = '../_images/BannerDnArrow.gif';
#                divControl.style.borderBottom = '0px';
#                divContainer.style.borderBottom = '1px black solid';
#                divCollapse.style.display = 'block';
#            } else {
#                divControl.style.borderBottom = '1px black solid';
#                divContainer.style.borderBottom = '0px';
#                arrowImage.src = '../_images/BannerRightArrow.gif';
#                divCollapse.style.display = 'none';
#            }
#        }
#
#        </script>
#        ~;
        
    if ($mode eq 'edit') {
        my $icon;
        my $image_alt;
        my $segment_style;
        $output .= '<div id="coursescontainer" class="coursesContainer" style="width: 600px;">'."\n";
        $output .= '<div class="showSegmentsTitle">';
        $output .= $course_title;
        $output .= '</div>';
        $output .= '<div class="showSegments">'."\n";
        foreach my $segment(@$course_segments) {
            if ($$segment{'type'} eq 'Video') {
                $icon = "../images/resourcelist_video.png";
                $image_alt = ' alt="Video" ';
            } elsif ($$segment{'type'} eq 'Web URL') {
                $icon = "../images/resourcelist_web.png";
                $image_alt = ' alt="Web" ';
            } elsif ($$segment{'type'} eq 'Video/Slide') {
                $icon = "../images/resourcelist_video.png";
                $image_alt = ' alt="Video/Slide" ';
            } else  {
                $icon = "../images/resourcelist_doc.png";
                $image_alt = ' alt="Document" ';
            }
            if ($$segment{'resource_type'} eq 'CO') {
                $segment_style = ' style="background-color: #f6f6ff;" ';
            } else {
                $segment_style = ' style="background-color: #f6fff6;" ';
            }
            $output .= '<div class="revealContainer" id="segmentContainer'.$segment_number.'" >'."\n";
            $output .= '<div'.$segment_style.' class="controller" id="segmentController'.$segment_number.'" >'."\n";
            $output .= '<div class="arrowSpacer" onclick="infoReveal(\'segment\','."$segment_number".');">';
            $output .= '<img id="segmentImage'.$segment_number.'"  src="../_images/BannerRightArrow.gif" width="7" height="4" alt="" /></div>'."\n";
            $output .= '<div class="iconSpacer"><img src="'.$icon.'"'.$image_alt.' /></div>'."\n";
            $output .= '<div class="segmentSpacer">'."\n";
            $output .= $segment_number.". ".$$segment{'title'};
            $output .= '</div>'."\n"; # close segment spacer
            if ($$segment{'resource_type'} eq 'CO') {
                $output .= '<div class="editLinkSpace">';
                %fields = ('menu'=>'courses',
                            'submenu'=>'editcourseonly',
                            'resourceid'=>$$segment{'resource_id'},
                            'courseid'=>$course_id,
                            'token'=>$env{'token'}
                            );
                $url = &build_url('editor',\%fields);
                $output .= '<a href="'.$url.'" >Edit</a>'."\n";
                $output .= '</div>'."\n";
            }
            $output .= '<div class="deleteLinkSpace">';
            %fields = ('menu'=>'courses',
                        'submenu'=>'build',
                        'resourceid'=>$$segment{'resource_id'},
                        'action'=>'removesegment',
                        'courseid'=>$course_id,
                        'token'=>$env{'token'},
                        'segment'=>$$segment{'id'},
                        );
            $url = &build_url('editor',\%fields);
            $output .= '<a href="'.$url.'" onclick="javascript:return confirm(\'Delete this course segment?\')">Remove</a>'."\n";
            $output .= '</div>'."\n"; # end delete link space
            $output .= '</div>'."\n"; # end the controller
            $output .= '<div class="collapser" id="segmentCollapser'.$segment_number.'">'."\n";
            my $organizer_text;
            my $comments_text;
            if ($$segment{'organizer'}) {
                $organizer_text = &mt($$segment{'organizer'});
            } else {
                $organizer_text = "There is no organizer text for this course segment.";
            }
            
            
            $output .= '<div class="revealContainer" id="organizerContainer'.$segment_number.'">'."\n"; # start revealer for the organizer
            
            $output .= '<div class="controller" id="organizerController'.$segment_number.'">';
            $output .= '<div class="arrowSpacer" id="organizerArrow'.$segment_number.'" onclick="infoReveal(\'organizer\','."$segment_number".');">';
            $output .= '<img id="organizerImage'.$segment_number.'" src="../_images/BannerRightArrow.gif" width="7" height="4" alt="" />';
            $output .= '</div>'."\n"; # close the arrowSpacer div
            $output .= '<div style="float: left;" >Organizer</div>'."\n";
            $output .= '</div>'."\n"; # close the controller div
            
            $output .= '<div style="display: none;" class="collapser" id="organizerCollapser'.$segment_number.'">';
            $output .= '<div>'.$organizer_text.'</div>'."\n";
            $output .= '</div>'."\n"; # end the collapser for organizer
            
            $output .= '</div>'."\n"; # end the revealContainer for organizer
            
            if ($$segment{'comments'}) {
                $comments_text = &mt($$segment{'comments'});
            } else {
                $comments_text = "There are no comments for this course resource.";
            }
            $output .= '<div class="revealContainer" id="editContainer'.$segment_number.'">'."\n"; # start revealer for the edit
            $output .= '<div class="controller" id="editController'.$segment_number.'">';
            $output .= '<div class="arrowSpacer" id="editArrow'.$segment_number.'" onclick="infoReveal(\'edit\','."$segment_number".');">';
            $output .= '<img id="editImage'.$segment_number.'" src="../_images/BannerRightArrow.gif" width="7" height="4" alt="" />';
            $output .= '</div>'."\n"; # close arrowSpacer div
            $output .= '<div style="float: left;"  >Edit Organizer</div>';
            $output .= '</div>'."\n"; # close the controller div
            $output .= '<div style="display: none;" class="collapser" id="editCollapser'.$segment_number.'">';
            $output .= '<div>'.&edit_organizer_form($$segment{'id'}).'</div>';
            $output .= '</div>'."\n"; # close the collapser
            $output .= '</div>'."\n"; # end the revealContainer for edit
            
            $output .= '<div class="revealContainer" id="commentsContainer'.$segment_number.'">'."\n"; # start revealer for the comments
            $output .= '<div class="controller" id="commentsController'.$segment_number.'">';
            $output .= '<div class="arrowSpacer" id="commentsArrow'.$segment_number.'" onclick="infoReveal(\'comments\','."$segment_number".');"><img id="commentsImage'.$segment_number.'" src="../_images/BannerRightArrow.gif" width="7" height="4" alt="" /></div>'."\n";
            $output .= '<div  style="float: left;" >Resource Comments</div>';
            $output .= '</div>'."\n";
            $output .= '<div style="display: none;" class="collapser" id="commentsCollapser'.$segment_number.'">';
            $output .= '<div>'.$comments_text.'</div>';
            $output .= '</div>'."\n";
            $output .= '</div>'."\n"; # end revealContainer for comments
            
            $output .= "</div>\n";
            $output .= "</div>\n";
            $segment_number ++;
        }
        $output .= "</div>\n";
        $output .= "</div>\n";
    } elsif ($mode eq 'study') {
        my $icon;
        my $last_segment = &get_last_segment($env{'user_id'},$course_id);
        $output .= '<div class="coursesContainer" style="margin-top: 20px;">'."\n";
        $output .= '<div class="showSegmentsTitle">'."\n";
        $output .= $course_title;
        $output .= '</div>'."\n";
        $output .= '<div class="showSegments">'."\n";
        my $links_one_more = 0;
        my $links_done = 0;
        my $row_style_color;
        foreach my $segment(@$course_segments) {
            my $segment_type_output;
            $row_style_color = $links_done?' style="background-color: #ffeeee; color: #cccccc;"':' style="background-color: #eeffee;"';
            $output .= '<div class="revealContainer" id="segmentContainer'.$segment_number.'">'."\n";
            $output .= '<div class="controller" '.$row_style_color.'  id="segmentController'.$segment_number.'">'."\n";
            $output .= '<div class="arrowSpacer" onclick="infoReveal(\'segment\','."$segment_number".');">'."\n";
            $output .= '<img id="segmentImage'.$segment_number.'"  src="../_images/BannerRightArrow.gif" width="7" height="4" alt="" /></div>'."\n";
            if ($$segment{'type'} eq 'Video') {
                $icon = "../images/resourcelist_video.png";
                $segment_type_output .= '<div class="iconSpacer"><img src="'.$icon.'" alt="Video" /></div>'."\n";
                if (!$links_done) {
                    %fields = ('token'=>$env{'token'},
                            'target'=>'minicourse',
                            'resource'=>'redirect',
                            'courseid'=>$course_id,
                            'segment'=>$$segment{'id'},
                            'resourceid'=>$$segment{'resource_id'},
                            'url'=> &mt($$segment{'location'}));
                    $url = &build_url('apprentice',\%fields);        
                    $segment_type_output .= '<div style="float: left;">'."\n";
                    $segment_type_output .= '<a class="course" href="'.$url.'">';
                    $segment_type_output .= &mt($$segment{'title'})."</a><br />\n";
                } else {
                    $segment_type_output .= '<div class="segmentSpacer">'."\n";
                    $segment_type_output .= &mt($$segment{'title'})."\n";
                }
            } elsif ($$segment{'type'} eq 'Web URL') {
                $icon = "../images/resourcelist_web.png";
                $segment_type_output .= '<div class="iconSpacer"><img src="'.$icon.'" alt="Web Site" /></div>';
                if (!$links_done) {
                    %fields = ('token'=>$env{'token'},
                            'target'=>'minicourse',
                            'resource'=>'redirect',
                            'courseid'=>$course_id,
                            'segment'=>$$segment{'id'},
                            'resourceid'=>$$segment{'resource_id'},
                            'url'=> &mt($$segment{'location'}));
                    $url = &build_url('apprentice',\%fields);
                    $segment_type_output .= '<div class="segmentSpacer">'."\n";
                    $segment_type_output .= '<a class="course" target="new" href="';
                    $segment_type_output .= $url.'">'.&mt($$segment{'title'}).'</a><br />';
                } else {
                    $segment_type_output .= '<div class="segmentSpacer">'."\n";
                    $segment_type_output .= &mt($$segment{'title'})."<br /> \n";
                }
            } elsif ($$segment{'type'} eq 'Video/Slide') {
                $icon = "../images/resourcelist_video.png";
                $segment_type_output .= '<div class="iconSpacer"><img src="'.$icon.'" alt="Video/Slide" /></div>';
                # create proper link to video/slide (Flash application);
                if (!$links_done) {
                    %fields = ('token'=>$env{'token'},
                            'menu'=>'courses',
                            'action'=>'showvidslide',
                            'courseid'=>$course_id,
                            'resourceid'=>$$segment{'resource_id'},
                            'segment'=>$$segment{'id'},
                            'showname'=>$$segment{'location'},
                            'url'=> &mt($$segment{'location'}));
                    $url = &build_url('apprentice',\%fields);
                    $segment_type_output .= '<div class="segmentSpacer">'."\n";
                    $segment_type_output .= '<a class="course" href="'.$url.'">'.&mt($$segment{'title'}).'</a><br />';
                } else {
                    $segment_type_output .= '<div class="segmentSpacer">'."\n";
                    $segment_type_output .= &mt($$segment{'title'})."<br /> \n";
                }
            } else {
                # here for documents
                $icon = "../images/resourcelist_doc.png";
                $segment_type_output .= '<div class="iconSpacer"><img src="'.$icon.'" alt="Document" /></div>';
                if (!$links_done) {
                    # Need to do a redirect here so we can log course segment completion.
                    # $output .= '<a class="course" target="new" href="'.$upload_dir_url.'/'.&mt_url($$segment{'location'}).'.'.$$segment{'resource_id'}.'">'.&mt($$segment{'title'}).'</a><br />';
                    %fields = ('resource'=>'redirect',
                                'menu'=>'courses',
                                'courseid'=>$env{'course_id'},
                                'segment'=>$$segment{'id'},
                                'token'=>$env{'token'},
                                'location'=>&mt($$segment{'location'}),
                               'resourceid'=>$$segment{'resource_id'});
                    $url = &build_url('apprentice',\%fields);
                    $segment_type_output .= '<div class="segmentSpacer">'."\n";
                    $segment_type_output .= '<a class="course" target="new" href="'.$url.'">'.&mt($$segment{'title'}).'</a><br />';
                } else {
                    $segment_type_output .= '<div class="segmentSpacer">'."\n";
                    $segment_type_output .= &mt($$segment{'title'})."<br /> \n";
                }
            }
            $segment_type_output .= '</div>'."\n"; # close title row
            if (!$links_done) {
                $segment_type_output .= '<div style="float: right;">'."\n";
                %fields = ('token'=>$env{'token'},
                        'target'=>'minicourse',
                        'menu'=>'courses',
                        'submenu'=>'study',
                        'courseid'=>$course_id,
                        'segment'=>$$segment{'id'},
                        'resourceid'=>$$segment{'resource_id'});
                $url = &build_url('apprentice',\%fields);
                $segment_type_output .= '<a href="'.$url.'">Notes</a>'."\n";
                $segment_type_output .= '</div>'."\n";
            }
            # need to test if next resource should be shown as a link
            if ($links_one_more || ($last_segment eq 0) ) {
                $links_done = 1;
            }
            if ($last_segment eq $$segment{'id'}) {
                $links_one_more = 1;
            }
            $output .= $segment_type_output;
            $output .= '</div>'."\n"; # closes the controller
            $output .= '<div id="segmentCollapser'.$segment_number.'" class="collapser">'."\n";
            $output .= '<div style="margin-top: 5px;margin-left: 5px;"><b style="margin-left: 5px;">Organizer: </b>'.&mt($$segment{'organizer'}.'</div>')."\n";;
            $output .= '<div style="margin-top: 5px;margin-left: 5px;margin-bottom: 5px;"><b style="margin-left: 5px;">Summary: </b>'.&mt($$segment{'comments'}.'</div>')."\n";;
            $output .= '</div>'."\n"; # close collapser
            $output .= '</div>'."\n"; # close revealerContainer
            $segment_number ++;
        }
        $output .= '</div>'."\n";
        $output .= '</div>'."\n";
    } else {
        $output = "Must have a mode set.";
    }
    return($output);
}
sub show_courses {
    # may need menu information sent
    my ($r) = @_;
    my $output;
    my $courses_array = &get_courses();
    $output .= qq~
                <script type="text/javascript">
                    function confirmDelete() {
                        confirm("Delete this course?");
                    }
                </script>
    ~;
    $output .= '<div class="coursesContainer" style="margin-top: 20px;margin-left: 20px;width: 600px;">';
    $output .= '<div class="showCoursesTitle">Courses (* = Published)</div>';
    my %fields = ('token'=>$env{'token'},
                'menu'=>'courses',
                'submenu'=>'build',
                'target'=>'minicourse',
                'action'=>'edit');
    foreach my $course (@$courses_array) {
        $fields{'courseid'} = $$course{'id'};
        my $published;
        if ($$course{'published'}) {
            $published = '*';
        } else {
            $published = '';
        }
        my $url = &build_url('editor',\%fields);
        $output .= '<div class="showCoursesRow">'."\n";
        $output .= '<div class="publishedSpace">'."\n";
        $output .= $published;
        $output .= "</div>\n";
        $output .= '<div class="courseTitleSpace">'."\n";
        $output .= '<a class="course" href="'.$url.'">';
        $output .= $$course{'name'}."</a>\n";
        $output .= "</div>\n";
        my %delete_fields = ('token'=>$env{'token'},
                'target'=>'minicourse',
                'menu'=>'courses',
                'submenu'=>'existing',
                'action'=>'deletecourse',
                'courseid'=>$$course{'id'});
        $url = &build_url('editor',\%delete_fields);
        $output .= '<div class="deleteLinkSpace">'."\n";    
        $output .= '<a class="course" href="'.$url.'" onclick="javascript:return confirm(\'Delete this course?\')">Delete</a>';
        $output .= "</div>\n";
        $output .= "</div>\n";
    }
    $output .= '</div>';
    return($output);
}
sub get_last_segment {
    my ($user_id,$course_id) = @_;
    my $segment_id;
    my $qry = "SELECT segment FROM course_user WHERE user_id = $user_id AND course_id = $course_id";
    my $sth = $Apache::Promse::env{'dbh'}->prepare($qry);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $segment_id = $$row{'segment'};
    return ($segment_id);
}
sub course_log_progress {
    my ($r) = @_;
    # Sequence holds list of segments in order. We come here when
    # a user selects a resource in a course sequence. User could be
    # selecting an earlier segment (already viewed). If that's the case
    # we don't want to do anything. If user is looking at a resource
    # in the sequence for the first time, we want to log that segment
    # as looked at (enabling link to subsequent resource).
    my $course_segments = &get_course_segments($r->param('courseid'));
    my $viewed_segment = $r->param('segment');
    my $course_id = $r->param('courseid');
    my $user_id = $env{'user_id'};
    my $last_segment = &get_last_segment($env{'user_id'},$course_id);
    my $current_segment_num = 0;
    my $segment_num = 1;
    my $viewed_segment_num = 0;
    # first find place in sequence of last stored segment
    foreach my $segment(@$course_segments) {
        if ($$segment{'id'} eq $last_segment) {
            $current_segment_num = $segment_num;
        }
        $segment_num ++;
    }
    $segment_num = 1;
    foreach my $segment(@$course_segments) {
        if ($$segment{'id'} eq $viewed_segment) {
            $viewed_segment_num = $segment_num;
        }
        $segment_num ++;
    }
    if (($viewed_segment_num gt $current_segment_num) || ($last_segment eq 0 )) {
        # need to update course_user record
        my $qry = "UPDATE course_user SET segment = $viewed_segment WHERE course_id = $course_id and user_id = $user_id";
       $env{'dbh'}->do($qry);
    }
    return();
}
sub show_user_courses {
    my ($r) = @_;
    my $output;
    my $user_courses = &get_user_courses($env{'user_id'});
    $output .= '<div class="showCourses">'."\n";
    my %fields;
    my $found_courses_flag = 0;
    foreach my $course (@$user_courses) {
        $output .= '<div class="showCoursesRow">'."\n";
        $found_courses_flag = 1;
        %fields = ('token'=>$env{'token'},
                    'menu'=>'courses',
                    'submenu'=>'study',
                    'courseid'=>$$course{'id'}
                    );
        my $url = &build_url('apprentice',\%fields);
        $output .= '<div class="courseTitleSpace">'."\n";
        $output .= $$course{'name'};
        $output .= '</div>'."\n";
        $output .= '<div class="deleteLinkSpace">'."\n";
        $output .= '<a class="course" href="'.$url.'">Study</a>';
        $output .= '</div>'."\n";
        $output .= '</div>'."\n";
    }
    if (!$found_courses_flag) {
        $output = "You have selected no mini-courses.";
    }
    $output .= '</div>'."\n";
    return($output);
}
sub add_user_course {
    my ($r) = @_;
    my $qry;
    my $user_id = $env{'user_id'};
    my $course_id = $r->param('courseid');
    $qry = "insert into course_user (user_id, course_id, segment) values ($user_id, $course_id, 0)";
    $env{'dbh'}->do($qry);
    return();
}
sub show_course_selection {
    my ($r) = @_;
    # routine to allow users to select a course to add to a list of courses taken
    my $output;
    my $courses = &get_courses(1);
    my $user_courses = &get_user_courses($env{'user_id'});
    my %stu_courses;
    for my $row(@$user_courses) {
        $stu_courses{$$row{'id'}} = 1;
    }
    my %fields;
    my $course_list_output;
    my $found_course_flag = 0;
    foreach my $course (@$courses) {
        if (!$stu_courses{$$course{'id'}}) {
            $found_course_flag = 1;
            %fields = ('token'=>$env{'token'},
                        'menu'=>'courses',
                        'submenu'=>'mine',
                        'action'=>'selectcourse',
                        'courseid'=>$$course{'id'}
                        );
            my $url = &build_url('apprentice',\%fields);
            $course_list_output .= $$course{'name'}.'<span class="nav">[<a class="course" href="'.$url.'">Select</a>]</span><br />';
        }
    }
    if ($found_course_flag) {
        $output .= $course_list_output;
    } else {
        $output .= "There are no courses available.";
    }
    return($output);
}
sub get_courses {
    my ($published) = @_;
    my $where_clause;
    if ($published) {
        $where_clause = " WHERE published = 1 ";
    } else {
        $where_clause = "";
    }
    my @courses;
    my $qry = "select id, name, description, published from courses $where_clause order by name";
    my $sth = $Apache::Promse::env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push(@courses, {%$row});
    }
    return(\@courses);
}
sub get_user_courses() {
    my ($user_id) = @_;
    my @courses;
    my $qry = "SELECT id, name, description, published FROM courses t1, course_user t2 
                WHERE t1.id = t2.course_id and t2.user_id = $user_id
                ORDER BY name";
    my $sth = $Apache::Promse::env{'dbh'}->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push(@courses, {%$row});
    }
    return(\@courses);
}
sub curriculum {
    my ($r) = @_;
    my $step = $r->param('step');
    my %hidden_fields;
    $r->print('Build curriculum<br />');
    if ($step eq 1) {
        my $sth = &get_locations();
        $r->print('Select the Location<br />');
        $r->print('<form method="post" action="editor">');
        $r->print('<select name="location">');
        while (my $row = $sth->fetchrow_hashref()) {
            $r->print('<option value="'.$$row{'location_id'}.'">'.$$row{'school'}.'</option>');
        }
        $r->print('</select>');
        $hidden_fields{'target'} = 'curriculum';
        $hidden_fields{'step'} = 2;
        $r->print(&hidden_fields(\%hidden_fields));
        $r->print('<hr align="center" width="100%" />');
        $r->print('<p>&nbsp;<input type="submit" value="Next->">&nbsp;</p>');
        $r->print('</form>');
         
    } elsif ($step eq 2) {
        $r->print('Select the Subject<br />');
        $r->print('<form method="post" action="editor">');
        $r->print('<select name="subject"><option>Math</option><option>Science</option></select>');
        $hidden_fields{'target'} = 'curriculum';
        $hidden_fields{'step'} = 3;
        $hidden_fields{'location'} = $r->param('location');
        $r->print(&hidden_fields(\%hidden_fields));
        $r->print('<hr align="center" width="100%" />');
        $r->print('<p>&nbsp;<input type="submit" value="Next->">&nbsp;</p>');
        $r->print('</form>');
       
    }   elsif ($step eq 3) {
        $r->print('Select the Grade<br />');
        $r->print('<form method="post" action="editor">');
        $r->print('<select name="grade"><option>1</option><option>2</option><option>3</option><option>4</option>');
        $r->print('<option>5</option><option>6</option><option>7</option><option>8</option>');
        $r->print('<option>9</option><option>10</option><option>11</option><option>12</option></select>');
        $hidden_fields{'target'} = 'curriculum';
        $hidden_fields{'step'} = 4;
        $hidden_fields{'location'} = $r->param('location');
        $hidden_fields{'subject'} = $r->param('subject');
        $r->print(&hidden_fields(\%hidden_fields));
        $r->print('<hr align="center" width="100%" />');
        $r->print('<p>&nbsp;<input type="submit" value="Next->">&nbsp;</p>');
        $r->print('</form>');
    }   elsif ($step eq 4) {  
        $r->print('Last step');
        $r->print('<form method="post" action="editor">');
        $r->print('<select name="curriculum"><option>Implemented</option><option>Achieved</option></select>');
        $hidden_fields{'target'} = 'curriculum';
        $hidden_fields{'step'} = 5;
        $hidden_fields{'location'} = $r->param('location');
        $hidden_fields{'subject'} = $r->param('subject');
        $hidden_fields{'grade'} = $r->param('grade');
        $r->print(&hidden_fields(\%hidden_fields));
        $r->print('<hr align="center" width="100%" />');
        $r->print('<p>&nbsp;<input type="submit" value="Next->">&nbsp;</p>');
        $r->print('</form>');
    }   elsif ($step eq 5) {
        $r->print('Select the Framework Elements<br />');
        $r->print('<form method="post" action="editor">');
        $r->print('<div id="frameworkSelector">');
        &topic_selector($r, 'math');
        $r->print('</div><br />');
        $hidden_fields{'action'} = 'save';
        $hidden_fields{'target'} = 'curriculum';
        $hidden_fields{'step'} = 1;
        $hidden_fields{'curriculum'} = $r->param('curriculum');
        $hidden_fields{'location'} = $r->param('location');
        $hidden_fields{'subject'} = $r->param('subject');
        $hidden_fields{'grade'} = $r->param('grade');
        $r->print(&hidden_fields(\%hidden_fields));
        $r->print('<hr align="center" width="100%" />');
        $r->print('<p>&nbsp;<input type="submit" value="Next->">&nbsp;</p>');
        $r->print('</form>'); 

    }
    return 'ok';
}
sub save_materials {
    my ($r) = @_;
    my %fields = ('title'=>&fix_quotes($r->param('title')),
                'author'=>&fix_quotes($r->param('author')),
                'year'=>&fix_quotes($r->param('year')),
                'edition'=>&fix_quotes($r->param('edition')),
                'isbn' => &fix_quotes($r->param('isbn')),
                'publisher'=>&fix_quotes($r->param('publisher')),
                'organization' => &fix_quotes($r->param('organization')),
                'notes' => &fix_quotes($r->param('notes')),
                'subject' => &fix_quotes($env{'subject'}),
                'grades' => &fix_quotes($r->param('grades')));
    my $new_id = &save_record('cc_materials',\%fields,1);
    return($new_id);
}
sub save_district_curriculum {
    my ($r) = @_;
    my $location = &get_user_location();
    my %fields = ('title'=>&fix_quotes($r->param('title')),
                  'district_id'=>$r->param('districtid'),
                  'description'=>&fix_quotes($r->param('description')));
    &save_record('cc_curricula', \%fields);              
    return 'ok';
}
sub save_curriculum {
    my ($r) = @_;
    my @framework_codes = $r->param('frameworkcode');
    my $subject = $r->param('subject');
    my $location = $r->param('location');
    my $grade = $r->param('grade');
    my $curriculum = lc($r->param('curriculum'));
    my %fields;
    $fields{'subject'} = &fix_quotes($subject);
    $fields{'location_id'} = $location;
    $fields{'grade'} = $grade;
    foreach my $check (@framework_codes) {
        $fields{'framework_id'} = $check;
        &save_record($curriculum.'_curriculum', \%fields);
    }
    return 'ok';
}

#sub get_curricula {
#    my($district_id) = @_;
#    my $subject = $env{'subject'};
#    my @curricula;
#    my $qry = "SELECT id, title, description 
#               FROM cc_curricula, cc_curricula_districts 
#               WHERE cc_curricula_districts.district_id = $district_id 
#               AND cc_curricula_districts.curriculum_id = cc_curricula.id
#               AND cc_curricula.subject = '$subject'";
#    my $rst = $env{'dbh'}->prepare($qry);
#    &Apache::Promse::logthis($qry);
#    $rst->execute();
#    while (my $curriculum = $rst->fetchrow_hashref()) {
#        push @curricula,{%$curriculum};
#    }
#    return(\@curricula);
#}
#sub list_curricula {
#    my ($r) = @_;
#    my $location = &get_user_location();
#    my $curricula = get_curricula($$location{'district_id'});
#    $r->print('<div id="statusMessage">&nbsp;</div>');
#    $r->print('<div id="coursescontainer" class="coursesContainer" style="width: 600px;">');# overall material container style later
#    $r->print('<div style="background-color: #eeeeee;height: 25px;padding-top: 5px;border-bottom-width: 1px;border-bottom-style: solid;border-bottom-color: #000000;">'); # header row container
#    $r->print('<b>Curricula</b>');
#    $r->print('</div>');
#    my $curriculum_counter = 1;
#    my $found_one = 0;
#    foreach my $item (@$curricula) {
#        $r->print('<div class="revealContainer" id="curriculumContainer'.$curriculum_counter.'" >' ); #revealer container
#        $r->print('<div class="controller" id="curriculumController'.$curriculum_counter.'" >'); #controller container
#        $r->print('<div class="arrowSpacer" onclick="infoReveal(\'curriculum\','."$curriculum_counter".');">');
#        $r->print('<img id="curriculumImage'.$curriculum_counter.'"  src="../_images/BannerRightArrow.gif" width="7" height="4" alt="" />');
#        $r->print('</div>'."\n");
#        $r->print('<div class="segmentSpacer">'."\n");
#        $r->print($$item{'title'});
#        $r->print('</div>'."\n");
#        $r->print('<div id="linkMessage'.$$item{'id'}.'" style="float: right;cursor: pointer;" >');
#        my %fields = ('menu'=>'curriculum',
#                      'submenu'=>'develop',
#                      'token'=>$env{'token'},
#                      'curriculumid'=>$$item{'id'});
#        my $url = &build_url('editor',\%fields);
#        $r->print('<a href="'.$url.'">Select</a>');
#        $r->print('</div>');
#        $r->print('</div>'); # close controller
#        $r->print('<div style="display: none;" class="collapser" id="curriculumCollapser'.$curriculum_counter.'">'); #collapser container
#        $r->print($$item{'description'});
#        $r->print('</div>');
#        $r->print('</div>'); # close revealer
#        $found_one = 1;
#        $curriculum_counter ++;
#    }
#    if (!$found_one) {
#        $r->print('No curricula found for this district');
#    }
#    $r->print('</div>');
#        
#}
sub list_materials {
    my ($r) = @_;
    my $location = &get_user_location();
    my $materials = get_materials($env{'district_id'});
    my $found_one = 0;
    $r->print('<div id="statusMessage">&nbsp;</div>');
    $r->print('<div id="coursescontainer" class="coursesContainer" style="width: 600px;">');# overall material container style later
    $r->print('<div style="background-color: #eeeeee;height: 25px;padding-top: 5px;border-bottom-width: 1px;border-bottom-style: solid;border-bottom-color: #000000;">'); # header row container
    $r->print('<b>Curricular Resources</b>');
    $r->print('</div>');
    my $material_counter = 1;
    foreach my $item (@$materials) {
        $r->print('<div class="revealContainer" id="materialContainer'.$material_counter.'" >' ); #revealer container
        $r->print('<div class="controller" id="materialController'.$material_counter.'" >'); #controller container
        $r->print('<div class="arrowSpacer" onclick="infoReveal(\'material\','."$material_counter".');">');
        $r->print('<img id="materialImage'.$material_counter.'"  src="../_images/BannerRightArrow.gif" width="7" height="4" alt="" />');
        $r->print('</div>'."\n");
        $r->print('<div class="segmentSpacer">'."\n");
        $r->print($$item{'title'});
        $r->print('</div>'."\n");
        $r->print('<div id="linkMessage'.$$item{'id'}.'" style="float: right;cursor: pointer;" onclick="linker('.$$item{'id'}.','.$$location{'location_id'}.',\''.$env{'token'}.'\')">');
        my $link_message;
        if ($$item{'district_id'}) {
            $link_message = "In district";
        } else {
            $link_message = "Not in district";
        }
        $r->print($link_message);
        $r->print('</div>');
        $r->print('</div>'); # close controller
        $r->print('<div style="display: none;" class="collapser" id="materialCollapser'.$material_counter.'">'); #collapser container
        $r->print($$item{'notes'});
        $r->print('</div>');
        $r->print('</div>'); # close revealer
        $found_one = 1;
        $material_counter ++; 
    }
    if (!$found_one) {
        $r->print('No materials found for this district');
    }
    $r->print('</div>');
    return('ok');
}
sub get_units {
    my($curriculum_id,$grade) = @_;
    my @units;
    my $qry = "select title, description, id from cc_units where curriculum_id = $curriculum_id and grade_id = $grade";
    my $rst = $env{'dbh'}->prepare($qry);
    $rst->execute();
    while (my $unit = $rst->fetchrow_hashref()) {
        push @units,{%$unit};
    }
    return(\@units);
}
sub develop_curriculum {
    my($r) = @_;
    my $location = &get_user_location();
    my $district_id = $$location{'district_id'};
    my $curriculum_id = $r->param('curriculumid');
    my $grade = $r->param('grade')?$r->param('grade'):'undefined';
    my @grades = ({'k'=>'k'},{'1'=>'1'},{'2'=>'2'},{'3'=>'3'},{'4'=>'4'},{'5'=>'5'},{'6'=>'6'},{'7'=>'7'},{'8'=>'8'});
    $r->print(&build_select('grade',\@grades));
    my $unit_counter = 1;
    my $units = &get_units($curriculum_id, $grade);
    $r->print('<div id="replaceThis">');
    foreach my $unit(@$units) {
        $r->print('<div id="unitContainer'.$unit_counter.'">');
        $r->print('<div id="unitController'.$unit_counter.'">');
        $r->print('<div class="arrowSpacer" onclick="infoReveal(\'unit\','."$unit_counter".');">');
        $r->print('<img id="unitImage'.$unit_counter.'" src="../_images/BannerRightArrow.gif" width="7" height="4" alt="" />');
        $r->print('</div>');
        $r->print('</div>');
        $r->print('<div id="unitCollapser'.$unit_counter.'">');
        $r->print('develop curriculum here');
        $r->print('</div>');
        $r->print('</div>');
    }
    $r->print('<div id="addunitContainer">');
    $r->print('<div id="addunitController">');
    $r->print('<div class="arrowSpacer" onclick="infoReveal(\'addunit\',\'\');">');
    $r->print('<img id="addunitImage" src="../_images/BannerRightArrow.gif" width="7" height="4" alt="" />');
    $r->print('</div>');
    $r->print('Add Unit');
    $r->print('</div>');
    $r->print('<div id="addunitCollapser">');
    $r->print('<input type="text" id="title" />');
    $r->print('<textarea id="newunitdescription" rows="5" cols="40">');
    $r->print('</textarea>');
    $r->print('<div style="cursor: pointer;" onclick="saveUnit('."'$env{'token'}', $district_id, $curriculum_id ".');">Save New Unit</div>');
    $r->print('</div>');
    $r->print('</div>');
    $r->print('</div>');
    return('ok');
}
sub add_curriculum_form {
    my ($r) = @_;
    my $url = &get_base_url($r);
    my $location = &get_user_location();
    $r->print('<h4>Add District Curriculum</h4>');
    $r->print('<div class="resourceFormContainer" style="background-color: #eeffee;">');
    $r->print('<form action="'.$url.'" method="post" >');
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('Title:');
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<input type="text" size="50" name="title" />');
    $r->print('</div>');
    $r->print('</div>');
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('Notes:');
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<textarea name="description" cols="55" rows="10"></textarea>');
    $r->print('</div>');
    $r->print('</div>');
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('<div class="resourceFormSubmit">');
    $r->print('<input type="submit" name="Submit" value="Save Curriculum" />');
    $r->print('</div>');
    $r->print('</div>');
    $r->print('</div>');
    my %fields;
    %fields = ('menu'=>'curriculum',
                  'districtid'=>$$location{'district_id'},
                  'submenu'=>'selectcurriculum',
                  'action'=>'addcurriculum');
    $r->print(&hidden_fields(\%fields));
    print '</form>';
    $r->print('</div>'); # close resource form container
     
    return('ok');
}
sub add_materials_form {
    my ($r) = @_;
    my $url = &get_base_url($r);
    $r->print('<h4>Add Curricular Material</h4>');
    $r->print('<div class="resourceFormContainer" style="background-color: #eeffee;">');
    $r->print('<form action="'.$url.'" method="post" >');
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('Title:');
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<input type="text" size="50" name="title" />');
    $r->print('</div>');
    $r->print('</div>');
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('Author:');
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<input type="text" size="30" name="author" />');
    $r->print('</div>');
    $r->print('</div>');
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('Year:');
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<input type="text" size="7" name="year" />');
    $r->print('</div>');
    $r->print('<div>');
    $r->print('ISBN: <input type="text" size="15" name="isbn" />');
    $r->print('</div>');
    $r->print('</div>');
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('Edition');
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<input type="text" size="30" name="edition" />');
    $r->print('</div>');
    $r->print('</div>');
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('Publisher');
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<input type="text" size="30" name="publisher" />');
    $r->print('</div>');
    $r->print('</div>');
    
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('Notes:');
    $r->print('</div>');
    $r->print('<div class="resourceFormField">');
    $r->print('<textarea name="notes" cols="55" rows="10"></textarea>');
    $r->print('</div>');
    $r->print('</div>');
    
    $r->print('<div class="materialFormRow">');
    $r->print('<div style="width: 150px;text-align: right;float: left;">');
    $r->print('<div class="resourceFormSubmit">');
    $r->print('<input type="submit" name="Submit" value="Save Material" />');
    $r->print('</div>');
    $r->print('</div>');
    $r->print('</div>');
    my %fields;
    %fields = ('menu'=>'curriculum',
                  'submenu'=>'materials',
                  'action'=>'addmaterial');
    $r->print(&hidden_fields(\%fields));
    print '</form>';
    $r->print('</div>'); # close resource form container
    
    return 'ok';
}
sub add_user_form {
    my ($r) = @_;
    $r->print('<div id="interiorHeader">');
    $r->print('<h2>Professional Development: Virtual Professional Development</h2>');
    $r->print('<h3>PROM/SE New User Registration</h3>');
    $r->print('</div><div id="interiorcontent">');
    $r->print('<form name="form1" method="post" action="register">'."\n");
    $r->print('<fieldset>');
    $r->print('<label>First Name</label>');
    $r->print('<input name="firstname" type="text" id="firstname" value="" size="35">');
    $r->print('<label>Last Name</label>');
    $r->print('<input name="lastname" type="text" id="lastname" value="" size="35">');
    $r->print('<label>Email Address</label>');
    $r->print('<input name="email" type="text" id="email" value="" size="25">');
    $r->print('<label>Please check all that apply.</label>');
    $r->print('<label>I teach 6th grade</label><input type="checkbox" name="checkbox" value="6">');
    $r->print('<label>I teach 7th grade</label><input type="checkbox" name="checkbox" value="7">');
    $r->print('<label>I teach 8th grade</label><input type="checkbox" name="checkbox" value="8">');
    $r->print('<label>User Name (e.g., MarySmith) </label>');
    $r->print('<input name="username" type="text" id="username" value="" size="25">');
    $r->print('<label>Password</label>');
    $r->print('<input name="password" type="password" id="password2" value="" size="25">');
    $r->print('<label>Bio</label>');
    $r->print('');
    $r->print('<textarea name="textarea" cols="55" rows="10"> </textarea>');
    $r->print('</fieldset>');
    $r->print('<input type="hidden" name="target" value="addrecord">');
    $r->print('<input name="Button" type="submit"  value="Register New Member">');
    $r->print('</form></div>');
    return 'ok';
}

sub user_not_valid {
    print qq~
    <table width="100%" border="0" cellspacing="0" cellpadding="10">
    <tr>
    <td align="left" valign="top">
    <p class="header">You are not logged in.</p>
    <p class="content">You can receive this page for any of several reasons. 
    <p class="content">You may have mis-typed your user name or your password, you may 
    have reached this page after logging out (by using your browser&quot;s back button) or you 
    may have been inactive on the site and were automatically logged out. 
    <p class="content">If you are registered you may wish to go back and <a href=promse>log in.</a></p>
    <p class="content">If you have not registered, you can do that by contacting a VPD administrator.
        </p>
    </td>
    </tr>
    </table>
    ~;
}
sub mentor_rating {
print qq~                    <p class="content"><strong>RATING</strong></p>
                    <p class="content">You have a current rating of 8. You are in the 
                      top 95% of mentors based on your question/answer ratio. </p>
~;
}

sub last_login {
    print '<br /><span>last login info to go here</span><br />';
    return 'ok';
}

sub logout {
    my ($r) = @_;
    my $qry;
    $qry = "DELETE FROM log WHERE token = '".$env{'token'}."'";
    $env{'dbh'}->do($qry);
    $qry = "DELETE FROM checkout WHERE user_id = ".$env{'user_id'};
    $env{'dbh'}->do($qry);
    my %fields = ('user_id'=>$env{'user_id'},
                   'date' => ' now() ',
                   'resource_id' => "'User Logout'");
    &save_record('activity_log',\%fields);
    return $qry;
}

sub help_system {
    my ($r) = @_;
    my $topic;
    if ($r->param('helptopic')) {
        $topic = $r->param('helptopic');
    } else {
        $topic = $env{'help_topic'};
    }
    if ($topic eq 'preferences') {
        print qq~
        <h4>Setting Preferences</h4>
        <div class="floatLeft">
        <div id="lookupScroller">
        <p class="content">The VPD has three kinds of preferences that you will want to set.
        You can set all three by going to the <strong>Home</strong> menu, and clicking on 
        <strong>Preferences</strong>. At the top of the page is a sub-menu where you can select 
        each of the three kinds of preferences: <strong>Profile, Interests,</strong> and <strong>Settings</strong></p>
        <strong>Profile</strong>
        <p class="content">Your profile describes you to others in the PROM/SE community. Be sure to 
        fill out your profile with information about what and where you teach. You can also update your
        email address, password, and your name, as it will be shown to others.</p>
        <p class="content">Be sure to click <strong>Save Changes</strong> when you are done making changes.</p>
        <strong>Note:</strong>
        <p class="content">If your browser is set to remember your password, you may find that the password field
        has asterisks in it. If you do not wish to change your password, you can still make other changes. When you
        click <strong>Save Changes</strong> changes in your Bio, name and email will be saved, but you will see
        a message indicating that the two password fields did not match, and the password was not changed.</p>
        </div>
        </div>
        <div class="floatLeft">
        <div id="lookupScroller">
        <strong>Interests</strong>
        <p class="content">Check the subject area topics that are of particular interest to you. 
        Remember that PROM/SE is about both giving and receiving support in teaching. When you click a 
        topic area of interest, enter a level of 1 (low), 2 (med), or 3 (high). </p>
        <p class="content">The VPD will use this information to help target resources and people. Where you 
        are strong (where you entered 3), you may receive questions about an area. Where you are less strong,
        you may receive messages recommending materials to support your understanding.</p>
        </div>
        </div>
        <div class="floatLeft">
        <div id="lookupScroller">
        <strong>Settings</strong>
        <p class="content">A number of features of the VPD are customizable. <strong>Settings</strong>
         allows you to change the way the PROM/SE environment works for you.</p>
         <p>As the VPD system is used, new customizable features will be added to the settings page.
         be sure to check back at the settings page to be sure that you have the settings that you prefer.</p>
        </div>
        </div>
         ~;
    } elsif ($topic eq 'finding'){
        print qq~
        <h4>Finding Resources</h4>
        <div id="lookupScroller">
        <p class="content">You can find resources to meet your learning and teaching needs by using the
        resource <strong>Search</strong> function. This is under the <strong>Teacher</strong> or <strong>
        Associate</strong> menu item.</p>
        <p>Here you can specify the <strong>subject area</strong>, the <strong>time commitment</strong> of
        the resources you are seeking.
        <p>In the <strong>Search for:</strong> box, you should type as much information as you can to 
        describe the content of your desired resources. For example, a good search phrase might be: <strong>
        teaching fractions using manipulatives with third graders</strong>.</p>
        <p class="content">After you click <strong>Search</strong> you will receive a list of the resources 
        available that most closely meet your criteria. Note the scores offered that show both how closely
        the resources meet your criteria, as well as how others who have used the resources rated them.</p>
        </div>
        ~;
    } elsif ($topic eq 'requirements'){
        print qq~
        <h4>System Requirements</h4>
        <div id="lookupScroller">
        <p class="content">The PROMSE VPD was developed using Firefox, on a PC platform.
        It is intended to be fully supported using any recent browser (e.g., Internet
        Explorer, Netscape, Firefox, Safari) on any computer (e.g., Windows, Mac, Linux). 
        If you encounter problems, please contact us and we will work to correct
        the problem.</p>
        
        </div>
        ~;
    } elsif ($topic eq 'passwords'){
        print qq~
        <h4>Forgotten Password</h4>
        <div id="lookupScroller">
        <p class="content">Passwords on the PROMSE VPD system are stored in clear text
        on our database. All reasonable efforts are made to keep passwords secure,
        but the VPD is not a "secure" website. That means that you should not use
        passwords that you may currently use for high-security situatie for high-security situatie for high-security situatie for high-security situatie for high-security situatie for high-security situations. For example,
        it would be unwise to use your online banking password on the PROMSE VPD.</p>
        </div>
        ~;
    } elsif ($topic eq 'answering'){
        print qq~
        <h4>Answering Questions</h4>
        <div id="lookupScroller">
        <p class="content">The PROMSE VPD is intended to provide <strong>just in
        time</strong> answers to questions. If you are given a question to answer,
        it is very important to respond as quickly as possible to encourage new
        teachers to take advantage of this resource.</p>
        </div>
        ~;
    } else {
    print '<h4>Help Center</h4>';
    print '<p class="content">';
    print qq~
    <strong> Tagging resources </strong> means assigning descriptors and relationships to a teaching resource. for example,
    a lesson plan intended to teach 3rd grade students addition facts would be tagged as <strong>3rd grade</strong>, <strong>
    math</strong> (as its subject), and perhaps 1.1.2.3 as the index from the math framework.</p>
    <p class="content"><span>It is possible to assign any number of tags to a resource, and a tag can be just about anything that is found
    in the PROM/SE Virtual Professional Development environment. This includes keywords, framework cells, other resources,
    individuals, etc.</p>
    <p style="content">This is a dynamic system, being developed exclusively for PROMSE. The system is dynamic in several ways:</p>
    <ul><li class="content">It is tightly coupled with an underlying database, and responds dynamically based on the content of the database.
    <li class="content">The system is designed for the users, and its design changes dynamically (through programming changes) as users voice their concerns.
    </ul>
    <p class="content">A primary goal of this Professional Development environment is to be dynamically responsive to the needs
    of the users.
    <p class="content">
    ~;
    print '</p>';
}
sub fix_quotes {
    my ($fixed) = @_;
    if(defined $fixed) {
        $fixed =~ s/'/''/g;
    } else {
        $fixed = '';
    }
    return " '".$fixed."' ";
}

    return();
}

1; 
