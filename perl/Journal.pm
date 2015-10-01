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
package Apache::Journal;
# File: Apache/Home.pm
use CGI;
$CGI::POST_MAX = 900000;
use Apache::Flash;
use Apache::Promse;
use Apache::Chat;
#use MIME::Lite;
# use PDF::Create;
use MIME::QuotedPrint;
use MIME::Base64;
use Mail::Sendmail;
# use JSON;
use JSON::XS;
# use JSON::Streaming::Writer;
# use vars(%env);
use strict;
use Apache::Constants qw(:common);

sub handler {
	#our $profile;
    my $json_scalar = "something here";
    my $coder = JSON::XS->new->ascii->pretty->allow_nonref;
    my $fh;
	print STDERR "\n****** \n IN JOURNAL.PM \n ******* \n";
    if (open($fh,">/var/www/logs/output.jsn")) {
    } else {
        print STDERR "open attempt returned false \n"
    }
    my $r = new CGI;
    if ($r->cgi_error) {
        &Apache::Promse::top_of_page($r);
        print $r->cgi_error;
        &Apache::Promse::footer($r)
    }
    my $warning = &Apache::Promse::validate_user($r); #sets environment variables.
    print STDERR "the warning from validate user is $warning \n";
	if ($warning eq 'no_user_id') {
		if ($env{'username'} eq 'not_found') {
			if ($r->param('action') eq 'getvaliddomains') {
				my $qry = "SELECT t1.district_id, t1.domain_name, t2.district_name
											FROM ok_domains t1
											LEFT JOIN districts t2 on t2.district_id = t1.district_id
											WHERE t1.enabled = 1
											ORDER BY t2.district_name";
				my $dbh = &Apache::Promse::db_connect();
				my $rst = $dbh->prepare($qry);
				$rst->execute();
				my @returned_domains;
				my @all_domains;
				my %dummy = ('district_id'=>' ',
							'district_name'=>'Select a District');
				push (@all_domains,{%dummy});
				my $current_district = 0;
				my $done_one = 0;
				my %district;
				while (my $row = $rst->fetchrow_hashref()) {
					if ($$row{'district_id'} ne $current_district) {
						if ($done_one) {
							push(@all_domains, {%district});
						}
						$district{'district_id'} = $$row{'district_id'};
						$district{'district_name'} = $$row{'district_name'};
						$district{'domain_name'} = $$row{'domain_name'};
						$current_district = $$row{'district_id'};
						$done_one = 1;
					} else {
						$district{'domain_name'} .= ";" . $$row{'domain_name'};
					}
				}
				if ($done_one) {
					push(@all_domains, {%district});
				}
				my %all_returns;
				$all_returns{'domains'} = [@all_domains];
				$r->print(JSON::XS::->new->pretty(1)->encode( \%all_returns));
			} elsif ($r->param('action') eq 'getframework2' || $r->param('action') eq 'getframework') {
				&get_framework2_file($r);
			} elsif ($env{'action'} eq 'login'){
			    # call from angular so POSTDATA
				print STDERR "logging in \n";
			} elsif ($r->param('action') eq 'getwelcomeletter'){
				&get_welcome_letter($r);
			} elsif ($r->param('action') eq 'getschoolsbyzip') {
			    &get_schools_by_zip($r);
			} elsif ($r->param('action') eq 'insertproposedschool') {
			    my %fields = ('school_name'=>$r->param('schoolname'),
			                'district_name'=>$r->param('districtname'),
			                'zip'=>$r->param('schoolzip'),
			                'email'=>$r->param('personemail')
			                );
			     my $table_name = 'tj_proposed_school';
			     my $new_record_id = &Apache::Promse::insert_record($table_name, \%fields, 1);
			     my %message = ('status'=>'success',
			                'recordid'=>$new_record_id);
			     $r->print(JSON::XS::->new->pretty(1)->encode( \%message));
			} elsif ($r->param('action') eq 'insertproposedtext') {
			    my %fields = ('title'=>$r->param('nonlistedTextbook'),
			                'publisher'=>$r->param('nonlistedTextbookPublisher'),
			                'year'=>$r->param('nonlistedTextbookYearPublished'),
			                'email'=>$r->param('email'),
			                'isbn'=>$r->param('nonlistedTextbookISBN')
			                );
			     my $table_name = 'tj_proposed_text';
			     my $new_record_id = &Apache::Promse::insert_record($table_name, \%fields, 1);
			     my %message = ('status'=>'success',
			                'recordid'=>$new_record_id);
			     $r->print(JSON::XS::->new->pretty(1)->encode( \%message));
   
			} elsif ($r->param('action') eq 'getdistricts') {
			    &get_districts($r);
            } elsif ($r->param('action') eq 'getcurricula') {
					print STDERR "\n *** Getting curricula \n ";
			        my $district_id = $r->param('districtid');
			        my $subject = $r->param('subject');
			        my $curricula = &get_curricula($district_id, $subject);
					my %curricula;
					$curricula{'curricula'} = [@$curricula];
					# print STDERR JSON::XS::->new->pretty(1)->encode( \%curricula);
					$r->print(JSON::XS::->new->pretty(1)->encode( \%curricula));
					return();
			} elsif ($r->param('action') eq 'insertproposedtext') {
			    &insert_proposed_text($r);
			} elsif ($r->param('action') eq 'insertproposedschool') {
			    &insert_proposed_school($r);
			} elsif ($r->param('action') eq 'activateaccount') {
				my $qry = "UPDATE users SET active=1 WHERE username = ?";
				my $rst = $env{'dbh'}->prepare($qry);
				$rst->execute($r->param('username'));
		       		print $r->header(-type => 'text/html',-expires => 'now');

				$r->print("Your new account is now active <br> You can log in here: <a href=\"http://csc.educ.msu.edu/Nav\">Texbook Navigator/Journal</a>.");
			    
			} elsif ($r->param('action') eq 'getdistrictitems') {
				my $district_id = $r->param('districtid');
				my $qry = "SELECT 'school' item, t1.school item_name, t1.location_id item_id FROM
					locations t1 
				WHERE t1.district_id = ?
				UNION
				SELECT 'class' item, t2.class_name item_name, t2.class_id item_id
					FROM tj_classes t2, tj_district_class t3
				WHERE 
				t2.class_id = t3.class_id AND t3.district_id = ?
				";
				my $dbh = &Apache::Promse::db_connect();
				my $rst = $dbh->prepare($qry);
				$rst->execute($district_id, $district_id);
				my @returned_schools;
				my @returned_classes;
				my %dummy_school = ('school_id'=>' ','school'=>"Select a School");
				my %dummy_class = ('class_id'=>' ','class_name'=>'Select a Course');
				push @returned_schools,{%dummy_school};
				push @returned_classes,{%dummy_class};
				while (my $row = $rst->fetchrow_hashref()) {
					if ($$row{'item'} eq 'school') {
						my %school = ('school'=>$$row{'item_name'},
									'school_id'=>$$row{'item_id'});
						push @returned_schools, {%school};
					}
					if ($$row{'item'} eq 'class') {
						my %class = ('class_name'=>$$row{'item_name'},
									'class_id'=>$$row{'item_id'});
						push @returned_classes, {%class};
					}
				}
				my %all_returns;
				$all_returns{'schools'} = [@returned_schools];
				$all_returns{'classes'} = [@returned_classes];
				$r->print(JSON::XS::->new->pretty(1)->encode( \%all_returns));
			} elsif ($r->param('action') eq 'registeruser') {
				&register_user($r);
			} elsif ($r->param('action') eq 'activateuser') {
				my $user_name = $r->param('username');
				my $qry = "UPDATE users SET active = 1 WHERE username = ?";
				my $dbh = &Apache::Promse::db_connect();
				my $rst = $dbh->prepare($qry);
				my $success = $rst->execute($user_name);
				my %response;
				$response{'activate'} = $success;
				$r->print(JSON::XS::->new->pretty(1)->encode( \%response));
			} else {
				$r->print('{"success":"logNo"}');
			}
			return();
		} else {
			$r->print('{"response":"no_user_id"}');
			return();
		}
	}
    if ($env{'target'} eq 'redirect') {
        &Apache::Promse::redirect($r);
    }
    if (($env{'username'} ne 'not_found') || ($env{'token'}=~/[^\s]/)){
        my $prefs = &Apache::Promse::get_preferences($r);
        if ($r->param('action') eq 'getframework') {
#            my $head_text = '<meta http-equiv="Content-Type" content="text/json; charset=utf-8" />';
#            print $r->header(-type => 'text/json');
#            $r->print( '{"first": 5, "second": "second value"}');
             &get_framework_file($r);
		} elsif ($r->param("action") eq 'getuserinfo') {
			print STDERR "****\n****\n getting user info \n ***** \n ***** ";
	       &get_user_info($r);
		} elsif ($r->param('action') eq 'getuserlog') {
			my $output = &get_user_log($r);
			$r->print($output);
		} elsif ($r->param('action') eq 'generatereport') {
			&generate_report($r);
		} elsif ($r->param('action') eq 'getuserlog14') {
			my $output = &get_user_log14($r);
			$r->print($output);
	    } elsif ($r->param("action") eq 'getuserinfoold') {
			my $response =
			    '
						{ "user": [	{
							"username": "Joan Smith",
							"email": "smith@smith.com",
							"classes":
							[{"classid": "1",
							"classname": "Math 1"},
							{"classid": "2",
							"classname":"Algebra"}]}]
						}';

						$r->print($response);

		} elsif ($r->param('action') eq 'getmaterials') {
			&get_materials($r);
		} elsif ($r->param('action') eq 'getdistrictclasses') {
			my $district_id = $r->param('districtid');
			my $class_selector = &get_district_classes($district_id);
			$r->print($class_selector);
		} elsif ($r->param('action') eq 'getdistrictclassesummary') {
					&get_tj_district_class_summary($r);
		} elsif ($r->param('action') eq 'gettjsummary') {
					&get_tj_summary($r);
		} elsif ($r->param('action') eq 'getcurricula') {
					print STDERR "\n *** Getting curricula \n ";
			        my $district_id = $r->param('districtid');
			        my $subject = $r->param('subject');
			        my $curricula = &get_curricula($district_id, $subject);
					my %curricula;
					$curricula{'curricula'} = [@$curricula];
					# print STDERR JSON::XS::->new->pretty(1)->encode( \%curricula);
					$r->print(JSON::XS::->new->pretty(1)->encode( \%curricula));
					return();
		} elsif ($r->param('action') eq 'emailjournal') {
					$r->print(&email_journal($r));
		} elsif ($r->param('action') eq 'getlessonarray' || $r->param('action') eq 'getlessonarraync') {
					&get_lesson_array($r);
		} elsif ($r->param('action') eq 'getstandardarraync') {
		    print STDERR "\n in getstandardarraync \n";
			&get_standard_array_nc($r);	
		} elsif ($r->param('action') eq 'getstandardarray' || $r->param('action') eq 'getstandardarraync') {
					&get_standard_array($r);
		} elsif ($r->param('action') eq 'getlessondetail') {
					&get_lesson_detail($r);
		} elsif ($r->param('action') eq 'getlessonnav') {
					&get_lesson_nav($r);
		} elsif ($r->param('action') eq 'gettypes') {
					my $qry = 'SELECT type_id, type_name FROM tj_types ORDER BY tj_types.type_id';
					my $rst = $env{'dbh'}->prepare($qry);
					$rst->execute();
					my %types;
					my @types;
					while (my $row = $rst->fetchrow_hashref()) {
						push @types, {%$row};
					}
					$types{'types'} = [@types];
					my $output = JSON::XS::->new->pretty(1)->encode( \%types);
					$r->print($output);
		} elsif ($r->param('action') eq 'getallnotice') {
				    my $output;
					my $user_id = $env{'user_id'};
					my $profile = &Apache::Promse::get_user_profile($user_id);
					my $district_id = $$profile{'district_id'};
				    my $qry = "SELECT 'notice' as type, messages.id as id, messages.end_date as due, 
									messages.subject as title, 
									message_user_status.is_read as status
								FROM messages 
								LEFT JOIN message_user_status ON message_user_status.user_id = $user_id
											AND message_user_status.message_id = messages.id
								WHERE messages.start_date < current_date() 
									AND messages.end_date > current_date() 
									AND messages.deleted = 0
									AND messages.recipients LIKE '%TJ%'
								ORDER BY start_date, end_date 
					";
				    my $sth = $env{'dbh'}->prepare($qry);
				    $sth->execute();
					my @notices;
					while (my $row = $sth->fetchrow_hashref()) {
						push @notices, {%$row};
					}
					$qry = "SELECT 'invoice' as type, tj_invoices.invoice_id as id, tj_invoices.date_due as due, 
									tj_invoices.invoice_name as title, tj_user_invoice.status as status,
									tj_invoices.work_start, tj_invoices.work_end, tj_invoices.entries_required
									FROM tj_invoices 
									LEFT JOIN tj_user_invoice ON tj_user_invoice.invoice_id = tj_invoices.invoice_id AND
								tj_user_invoice.user_id = $user_id
									WHERE tj_invoices.date_available < current_date() 
								";
					$sth = $env{'dbh'}->prepare($qry);
					$sth->execute();
					
					while (my $row = $sth->fetchrow_hashref()) {
						my $work_start = "'" . $$row{'work_start'} . "'";
						my $work_end = "'" . $$row{'work_end'} . "'";
						my $entries_required = $$row{'entries_required'};
						my $qry = "SELECT count(journal_id) AS counter FROM tj_journal
						 	WHERE date_taught >= $work_start 
								AND date_taught <= $work_end
								AND user_id = $user_id";
						my $check_sth = $env{'dbh'}->prepare($qry);
						$check_sth->execute();
						my $check_row = $check_sth->fetchrow_hashref();
						print STDERR "\n entries required $entries_required and found were: " . $$check_row{'counter'} ."\n";
						if ($$check_row{'counter'} >= $entries_required) {
							push @notices, {%$row};
						}
					}
					# brute force for invoice #2
					# edit this for subsequenct invoices  
					$qry = "SELECT user_id FROM temp_invoice_user_list WHERE user_id = $user_id AND invoice_id = 0";
					$sth = $env{'dbh'}->prepare($qry);
					$sth->execute();
					if (my $row = $sth->fetchrow_hashref()) {
						$qry = "SELECT 'invoice' as type, tj_invoices.invoice_id as id, tj_invoices.date_due as due, 
										tj_invoices.invoice_name as title, tj_user_invoice.status as status,
										tj_invoices.work_start, tj_invoices.work_end, tj_invoices.entries_required
										FROM tj_invoices 
										LEFT JOIN tj_user_invoice ON tj_user_invoice.invoice_id = tj_invoices.invoice_id AND
									tj_user_invoice.user_id = $user_id
										WHERE tj_invoices.invoice_id = 2
									";
						$sth = $env{'dbh'}->prepare($qry);
						$sth->execute();
						$row = $sth->fetchrow_hashref();
						push @notices, {%$row};
					} else {
						print STDERR "\n user not found \n";
					}
					$qry = "SELECT user_id FROM temp_invoice_user_list WHERE user_id = $user_id AND invoice_id = 4";
					$sth = $env{'dbh'}->prepare($qry);
					$sth->execute();
					
					if (my $row = $sth->fetchrow_hashref()) {
						$qry = "SELECT 'invoice' as type, tj_invoices.invoice_id as id, tj_invoices.date_due as due, 
										tj_invoices.invoice_name as title, tj_user_invoice.status as status,
										tj_invoices.work_start, tj_invoices.work_end, tj_invoices.entries_required
										FROM tj_invoices 
										LEFT JOIN tj_user_invoice ON tj_user_invoice.invoice_id = tj_invoices.invoice_id AND
									tj_user_invoice.user_id = $user_id
										WHERE tj_invoices.invoice_id = 4
									";
						$sth = $env{'dbh'}->prepare($qry);
						$sth->execute();
						$row = $sth->fetchrow_hashref();
						push @notices, {%$row};
				} else {
					print STDERR "\n user not found \n";
				}
				# now do brute force for notification (not really an invoice) #3
				print STDERR "\n getting all notice routine district is $district_id ***** \n";
				my $list_of_districts = 'x13x89x90x6x4x10x';
				my $district_match = 'x' . $district_id . 'x';
				if ($list_of_districts =~ /$district_id/) {
						$qry = "SELECT 'invoice' as type, tj_invoices.invoice_id as id, tj_invoices.date_due as due, 
										tj_invoices.invoice_name as title, tj_user_invoice.status as status,
										tj_invoices.work_start, tj_invoices.work_end, tj_invoices.entries_required
										FROM tj_invoices 
										LEFT JOIN tj_user_invoice ON tj_user_invoice.invoice_id = tj_invoices.invoice_id AND
									tj_user_invoice.user_id = $user_id
										WHERE tj_invoices.invoice_id = 3
									";
						$sth = $env{'dbh'}->prepare($qry);
						$sth->execute();
						if (my $row = $sth->fetchrow_hashref()) {
							push @notices, {%$row};
						}
				} else {
					print STDERR "district did not match \n";
				}
				my %notices;
				$notices{'notices'} = [@notices];
				$output = JSON::XS::->new->pretty(1)->encode( \%notices);
				$r->print($output);
			} elsif ($r->param('action') eq 'updateuserinfo') {
		        &update_user_info($r);
			} elsif ($r->param('action') eq 'getsubmittedinvoice') {	
					my $invoice_id = $r->param('invoiceid');
					my $user_id = $env{'user_id'};
					my $qry = "SELECT tj_invoices.message, tj_";
			} elsif ($r->param('action') eq 'getinvoice') {
					my $invoice_id = $r->param('invoiceid');
					my $user_id = $env{'user_id'};
					my $qry = "SELECT invoice_name, date_due, date_available, work_start, work_end, message,now() as now
							FROM tj_invoices
							LEFT JOIN tj_user_invoice ON tj_invoices.invoice_id = tj_user_invoice.invoice_id
							AND tj_user_invoice.user_id = $user_id
							WHERE tj_invoices.invoice_id = ? 
								";
					my $rst = $env{'dbh'}->prepare($qry);
					$rst->execute($invoice_id);
					if (my $invoice_row = $rst->fetchrow_hashref()) {
						my $message = $$invoice_row{'message'};
						my $work_start = $$invoice_row{'work_start'};
						my ($start_year, $start_month, $start_day) = split /-/,$work_start;
						my $work_end = $$invoice_row{'work_end'};
						my ($end_year, $end_month, $end_day) = split /-/,$work_end;
						$work_start = $start_month . '-' . $start_day . "-" . $start_year;
						$work_end = $end_month . '-' . $end_day . "-" . $end_year;
						my $date = $$invoice_row{'now'};
						my ($date_portion, $time_portion) = split / /, $date;
						my $user_name = $env{'display_name'};
						$message =~ s/<<workstart>>/$work_start/g;
						$message =~ s/<<workend>>/$work_end/g;
						$message =~ s/<<date>>/$date_portion/g;
						$message =~ s/<<username>>/$user_name/g;
						my %invoice_message = ('invoice'=> $message);
						my $output = JSON::XS::->new->pretty(1)->encode( \%invoice_message);
						$r->print($message);
					} else {
						$qry = "SELECT message FROM messages WHERE id = $invoice_id";
						$rst = $env{'dbh'}->prepare($qry);
						$rst->execute();
						my $message_row = $rst->fetchrow_hashref();
						my $message = $$message_row{'message'};
						$r->print($message);
					}
			} elsif ($r->param('action') eq 'updateteachertype') {
					my $qry = "DELETE FROM tj_teacher_type WHERE 
							user_id = ? AND class_id = ?";
					my $rst = $env{'dbh'}->prepare($qry);
					$rst->execute($env{'user_id'}, $r->param('classid'));
					my %fields = ('type_id' => $r->param('typeid'),
							'user_id' => $env{'user_id'},
							'class_id' => $r->param('classid'));
							
					my $msg = &Apache::Promse::save_record('tj_teacher_type',\%fields);
					$r->print('{"success":"OK"}');
			} elsif ($r->param('action') eq 'submitinvoice') {
					my $user_id = $env{'user_id'};
					my $invoice_id = $r->param('invoiceid');
					my $qry = "SELECT status, time_stamp FROM tj_user_invoice WHERE
								user_id = $user_id 
								AND invoice_id = $invoice_id";
					my $rst = $env{'dbh'}->prepare($qry);
					$rst->execute();
					if (my $row = $rst->fetchrow_hashref()) {
						$r->print('{"success":"submitted ' . $$row{'time_stamp'} . '"}');
					} else {
						my %fields = ('invoice_id' => $r->param('invoiceid'),
							'user_id' => $user_id,
							'status' => "'submitted'");
						my $msg = &Apache::Promse::save_record('tj_user_invoice',\%fields);
						$r->print('{"success":"OK"}');
					}
			} elsif ($r->param('action') eq 'deletejournalentry') {
					my $journal_id = $r->param('journalid');
					my $qry = "update tj_journal set deleted = 1 where journal_id = ?";
					my $rst = $env{'dbh'}->prepare($qry);
					$rst->execute($journal_id);
					$qry = "update tj_journal_topic set deleted = 1 where journal_id = ?";
					$rst = $env{'dbh'}->prepare($qry);
					$rst->execute($journal_id);
					$qry = "update tj_journal_math_practices set deleted = 1 where journal_id = ?";
					$rst = $env{'dbh'}->prepare($qry);
					$rst->execute($journal_id);
					$qry = "update tj_topic_materials set deleted = 1 where journal_id = ?";
					$rst = $env{'dbh'}->prepare($qry);
					$rst->execute($journal_id);
					$qry = "update tj_topic_activity set deleted = 1 where journal_id = ?";
					$rst = $env{'dbh'}->prepare($qry);
					$rst->execute($journal_id);
					$r->print('{"success":"OK"}');
			} elsif ($r->param('action') eq 'deletejournaltopic') {
					my $journal_id = $r->param('journalid');
					my $topic_id = $r->param('framework_id');
					my $qry = "DELETE FROM tj_journal_topic WHERE tj_journal_topic.journal_id = $journal_id
														AND tj_journal_topic.framework_id = $topic_id";
					$env{'dbh'}->do($qry);
					$qry = "DELETE FROM tj_topic_activity WHERE tj_topic_activity.journal_id = $journal_id AND
									topic_id = $topic_id";
					$env{'dbh'}->do($qry);
					$qry = "DELETE FROM tj_user_materials WHERE tj_user_materials.journal_id = $journal_id AND
									topic_id = $topic_id";
					$env{'dbh'}->do($qry);
					
					$r->print('{"success": "deleted"}');
			} elsif ($env{'action'} eq 'login') {
			    my %output = ('success'=>'logOk',
			                'token'=>$env{'token'},
			                'password'=>$env{'md5pwd'});
				$r->print(JSON::XS::->new->pretty(1)->encode( \%output));

			} elsif ($r->param('action') eq 'getdistrictitems') {
					my $output = &get_district_items($r);
					$r->print($output);
			} elsif ($r->param('action') eq 'updatejournaltopic') {
					&update_journal_topic($r);
			} elsif ($r->param('action') eq 'insertlesson') {
					&insert_lesson($r);
			} elsif ($r->param('action') eq 'insertjournaltopic') {
					&insert_journal_topic($r);
			} elsif ($r->param("action") eq 'genframework') {
					&get_framework($r);
			} elsif ($r->param("action") eq 'logout') {
					$r->print('{"logout":"ok"}');
		    } else {
		       		print $r->header(-type => 'text/html',-expires => 'now');
		       		$r->print(&top_of_page());
		    }
		} else {
		        #print $r->header(-type => 'text/json');
		        $r->print('{"success":"logNo"}');
		        #&Apache::Promse::top_of_page($r);
		        #&Apache::Promse::user_not_valid($r);
		}
    #print STDERR "\n*****  Check Point   *****\n";
    return();
}
sub generate_report {
	my ($r) = @_;
	my %output;
	my $directory_name = '/var/www/html/PDFTests';
	my $file_name = 'testfile.pdf';
	my $title = 'A title goes here';
	my $pdf = '';
#	my $pdf = new PDF::Create('filename'=>$directory_name.'/'.$file_name,
#							'version'=> 1.2,
#							'PageMode'=>'UseOutlines',
#							'Author'=>'VPD',
#							'Title'=>$title);
#	my $text = "This is something that should appear in the PDF";
	my $root = $pdf->new_page('MediaBox'=>[0, 0, 612, 792]);
	my $page = $root->new_page;
	my $f1 = $pdf->font('subtype'=>'Type1',
					'Encoding'=>'WinAnsiEncoding',
					'BaseFont'=>'Helvetica');
	$page->stringc($f1, 15, 306, 705, $title);
	$pdf->close;
	my $file = $directory_name.'/'.$file_name;
	my %mail = (
	         from => 'rick@msu.edu',
	         to => 'owen.campbell@gmail.com',
	         subject => 'Test attachment',
	        );


	my $boundary = "====" . time() . "====";
	$mail{'content-type'} = "multipart/mixed; boundary=\"$boundary\"";

	my $message = encode_qp( "Here is an attachment" );

	open (F, $file) or die "Cannot read $file: $!";
	binmode F; undef $/;
	$mail{body} = encode_base64(<F>);
	close F;

	$boundary = '--'.$boundary;
	$mail{body} = <<END_OF_BODY;
$boundary
Content-Type: text/plain; charset="iso-8859-1"
Content-Transfer-Encoding: quoted-printable

$message
$boundary
Content-Type: application/octet-stream; name="$file"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="$file"

$mail{body}
$boundary--
END_OF_BODY

	sendmail(%mail) || print "Error: $Mail::Sendmail::error\n";
	
	
	
	print STDERR "in generate report \n";
	print $r->header(-type => 'application/json',
                    -expires => 'now');
	$output{'success'} = 'true';
	$r->print(JSON::XS::->new->pretty(1)->encode(\%output));			
}
sub get_curricula {
    my($district_id, $subject) = @_;
    my @curricula;
    my $qry = "SELECT id, title, description, district_name, pub_year
               FROM cc_curricula, cc_curricula_districts, districts 
               WHERE cc_curricula_districts.district_id = $district_id 
               AND cc_curricula_districts.curriculum_id = cc_curricula.id
               AND cc_curricula.subject = '$subject'
               AND districts.district_id = $district_id
               ORDER BY cc_curricula.title";
    my $rst = $env{'dbh'}->prepare($qry);
    $rst->execute();
    my %select_text = ('title'=>'Select Text',
                    'description'=>'Select Text',
                    'id'=>0);
    #&Apache::Promse::logthis('******');
    push @curricula,{%select_text};
  print STDERR "\n$qry\n";
    while (my $curriculum = $rst->fetchrow_hashref()) {
        $$curriculum{'title'} = $$curriculum{'pub_year'} . '-' . $$curriculum{'title'};
        push @curricula,{%$curriculum};
    }
    return(\@curricula);
}
sub get_district_classes {
	my ($district_id) = @_;
	my @district_classes;
	my $qry = "SELECT DISTINCT
	tj_classes.class_id,
	tj_classes.grade,
	tj_classes.class_name
FROM
	tj_classes
WHERE
	tj_classes.class_id IN(
		SELECT
			tj_journal.class_id
		FROM
			tj_journal
		WHERE
			tj_journal.user_id IN(
				SELECT
					user_locs.user_id
				FROM
					user_locs,
					locations
				WHERE
					user_locs.loc_id = locations.location_id
				AND locations.district_id = ?
			)
	)
ORDER BY
	grade,
	class_name";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute($district_id);
	while (my $row = $rst->fetchrow_hashref()) {
		push @district_classes, {$$row{'class_name'}=>$$row{'class_id'}};
	}
	unshift @district_classes,{'Select Grade/Class'=>'0'};
    my $class_selector = &Apache::Promse::build_select('classid',\@district_classes,0,'onchange="classSelectorChange()"');
	return($class_selector);
}
sub get_districts {
    my ($r) = @_;
    my $state = $r->param('state');
    my $zip = $r->param('zip');
    my $qry;
    my $sth;
    my %output;
    if ($zip > 0) {
        $qry = "SELECT id, school_id, district_name, school_name FROM all_schools WHERE zip = ? ORDER BY district_name, school_name";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute($zip);
    } else {
        $qry = "SELECT DISTINCT district_name FROM all_schools WHERE state  = ? ORDER BY district_name";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute($state);
    }
    my @districts;
    while (my $row = $sth->fetchrow_hashref()) {
        push @districts, {%$row};
    }
    $output{'districts'} = [@districts];
	print $r->header(-type => 'application/json',
                    -expires => 'now');
	$r->print(JSON::XS::->new->pretty(1)->encode(\%output));			
    
}
sub get_new_stuff {
	my ($r) = @_;
	my $qry = "select * from cc_units
	left join cc_themes on cc_themes.unit_id = cc_units.id
	left join cc_pf_theme_tags t3 on t3.theme_id = cc_themes.id
	where curriculum_id = 315
	ORDER BY  cc_units.grade_id, cc_units.sequence, cc_themes.sequence";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	my %output;
	# must determine user's grade and curriculum
	print $r->header(-type => 'application/json',
                    -expires => 'now');
	$output{'success'} = 'true';
	$r->print(JSON::XS::->new->pretty(1)->encode(\%output));			
}
sub weekdays_between_dates{
	my ($start_date, $end_date) = @_;
	my $qry = "SELECT DATEDIFF(?,?) AS days, DAYOFWEEK(?) AS start_day";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute($end_date, $start_date, $start_date);
	my $row = $rst->fetchrow_hashref();
	my $days = $$row{'days'};
	my $weeks = int($days/7);
	my $week_days = $days - (2 * $weeks);
	return ($week_days);
}
sub get_tj_district_class_summary {
	my ($r) = @_;
	my $start_date = $r->param('startdate');
	my $end_date = $r->param('enddate');
	my $latest_date = '2000-01-01';
	my $earliest_date = '2100-01-01';
	my $district_id = $r->param('districtid');
	my $class_id = $r->param('classid');
	my $threshold = $r->param('threshold');
	my $overall_summary_table;
	my $teacher_table;
	my $standard_table;
	$threshold =~ s/%//;
	my $qry = "SELECT class_name, grade FROM tj_classes where class_id = ?";
	my $rst = $env{'dbh'}->prepare($qry);
	my $rejected = 0;
	$rst->execute($class_id);
	my $row = $rst->fetchrow_hashref();
	my $class_name = $$row{'class_name'};
	my $class_grade = $$row{'grade'};
	$qry = "SELECT district_name FROM districts where district_id = ?";
	$rst = $env{'dbh'}->prepare($qry);
	$rst->execute($district_id);
	$row = $rst->fetchrow_hashref();
	my $district_name = $$row{'district_name'};
	my $report_days = &weekdays_between_dates($start_date, $end_date);
	my $individual_filter = '';
	if ($r->param('submenu') eq 'mine') {
		$individual_filter = " AND t1.user_id = $env{'user_id'}";
	}
 	$qry = "SELECT t1.user_id, t1.duration AS class_duration, t2.duration AS standard_percent, t1.date_taught,
		 	t3.title, t3.id as standard_id, t3.sequence, t3.framework_id, t3.description, t3.grade
			FROM tj_journal t1
			LEFT JOIN tj_journal_topic t2 ON t2.journal_id = t1.journal_id
			LEFT JOIN framework_items t3 ON t3.id = t2.framework_id 
			WHERE t1.date_taught > ? AND
			t1.date_taught < ? AND
			dayofweek(t1.date_taught) <> 1 AND
			dayofweek(t1.date_taught) <> 7 AND
			t1.user_id IN (SELECT user_id FROM user_locs, locations WHERE user_locs.loc_id = locations.location_id AND locations.district_id = ?) AND
			t1.class_id = ?
			$individual_filter 
			ORDER BY t3.sequence, t1.date_taught, t1.user_id";
	$rst = $env{'dbh'}->prepare($qry);
	$rst->execute($start_date, $end_date, $district_id,$class_id );
	my %teachers;
	my %standards;
	my $done_one = 0;
	my $row_counter = 0;
	while (my $row = $rst->fetchrow_hashref()) {
		if (! $done_one) {
			$done_one = 1;
		}
		my $day_entered = 0;
		if (! $teachers{$$row{'user_id'}}{'dates_taught'}{$$row{'date_taught'}}) {
			$earliest_date = $$row{'date_taught'} lt $earliest_date?$$row{'date_taught'}:$earliest_date;
			$latest_date = $$row{'date_taught'} gt $latest_date?$$row{'date_taught'}:$latest_date; 
			$teachers{$$row{'user_id'}}{'days'} ++;
			$teachers{$$row{'user_id'}}{'dates_taught'}{$$row{'date_taught'}} = 1;
			$day_entered = 1;
		}
		if ($$row{'framework_id'} eq '1' || $$row{'standard_id'} eq '10201') {
			if ($day_entered) {
				$teachers{$$row{'user_id'}}{'mathdays'} ++;
			}
			if ($day_entered == 1) {
				$teachers{$$row{'user_id'}}{'total_reported_minutes'} += $$row{'class_duration'};
			}
			$standards{$$row{'standard_id'}}{'count'}++;
			if ($$row{'standard_id'} ne '10201') {
				
				$teachers{$$row{'user_id'}}{'standards'}{$$row{'standard_id'}}{'n'} ++;
				$teachers{$$row{'user_id'}}{'standards'}{$$row{'standard_id'}}{'minutes'} += ($$row{'class_duration'} * $$row{'standard_percent'})/100;
				$teachers{$$row{'user_id'}}{'total'} ++;
				if ($$row{'grade'} < $class_grade) {
					$teachers{$$row{'user_id'}}{'below_grade_mins'} += ($$row{'class_duration'} * $$row{'standard_percent'})/100;
				} elsif ($$row{'grade'} > $class_grade) {
					$teachers{$$row{'user_id'}}{'above_grade_mins'} += ($$row{'class_duration'} * $$row{'standard_percent'})/100;
				} else {
					$teachers{$$row{'user_id'}}{'at_grade_mins'} += ($$row{'class_duration'} * $$row{'standard_percent'})/100;
				}
			} else {
				$teachers{$$row{'user_id'}}{'other_math_topic_mins'} += ($$row{'class_duration'} * $$row{'standard_percent'})/100;
			}				
			if ($teachers{$$row{'user_id'}}{'standards'}{$$row{'standard_id'}}{'n'} == 1) {
				if ($$row{'standard_id'} ne '10201') {
					if ($$row{'grade'} < $class_grade) {
						$teachers{$$row{'user_id'}}{'below_grade'} ++;
					} elsif ($$row{'grade'} > $class_grade) {
						$teachers{$$row{'user_id'}}{'above_grade'} ++;
					} else {
						$teachers{$$row{'user_id'}}{'at_grade'} ++;
					}
					$teachers{$$row{'user_id'}}{'standard_count'} ++;
				} else {
					$teachers{$$row{'user_id'}}{'other_math_topic'} ++;
				}			
			}
			$standards{$$row{'standard_id'}}{'sequence'} = $$row{'sequence'};
			$standards{$$row{'standard_id'}}{'description'} = $$row{'description'};
			$standards{$$row{'standard_id'}}{'title'} = $$row{'title'};
			$standards{$$row{'standard_id'}}{'teachers'}{$$row{'user_id'}}{'count'} ++;
			$standards{$$row{'standard_id'}}{'teachers'}{$$row{'user_id'}}{'total'} += ($$row{'class_duration'} * $$row{'standard_percent'})/100;
		} elsif ($$row{'title'} eq 'Other Content Topics' && $day_entered) {
			$teachers{$$row{'user_id'}}{'mathdays'} ++;
			print STDERR "other topic here \n";
		} else {
			# print STDERR "\n nothing $$row{'framework_id'} is framework id";
		}
	}
	if (! $done_one) {
		$r->print('<div style="padding:4px;text-align:left;width:350px;background-color:#ffeeee;border-width:1px;border-style:solid;border-color:#888888;display:block">');
		$r->print("<div>Summary of $district_name, $class_name returned no entries</div>");
		$r->print('<div style="margin-top:4px"> Please select another grade.</div>');
		$r->print('</div>');

	} elsif (scalar(keys(%teachers)) < 3) {
		$r->print('<div style="padding:4px;text-align:left;width:350px;background-color:#ffeeee;border-width:1px;border-style:solid;border-color:#888888;display:block">');
		$r->print('<div>There are fewer than three participating teachers in the selected grade. Results are not displayed to preserve anonymity.</div>
		<div style="margin-top:4px"> Please select another grade.</div>');
		$r->print('</div>');
	} else {
		$teacher_table = '';
		$teacher_table .= '<table><thead>
			<tr><th colspan="10">Summary by Teacher for ' . $report_days . ' reporting days
			<img height="15" width="15" helpid="help02" onmouseover="mouseoverhelp(this)" onmouseout="mouseouthelp()" src="../images/helpsmall.png" /></th></tr>
			<tr><th>&nbsp;</th>
			<th>Days</th>
			<th>Math Days</th>
			<th>Avg Class Dur.</th>
			<th>Num Stds</th>
			<th>&lt; Grade</th>
			<th>= Grade</th>
			<th>&gt; Grade</th>
			<th>Non-CCSSM</th>
			<th>Unreported</th>
			</tr></thead><tbody>';
		
		foreach my $key (keys(%teachers)) {
			my $percent_complete = $teachers{$key}{'days'}/$report_days;
			$teachers{$key}{'completion'} = $percent_complete;
			my $standards = $teachers{$key}{'standards'};
			my $total_standards_taught = $teachers{$key}{'standard_count'};
			if (!($percent_complete < $threshold/100)) {
				$row_counter ++;
				my $percent_math_days = $teachers{$key}{'mathdays'}/$teachers{$key}{'days'} * 100;
				my $avg_class_duration = 'na';
				my $percent_at_grade = 'na';
				my $percent_below_grade = 'na';
				my $percent_above_grade = 'na';
				my $percent_other_math = 'na';
				my $at_grade = $teachers{$key}{'at_grade'};
				my $below_grade = $teachers{$key}{'below_grade'};
				my $above_grade = $teachers{$key}{'above_grade'};
				my $other_math_topics = $teachers{$key}{'other_math_topic'};
				my $at_grade_mins = $teachers{$key}{'at_grade_mins'};
				my $below_grade_mins = $teachers{$key}{'below_grade_mins'};
				my $above_grade_mins = $teachers{$key}{'above_grade_mins'};
				my $other_math_mins = $teachers{$key}{'other_math_topic_mins'};
				if ($teachers{$key}{'mathdays'} > 0) {
					print STDERR "doing % stuff \n";
					print STDERR $teachers{$key}{'total_reported_minutes'} . " is total reported minutes \n";
					print STDERR $at_grade . ', ' . $below_grade . ',  are at and below grade \n';
					$avg_class_duration = $teachers{$key}{'total_reported_minutes'}/$teachers{$key}{'mathdays'};
					$percent_at_grade = sprintf('%.0f',($at_grade_mins/$teachers{$key}{'total_reported_minutes'}) * 100);
					$percent_below_grade = sprintf('%.0f',($below_grade_mins/$teachers{$key}{'total_reported_minutes'}) * 100);
					$percent_above_grade = sprintf('%.0f',($above_grade_mins/$teachers{$key}{'total_reported_minutes'}) * 100);
					$percent_other_math = sprintf('%.0f',($other_math_mins/$teachers{$key}{'total_reported_minutes'}) * 100);
					$percent_at_grade = $percent_at_grade > 100?100:$percent_at_grade;
					$percent_below_grade = $percent_below_grade > 100?100:$percent_below_grade;
					$percent_above_grade = $percent_above_grade > 100?100:$percent_above_grade;
					$percent_other_math = $percent_other_math > 100?100:$percent_other_math;
				}
				
				my $unaccounted_percent = 100 - ($percent_at_grade + $percent_below_grade + $percent_above_grade + $percent_other_math);
				$unaccounted_percent = $unaccounted_percent < 0?0:$unaccounted_percent;
				$teacher_table .= "<tr teacherid=" . '"' . $key . '"'. "><td>$row_counter</td>
				<td>$teachers{$key}{'days'} (" . sprintf('%.0f',$percent_complete * 100) . "%)</td>
				<td>$teachers{$key}{'mathdays'} (" . sprintf('%.0f',$percent_math_days) . "%)</td>
				<td>" . sprintf('%.0f',$avg_class_duration) . "</td>
				<td>$total_standards_taught</td>
				<td>$below_grade ($percent_below_grade%)</td>
				<td>$at_grade ($percent_at_grade%)</td>
				<td>$above_grade ($percent_above_grade%)</td>
				<td>($percent_other_math%)</td>
				<td>($unaccounted_percent%)</td></tr>
				";
			} else {
				$rejected ++;
			}
		}
		$teacher_table .= '</tbody></table>';
		$standard_table = "<table>";
		$standard_table .= '<thead><tr><th colspan="4">Grade Level Summary
		<img height="15" width="15" helpid="help03" onmouseover="mouseoverhelp(this)" onmouseout="mouseouthelp()" src="../images/helpsmall.png" />
		</th></tr></thead>';
		$standard_table .= '<thead><tr><th onclick="sortonsequence()">Code
		<image id="codesort" src="../images/ascending.png" /></th><th onclick="sortonnumteachers()"># Teachers<image id="numteacherssort" src="../images/ascendinggray.png" /></th>
		<th onclick="sortonavgpercent()">Avg %<image id="percentsort" src="../images/ascendinggray.png" />
		<th>Range of Days</th>
		</tr></thead><tbody id="standards">';
		my %sequence_hash;
		foreach my $key(keys(%standards)) {
			$sequence_hash{$standards{$key}{'sequence'}} = $key;
		}
		foreach my $sequence(sort {$a <=> $b} keys(%sequence_hash)) {
			my $key = $sequence_hash{$sequence};
			my $standard_teachers = $standards{$key}{'teachers'};
			my $num_teachers = 0;
			my $sum_percentage = 0;
			my $min_days = 999;
			my $max_days = 0;
			foreach my $teacher(keys(%$standard_teachers)) {
				if ($teachers{$teacher}{'completion'} > ($threshold/100)) {
					$num_teachers ++;
					$min_days = $$standard_teachers{$teacher}{'count'} < $min_days?$$standard_teachers{$teacher}{'count'}:$min_days;
					$max_days = $$standard_teachers{$teacher}{'count'} > $max_days?$$standard_teachers{$teacher}{'count'}:$max_days;
					#print STDERR "\n std total: " . $$standard_teachers{$teacher}{'total'};
					#print STDERR ", total teach time: " . $teachers{$teacher}{'total_reported_minutes'};
					$sum_percentage += $$standard_teachers{$teacher}{'total'}/$teachers{$teacher}{'total_reported_minutes'};
				}
			}
			my $mean_percentage;
			if ($num_teachers > 0) {
				$mean_percentage = ($sum_percentage/$num_teachers) * 100;
			} 
			if ($mean_percentage > 0) {
				my $description = $standards{$key}{'description'};
				$description =~ s/"/&quot;/g;
				$standard_table .= "<tr sequence=" . $standards{$key}{'sequence'} . '>
					<td onmouseover="mouseoverstandard(this,' . "'<b>$standards{$key}{'title'}</b><br />$description'" . ')" onmouseout="mouseoutstandard()">' . "$standards{$key}{'title'}</td>
					<td>$num_teachers</td>
					<td>" . sprintf('%.2f', $mean_percentage) . "%</td>
					<td>$min_days - $max_days</td>
					</tr>";
			}
		}
		
		$standard_table .= "</tbody></table>";
		my $total = $row_counter + $rejected;
		$overall_summary_table = '<table>';
		$overall_summary_table .= '<thead><tr><th colspan="4">';
		$overall_summary_table .= "Summary for $total Teachers ($report_days reporting days)" .
		'<img height="15" width="15" helpid="help01" onmouseover="mouseoverhelp(this)" onmouseout="mouseouthelp()" src="../images/helpsmall.png" />'
		. "</th></tr>";
		$overall_summary_table .= '</th><tr><th>&lt; Comp. %</th><th>Included</th><th>Earliest</th><th>Latest</th></tr>';
		$overall_summary_table .= "<tr><td>$rejected</td><td>$row_counter</td><td>$earliest_date</td><td>$latest_date</td></tr></table>";
		$r->print($overall_summary_table);
		$r->print($teacher_table);
		$r->print($standard_table);
	}
	
}
sub get_journal_summary_javascript {
	my ($r) = @_;
	my $district_id = $r->param('districtid')?$r->param('districtid'):13;
	my $submenu = $r->param('submenu');
	my $token = $env{'token'};
	my $output = qq~
	<script type="application/javascript">
	var asc1 = 1;
	var asc2 = 1;
	var asc3 = 1;
	document.getElementById('updateButton').disabled = true;
    \$(function() {
     \$( "#startdate" ).datepicker({ dateFormat: "yy-mm-dd" });
    });
    \$(function() {
     \$( "#enddate" ).datepicker({ dateFormat: "yy-mm-dd" });
    });
	function onDistrictSelect() {
		document.getElementById('statusMessage').innerHTML = "Retrieving Classes for selected district . . . ";
		var district_id = document.getElementById('districtid').value;
		getDistrictClasses(district_id);
		document.getElementById('statusMessage').innerHTML = "Retrieving Classes for selected district . . . ";
	}
	function buttonClicked() {
		document.getElementById('statusMessage').innerHTML = "Updating table . . . ";
		document.getElementById('updateButton').disabled = true;
		getDistrictClassSummary();
		
	}
	function mouseoverhelp(imageElement) {
		var helpid = imageElement.getAttribute("helpid");
		var helpText = document.getElementById(helpid).innerHTML;
		var top = imageElement.offsetTop;
		var left = imageElement.offsetLeft;
		var oTop = imageElement.offsetTop;
		var oLeft = imageElement.offsetLeft;
		var message = '<br />Offset for imageElement ' + ' top: ' + top + ' left: ' + left;
		baseElement = imageElement;
		while (parentElement = baseElement.offsetParent) {
			message += '<br />offset for ' + parentElement + ' top: ' + parentElement.offsetTop + ' left: ' + parentElement.offsetLeft;
			top += parentElement.offsetTop;
			left += parentElement.offsetLeft;
			message += '<br />computed top: ' + top + ' left: ' + left;
			baseElement = parentElement;
		}
		var target = document.getElementById('helpDisplay');
		target.innerHTML = helpText;
		target.style.display = "block";
		target.style.left = (left - 50) + 'px';
		target.style.top = (top - 10) + 'px';
		console.log('mouseoverhelp ' + helpText);
	}
	function mouseouthelp() {
		document.getElementById('helpDisplay').style.display = "none";
		console.log('mouseouthelp');
	}
	function mouseoverstandard(cell, standardText) {
		var top = cell.offsetTop + cell.offsetParent.offsetTop;
		var left = cell.offsetLeft + cell.offsetParent.offsetLeft;
		var screenHeight = screen.height - 60;
		var scroller = document.getElementById('interiorContent');
		var scrollTopOffset = scroller.scrollTop - (scroller.offsetTop + scroller.offsetParent.offsetTop);
		var target = document.getElementById('standardText');
		target.innerHTML = standardText;
		target.style.display = "block";
		target.style.position = "absolute";
		target.style.left = (left + 50) + 'px';
		console.log('adjusting top is ' + top + ' box is ' + target.offsetHeight + ' scroll pos is ' + scrollTopOffset );		
		if ((target.offsetHeight + top - scrollTopOffset) > screenHeight) {
			top = top - ((target.offsetHeight + top - scrollTopOffset) - screenHeight);
			console.log('new top is ' + top);
		}
		target.style.top = top + 'px';
	}
	function mouseoutstandard() {
		document.getElementById('standardText').style.display = "none";
	}
	function sortonnumteachers() {
		console.log('sort on num teachers');
		var sortSource = document.getElementById('standards');
		sortTable(sortSource, 1,1);
	}
	function sortonavgpercent() {
		var tbody = document.getElementById('standards');
		var rows = tbody.rows;
		var numRows = rows.length;
		var sortInfo = new Array();
		var sortArray = new Array();
		for (row = 0; row < numRows; row ++) {
			var sequence = rows[row].cells[2].innerHTML;
			sequence = sequence.replace("%","");
			if (!sortInfo[sequence]) {
				sortArray.push(sequence);
				sortInfo[sequence] = new Array();
				sortInfo[sequence].push(row);
			} else {
				sortInfo[sequence].push(row);
			}
		}
		if (asc3 == 1) {
			sortArray.sort(function(a,b){return a-b});
			asc3 = 0
		} else {
			sortArray.sort(function(a,b){return b-a});
			asc3 = 1
		}
		var newInnerHTML = '';
		var newRows = new Array();
		for (val = 0;val < sortArray.length;val ++) {
			for (newRow = 0; newRow < sortInfo[sortArray[val]].length; newRow++){
				var seqvalue = rows[sortInfo[sortArray[val]][newRow]].getAttribute('sequence');			
				newInnerHTML += '<tr sequence="' + seqvalue + '">' + rows[sortInfo[sortArray[val]][newRow]].innerHTML + '</tr>';
			}
		}
		tbody.innerHTML = newInnerHTML;
		updateSortIcons(3);
	}
	function sortonsequence() {
		console.log('sort on sequence');
		var tbody = document.getElementById('standards');
		var rows = tbody.rows;
		var numRows = rows.length;
		var sortInfo = new Array();
		var sortArray = new Array();
		for (row = 0; row < numRows; row ++) {
			var sequence = rows[row].getAttribute('sequence');
			if (!sortInfo[sequence]) {
				sortArray.push(sequence);
				sortInfo[sequence] = new Array();
				sortInfo[sequence].push(row);
			} else {
				sortInfo[sequence].push(row);
			}
		}
		if (asc1 == 1) {
			sortArray.sort(function(a,b){return a-b});
			asc1 = 0
		} else {
			sortArray.sort(function(a,b){return b-a});
			asc1 = 1
		}
		var newInnerHTML = '';
		var newRows = new Array();
		for (val = 0;val < sortArray.length;val ++) {
			for (newRow = 0; newRow < sortInfo[sortArray[val]].length; newRow++){
				var seqvalue = rows[sortInfo[sortArray[val]][newRow]].getAttribute('sequence');			
				newInnerHTML += '<tr sequence="' + seqvalue + '">' + rows[sortInfo[sortArray[val]][newRow]].innerHTML + '</tr>';
			}
		}
		tbody.innerHTML = newInnerHTML;
		updateSortIcons(1);
	}
	function sortTable(tbody, col, asc) {
		var rows = tbody.rows;
		var numRows = rows.length;
		var sortInfo = new Array();
		var sortArray = new Array();
		for (row = 0; row < numRows; row++) {
			var sequence = rows[row].cells[1];
			if (!sortInfo[sequence.innerHTML]) {
				sortArray.push(sequence.innerHTML);
				sortInfo[sequence.innerHTML] = new Array();
				sortInfo[sequence.innerHTML].push(row);
			} else {
				sortInfo[sequence.innerHTML].push(row);
			}
		}
		if (asc2 == 1) {
			sortArray.sort(function(a,b){return a-b});
			asc2 = 0
		} else {
			sortArray.sort(function(a,b){return b-a});
			asc2 = 1
		}
		var unique = sortArray.length;
		var newInnerHTML = '';
		var newRows = new Array();
		for (val = 0;val < unique;val ++) {
			for (newRow = 0; newRow < sortInfo[sortArray[val]].length; newRow++){
				var seqvalue = rows[sortInfo[sortArray[val]][newRow]].getAttribute('sequence');
				newInnerHTML += '<tr sequence="' + seqvalue + '">' + rows[sortInfo[sortArray[val]][newRow]].innerHTML + '</tr>';
			}
		}
		tbody.innerHTML = newInnerHTML;
		updateSortIcons(2);
	}
	function updateSortIcons(columnNum) {
		col1 = document.getElementById('codesort');
		col2 = document.getElementById('numteacherssort');
		col3 = document.getElementById('percentsort');
		if (columnNum == 1) {
			if (asc1 == 0) {
				col1.src = "../images/ascending.png";
			} else {
				col1.src = "../images/descending.png"
			}
			if (asc2 == 0) {
				col2.src = "../images/ascendinggray.png";
			} else {
				col2.src = "../images/descendinggray.png";
			}
			if (asc3 == 0) {
				col3.src = "../images/ascendinggray.png";
			} else {
				col3.src = "../images/descendinggray.png";
			}
		}
		if (columnNum == 2) {
			if (asc2 == 0) {
				col2.src = "../images/ascending.png";
			} else {
				col2.src = "../images/descending.png";
			}
			if (asc1 == 0) {
				col1.src = "../images/ascendinggray.png";
			} else {
				col1.src = "../images/descendinggray.png";
			}
			if (asc3 == 0) {
				col3.src = "../images/ascendinggray.png";
			} else {
				col3.src = "../images/descendinggray.png";
			}
		}
		if (columnNum == 3) {
			if (asc3 == 0) {
				col3.src = "../images/ascending.png";
			} else {
				col3.src = "../images/descending.png";
			}
			if (asc1 == 0) {
				col1.src = "../images/ascendinggray.png";
			} else {
				col1.src = "../images/descendinggray.png";
			}
			if (asc2 == 0) {
				col2.src = "../images/ascendinggray.png";
			} else {
				col2.src = "../images/descendinggray.png";
			}
		
		}
	}
	function classSelectorChange() {
		document.getElementById('updateButton').disabled = false;
	}
	function createGetDataObject(str) {
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
		return(xmlHttp);
	}
	function getDistrictClassSummary(district_id, class_id) {
		document.getElementById('statusMessage').innerHTML = "in getdistrictclasssummary function";
		var xmlHttp = createGetDataObject('');
        xmlHttp.onreadystatechange = function() {
            if(xmlHttp.readyState==4) {
				document.getElementById('statusMessage').innerHTML = "District class summary retrieved. ";
                // Get the data from the server's response
				document.getElementById('summaryTable').innerHTML = xmlHttp.responseText;
            	document.getElementById('updateButton').disabled = true;
			}
        }
		class_id = document.getElementById('classid').value;
		start_date = document.getElementById('startdate').value;
		end_date = document.getElementById('enddate').value;
		threshold = document.getElementById('threshold').value;
        token = "$token";
		districtid = document.getElementById('districtid').value;
        xmlHttp.open("GET","promse/journal?action=getdistrictclassesummary;submenu=$submenu;token=$token;districtid=" + districtid + ";classid=" + class_id + ";startdate=" + start_date + ";enddate=" + end_date + ";threshold=" + threshold,true);
        xmlHttp.send(null);
	}
	function getData(str) {
		getFramework(str);
		getEntries(str);
	}
	function displayStandards(str) {
		var activeCanvas = document.getElementById('canvasOne');
		var ctx = activeCanvas.getContext("2d");
		ctx.fillRect(20,20,20,20);
		console.log("finished display standards");
	}
	function getDistrictClasses(district_id) {
		document.getElementById('statusMessage').innerHTML = "in getting classes routine districtid is " + district_id;
		var xmlHttp = createGetDataObject('');
        xmlHttp.onreadystatechange = function() {
            if(xmlHttp.readyState==4) {
				document.getElementById('statusMessage').innerHTML = "Classes retrieved ";
                // Get the data from the server's response
 			    document.getElementById('classselector').innerHTML = xmlHttp.responseText;
				console.log('class selector width is ' + document.getElementById('classid').offsetWidth);
				document.getElementById('districtid').style.width = document.getElementById('classid').offsetWidth + 'px';
				document.getElementById('controlPanel').offsetWidth = 600;
            	document.getElementById('updateButton').disabled = false;
			}
        }

        token = "$token";
        xmlHttp.open("GET","promse/journal?action=getdistrictclasses;token=$token;districtid=$district_id",true);
        xmlHttp.send(null);
		
	}
    function getEntries(str) {
        var xmlHttp = createGetDataObject('');
		console.log('getting data');
        document.getElementById("statusMessage").innerHTML="Retrieving . . .";
        xmlHttp.onreadystatechange = function() {
            if(xmlHttp.readyState==4) {
				console.log("ready state 4 in get entries");
                // Get the data from the server's response
                var display = "";
                xmlHttp.responseText;
                entries = eval("(" + xmlHttp.responseText + ")");
				console.log("retrieved entries is: " + entries[9986]);
				console.log("total keys of that are: " + Object.keys(entries));
				standards = entries;
				displayStandards('');
                document.getElementById("statusMessage").innerHTML=standards.length + ' is the entries standards length '; 
            }
        }
        filter = str;
        token = "$token";
        xmlHttp.open("GET","static_queries/tjjournal_summary.json",true);
        xmlHttp.send(null);
    }
    function getFramework(str) {
        var xmlHttp = createGetDataObject('');
		console.log('getting data');
        document.getElementById("statusMessage").innerHTML="Retrieving . . .";
        xmlHttp.onreadystatechange = function() {
            if(xmlHttp.readyState==4) {
				console.log("ready state 4 in get framework");
                // Get the data from the server's response
                var display = "";
                xmlHttp.responseText;
                framework = eval("(" + xmlHttp.responseText + ")");
				grades = framework.children;
                document.getElementById("statusMessage").innerHTML=grades.length + ' is the framework grades length '; 
            }
        }
        filter = str;
        token = "$token";
        xmlHttp.open("GET","framework1.jsn",true);
        xmlHttp.send(null);
    }
	function canvasClicked(e) {
		console.log(e.id);
		var canvasID = e.id;
		e.style.display = 'none';
		if (canvasID == 'canvasOne') {
			document.getElementById('canvasTwo').style.display = 'block';
		} else {
			document.getElementById('canvasOne').style.display = 'block';
		}
		
	}
	</script>
	~; 
	return($output);
}
sub get_disclaimer {
	my $output = qq~
	<div style="float:left;
		background-color:#eeffff;
		width:400px;
		border-style:solid;border-width:1px;border-color:#cccccc;
		text-align:left;
		padding:3px;">
	<div style="width:100%;text-align:center">
	
	<b style="text-align:center;width:100%">Teacher Journal Summary</b>
 	</div>
	<div style="margin-top:3px;">
	This site provides summaries of data reported by participating teachers in your district.
 	</div>
	<div style="margin-top:3px;">
	<b>&quot;Reporting days&quot;</b> includes every Monday through Friday for the time period selected.
	 <b>&quot;Completion percent&quot;</b> represents the proportion of school days reported by a teacher. 
	 The greater the number of teachers included in your summary who have entered information for all reporting days, 
	 the more accurate the representation will be for the typical coverage at that grade level.
 	</div>
	<div style="margin-top:3px;">
	If too many teachers have a large number of missing days (low &quot;Comp %&quot;), caution should be used in interpreting the data. 
	However, the data can be used to identify issues in need of further study.
 	</div>
	<div style="margin-top:3px;">
	To protect confidentiality, results from any grade with fewer than three teachers will not be reviewable.
	</div>
	</div>
	~;
	return($output);
}

sub get_journal_summary_help {
	my $output = qq~
	<div style="display:none;text-align:left;" id="help01">
	<b>Summary of Teachers</b>
	<table>
	<tr><td style="text-align:right;width:55px"><b>Title</b></td><td style="text-align:left">Shows number of participating teachers in the selected grade. <i>Reporting Days</i> 
	is the number of days between <i>Start Date</i> and <i>End Date</i> excluding weekends.</td></tr>
	
	<tr><td style="text-align:right;"><b>&lt; Comp %</b></td><td style="text-align:left">Number of teachers not meeting the selected <i>Completion %</i></td></tr>
	<tr><td style="text-align:right"><b>Included</b></td><td style="text-align:left">Number of Teachers meeting the selected Completion %</td></tr>
	<tr><td style="text-align:right"><b>Earliest</b></td><td style="text-align:left">The earliest date that at least one teachers reported data.</td></tr>
	<tr><td style="text-align:right"><b>Latest</b></td><td style="text-align:left">The latest date that at least one teachers reported data.</td></tr>
	</table>
	</div>
	
	<div style="display:none" id="help02">
		<b>Summary by Teacher</b><br />
		<table>
		<tr><td style="text-align:right"><b>Days</b></td><td style="text-align:left">Number of days with journal entry<br />(% of <i>reporting days</i> with reports.)</td></tr>
		<tr><td style="text-align:right"><b>Math Days</b></td><td style="text-align:left">Number of days with reported math activity<br />(% of reported days with math activity)</td></tr>
		<tr><td style="text-align:right"><b>Avg Class Dur</b></td><td style="text-align:left">Average class period length in minutes</td></tr>
		<tr><td style="text-align:right"><b>Num Stds</b></td><td style="text-align:left">Number of CCSSM standards covered</td></tr>
		<tr><td style="text-align:right"><b>&lt; Grade</b></td><td style="text-align:left">Number of CCSSM standards below class grade<br />(% of teaching time)</td></tr>
		<tr><td style="text-align:right"><b>= Grade</b></td><td style="text-align:left">Number of CCSSM standards at class grade<br />(% of teaching time)</td></tr>
		<tr><td style="text-align:right"><b>&gt; Grade</b></td><td style="text-align:left">Number of CCSSM standards above class grade<br />(% of teaching time)</td></tr>
		<tr><td style="text-align:right"><b>Non-CCSSM</b></td><td style="text-align:left">(% of teaching time on math topics not in CCSSM)</td></tr>
		<tr><td style="text-align:right"><b>Unreported</b></td><td style="text-align:left">(% of teaching time without reported math activity)</td></tr>
		</table>
	</div>
	
	<div style="display:none" id="help03"><b>Grade Level Summary</b>
	<table>
	<tr><td style="text-align:right"><b>Code</b></td><td style="text-align:left">The CCSSM Code covered by at least one teacher</td></tr>
	<tr><td style="text-align:right"><b># Teachers</b></td><td style="text-align:left">Number of teachers covering the standard</td></tr>
	<tr><td style="text-align:right"><b>Avg %</b></td><td style="text-align:left">Average % of teaching time devoted to the standard</td></tr>
	<tr><td style="text-align:right"><b>Range of Days</b></td><td style="text-align:left">Minimum and maximum days standard was addressed</td></tr>
	
	</table>
	Sort on any column by clicking <img src="../images/ascending.png" /> or <img src="../images/descending.png" />
	
	</div>
	
	<div style="display:none" id="help04"><b>Control Panel</b>
	<br />Selects subset of teachers for summary.
	<table>
	<tr><td style="text-align:right"><b>District</b></td><td style="text-align:left">(Admin version only) Selecting district retrieves Course/Grade selector</td></tr>
	<tr><td style="text-align:right"><b>Course/Grade</b></td><td style="text-align:left">Selects course or grade for summary</td></tr>
	<tr><td style="text-align:right"><b>Start Date</b></td><td style="text-align:left">Selects start date for period of interest</td></tr>
	<tr><td style="text-align:right"><b>End Date</b></td><td style="text-align:left">Selects end date for period of interest</td></tr>
	<tr><td style="text-align:right"><b>Completion %</b></td><td style="text-align:left">Set the minimum criterion of the percent of days reported (excluding weekends)</td></tr>
	<tr><td style="text-align:right"><b>Update Tables</b></td><td style="text-align:left">Retrieve the summary according to the panel settings</td></tr>
	</table>
	</div>
	~;
	return($output);
}
sub get_user_log_old {
	my ($r,$passed_user_id,$get_all) = @_;
	my $start_record = $r->param('start')?$r->param('start'):0;
	my $limit_records = $r->param('limit')?$r->param('limit'):40;
	my $limit_string = "LIMIT $start_record, $limit_records";
	if ($get_all) {
		$limit_string = "";
	}
	my $course = $r->param('courseid');
	my $date_taught = $r->param('datetaught');
	my $user_id;
	if (! $passed_user_id) {
		$user_id = $env{'user_id'};
	} else {
		$user_id = $passed_user_id;
	}
	my $output;
	my $qry = "SELECT DISTINCT tj_journal.journal_id, tj_journal.date_taught, tj_journal.class_id, tj_journal_topic.framework_id, tj_journal_topic.duration,
								tj_journal_topic.background, tj_journal_topic.pages, tj_journal_topic.notes,tj_activities.activity_name,
								tj_topic_materials.material_id, cc_materials.title as material_name, tj_user_materials.material_name as user_material_name,
								tj_topic_activity.activity_id, framework_items.description, tj_classes.class_name
								FROM (tj_journal, tj_journal_topic, tj_classes, framework_items)
								LEFT JOIN (tj_topic_materials, cc_materials) 
									ON (tj_topic_materials.journal_id = tj_journal.journal_id	
										AND tj_topic_materials.topic_id = tj_journal_topic.framework_id
										AND cc_materials.id = tj_topic_materials.material_id)
								LEFT JOIN tj_user_materials ON (tj_user_materials.journal_id = tj_journal.journal_id AND tj_user_materials.topic_id = tj_journal_topic.framework_id)
								LEFT JOIN (tj_topic_activity, tj_activities) ON (tj_topic_activity.journal_id = tj_journal.journal_id AND 
										tj_topic_activity.topic_id = tj_journal_topic.framework_id AND
										tj_activities.activity_id = tj_topic_activity.activity_id)
			WHERE tj_journal.user_id = $user_id AND tj_journal_topic.journal_id AND tj_journal.journal_id = tj_journal_topic.journal_id AND
						tj_journal_topic.framework_id = framework_items.id AND
						tj_classes.class_id = tj_journal.class_id AND
						tj_journal.deleted = 0 AND tj_journal_topic.deleted = 0
			ORDER BY tj_journal.date_taught DESC,tj_journal.class_id, tj_journal.time_stamp, tj_journal_topic.framework_id
			$limit_string";
	my $rst = $env{'dbh'}->prepare($qry);
	$rst->execute();
	my %retro_report;
	my $current_journal_id = 0;
	my $current_topic_id = 0;
	my @journal_entries;
	my %journal_entry;
	my @topics;
	my $topic;
	my @activities;
	my %activity;
	my @materials;
	my %material;
	my @user_materials;
	my %user_material;
	my $first_row = 1;
	my $row_counter = 0;
	my $has_activity = 0;
	my $has_material = 0;
	my $has_user_materials = 0;
	my $did_one = 0;
	while (my $row = $rst->fetchrow_hashref()) {
		$did_one = 1;
		$row_counter ++;
		if ($current_journal_id ne $$row{'journal_id'}) {
			if (! $first_row) {
				if ($has_activity) {
					$journal_entry{'activity'} = [@activities];
				}
				@activities = ();
				$has_activity = 0;
				push (@journal_entries, {%journal_entry});
			}
			$current_journal_id = $$row{'journal_id'};
			$current_topic_id = $$row{'framework_id'};
			# here begin the journal entry
			%journal_entry=('journalid'=>$$row{'journal_id'},
							'datetaught'=>$$row{'date_taught'},
							'classid'=>$$row{'class_id'},
							'classname'=>$$row{'class_name'},
							'framework_id'=>$current_topic_id,
							'frameworktitle'=>$$row{'description'},
							'duration'=>$$row{'duration'},
							'background' => $$row{'background'},
							'pages' => $$row{'pages'},
							'notes' => $$row{'notes'});

			# every journal entry must have at least one topic
			# now need to check for activity and materials
			if ($$row{'activity_id'}) {
				%activity = ('activity_id'=>$$row{'activity_id'},
							'activity_name' => $$row{'activity_name'});
				push(@activities, {%activity});	
				$has_activity = 1;
			}
			if ($$row{'user_material_name'}) {
				$journal_entry{'usermaterials'} = $$row{'user_material_name'};
			}
			if ($$row{'material_id'}) {
				$journal_entry{'materialid'} = $$row{'material_id'};
				$journal_entry{'materialname'} = $$row{'material_name'};
			}
		} elsif ($current_topic_id ne $$row{'framework_id'})  {
			# new topic in existing journal - so store previous
			$current_topic_id = $$row{'framework_id'};
			if ($has_activity) {
				$journal_entry{'activity'} = [@activities];
			}
			push (@journal_entries, {%journal_entry});
			@activities = ();
			$has_activity = 0;
			%journal_entry=('journalid'=>$$row{'journal_id'},
							'datetaught'=>$$row{'date_taught'},
							'classid'=>$$row{'class_id'},
							'classname'=>$$row{'class_name'},
							'framework_id'=>$current_topic_id,
							'frameworktitle'=>$$row{'description'},
							'duration'=>$$row{'duration'},
							'background' => $$row{'background'},
							'pages' => $$row{'pages'},
							'notes' => $$row{'notes'});
			if ($$row{'activity_id'}) {
				%activity = ('activity_id'=>$$row{'activity_id'},
							'activity_name' => $$row{'activity_name'});
				push(@activities, {%activity});	
				$has_activity = 1;
			}
			if ($$row{'user_material_name'}) {
				$journal_entry{'usermaterials'} = $$row{'user_material_name'};
			}
			if ($$row{'material_id'}) {
				$journal_entry{'materialid'} = $$row{'material_id'};
				$journal_entry{'materialname'} = $$row{'material_name'};
			}
		} else {
			if ($$row{'activity_id'}) {
				%activity = ('activity_id'=>$$row{'activity_id'},
							'activity_name' => $$row{'activity_name'});
				push(@activities, {%activity});	
				$has_activity = 1;				
			}
		}
		$first_row = 0;
	}
	if ($did_one) {
		if ($has_activity) {
			$journal_entry{'activity'} = [@activities];
		}
		push(@journal_entries,{%journal_entry});
	}
	$retro_report{'userlog'} = [@journal_entries];
	if ($passed_user_id) {
		return(\%retro_report);
	} else {
		$output = JSON::XS::->new->pretty(1)->encode( \%retro_report);
		return($output);
	}
}

	sub build_topic {
		my ($row) = @_;
		my %topic = ('framework_id'=>$$row{'framework_id'},
				'frameworktitle'=>$$row{'description'},
				'duration'=>$$row{'duration'},
				'background' => $$row{'background'},
				'pages' => $$row{'pages'},
				'notes' => $$row{'notes'});
		return(\%topic);
	}
	sub get_lesson_array_old {
		my ($r) = @_;
		my $grade = $r->param('grade');
		my $curriculum_id = $r->param('curriculumid');
		print STDERR "\n **** new stuff \n ***** ";
		my $qry = "SELECT cc_curricula.unit_name, cc_curricula.lesson_name, cc_units.id as unit_id, cc_units.title as unit_title, 
					cc_units.description as unit_description,cc_units.grade_id,
					cc_themes.id as lesson_id, cc_math_ideas.idea, 
					cc_themes.title as lesson_title, cc_themes.description as lesson_description,
					framework_items.id as standard_id, framework_items.title as standard_title, 
					framework_items.description as standard_description,
					cc_materials.id as material_id, cc_materials.title as material_title
					FROM cc_curricula, cc_units, cc_themes
					LEFT JOIN (cc_math_ideas, cc_lesson_ideas) on cc_math_ideas.id = cc_lesson_ideas.idea_id AND cc_lesson_ideas.lesson_id = cc_themes.id
					LEFT JOIN (cc_pf_theme_tags, framework_items) on cc_pf_theme_tags.theme_id = cc_themes.id AND cc_pf_theme_tags.pf_end_id = framework_items.id
					LEFT JOIN (cc_materials, cc_material_chunks) ON cc_materials.id = cc_material_chunks.material_id AND cc_material_chunks.theme_id = cc_themes.id 
					WHERE cc_units.curriculum_id = ? AND
						cc_curricula.id = cc_units.curriculum_id AND
						cc_units.grade_id = ? AND
						cc_units.id = cc_themes.unit_id AND
						cc_themes.eliminated IS NULL
						ORDER BY cc_units.sequence, cc_themes.sequence";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute($curriculum_id, $grade);
		my %units_hash;
		my %unit;
		my %lessons_hash;
		my @lessons_array;
		my %lesson;
		my @linked_standards_array;
		my %linked_standards; #used to remember what's been linked to avoid duplicates
		my $current_lesson = 0;
		my $in_lesson = 0;
		my $first_row = 1;
		my %output;
		while (my $row = $rst->fetchrow_hashref()) {
			if (! $units_hash{$$row{'unit_id'}}) {
				$unit{'title'} = $$row{'unit_title'};
				$unit{'description'} = $$row{'unit_description'};
				$units_hash{$$row{'unit_id'}} = {%unit};
			}
			if ($current_lesson != $$row{'lesson_id'}) {
				%linked_standards = ();
				if ($in_lesson) {
					if (scalar(@linked_standards_array) == 0) {
						push @linked_standards_array, {('id' => 0)};
					}
					$lesson{'children'} = [@linked_standards_array];
					@linked_standards_array = ();
					push @lessons_array, {%lesson};
				}
				$lessons_hash{$current_lesson} = {%lesson};
				%lesson = ();
				$lesson{'leaf'} = 'false';
				$lesson{'item_type'} = "lesson";
				$lesson{'grade_id'} = $$row{'grade_id'};
				$lesson{'item_description'} = $$row{'lesson_description'};
				$lesson{'item_title'} = $$row{'lesson_title'};
				$lesson{'item_id'} = $$row{'lesson_id'};
				$current_lesson = $$row{'lesson_id'};
			} 
			if ($$row{'standard_id'}) {
				if (! $linked_standards{$$row{'standard_id'}}) {
					push @linked_standards_array, {('item_type' => "standard",
												'item_id' => $$row{'standard_id'},
												'item_title' => $$row{'standard_title'},
												'item_description' => $$row{'standard_description'},
												'leaf' => "true")};
					$linked_standards{$$row{'standard_id'}} = 1;
				}
			}
			
			$in_lesson = 1;
		}


		print $r->header(-type => 'application/json',
	                    -expires => 'now');
		$output{'children'} = [@lessons_array];
		$r->print(JSON::XS::->new->pretty(1)->encode( \%output));			
		
	}
	sub class_id_to_grade {
		my($class_id) = @_;
		my $grade;
		my $qry = "SELECT grade FROM tj_classes where class_id = ?";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute($class_id);
		my $row = $rst->fetchrow_hashref();
		$grade = $$row{'grade'};
		return ($grade);
	}
	sub get_lesson_array {
		my ($r) = @_;
		my $no_children;
		update_user_curriculum($r);

		my $nc = '';
		if ($r->param('action') eq 'getlessonarraync') {
			$no_children = 1;
			$nc = 'nc';
		} else {
			$no_children = 0;
		}
		my $class_id = $r->param('classid');
		my $grade = &class_id_to_grade($class_id);
		my $grade_filter = '(cc_units.grade_id = ' . $grade . ')';
		#if ($grade eq '0') {
		#	$grade_filter == '(cc_units.grade_id = 0 OR cc_units.grade_id = 1)'
		#} elsif ($grade eq '9') {
		#	$grade_filter = '(cc_units.grade_id = 9 OR cc_units.grade_id = 8)'
		#} else {
		#	$grade_filter = "(cc_units.grade_id = $grade OR cc_units.grade_id = " . ($grade - 1) . " OR cc_units.grade_id = " . ($grade + 1) . ")";
		#}
		
		my $curriculum_id = $r->param('curriculumid');
		my $fh;
		my %output;
		my $file_name = "/var/www/html/static_queries/curric_". $curriculum_id . "grade_" . $grade . "$nc.jsn";
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size) = stat $file_name;
        if ($size > 0) {
			open(IN, '<' . $file_name);
			print $r->header(-type => 'application/json',
	                    -expires => 'now');
			while(<IN>){
				$r->print($_);			
			}
			
        } else {
			if (open(OUT, '>' . $file_name)) {
        	} else {
            	print STDERR "unable to open output file \n"
        	}
			my $qry = "SELECT cc_curricula.unit_name, cc_curricula.lesson_name, cc_units.id as unit_id, cc_units.title as unit_title, 
					cc_units.description as unit_description,cc_units.grade_id,
					cc_themes.id as lesson_id, cc_math_ideas.idea, 
					cc_themes.title as lesson_title, cc_themes.description as lesson_description,
					framework_items.id as standard_id, framework_items.title as standard_title, framework_items.grade as standard_grade,
					framework_items.description as standard_description,
					cc_materials.id as material_id, cc_materials.title as material_title
					FROM cc_curricula, cc_units, cc_themes
					LEFT JOIN (cc_math_ideas, cc_lesson_ideas) on cc_math_ideas.id = cc_lesson_ideas.idea_id AND cc_lesson_ideas.lesson_id = cc_themes.id
					LEFT JOIN (cc_pf_theme_tags, framework_items) on cc_pf_theme_tags.theme_id = cc_themes.id AND cc_pf_theme_tags.pf_end_id = framework_items.id
					LEFT JOIN (cc_materials, cc_material_chunks) ON cc_materials.id = cc_material_chunks.material_id AND cc_material_chunks.theme_id = cc_themes.id 
					WHERE cc_units.curriculum_id = ? AND
						cc_curricula.id = cc_units.curriculum_id AND
						$grade_filter AND
						cc_units.id = cc_themes.unit_id AND
						(cc_themes.eliminated IS NULL OR cc_themes.eliminated = 0)
						ORDER BY cc_units.sequence, cc_themes.sequence, standard_grade";
			my $rst = $env{'dbh'}->prepare($qry);
			$rst->execute($curriculum_id);
			my %units_hash;
			my %unit;
			my %lessons_hash;
			my @lessons_array;
			my %lesson;
			my @linked_standards_array;
			my @linked_standards_out_of_grade;
			my %linked_standards; #used to remember what's been linked to avoid duplicates
			my $current_lesson = 0;
			my $sequence = 10000;
			my $in_lesson = 0;
			my $first_row = 1;
			while (my $row = $rst->fetchrow_hashref()) {
			    my $grade_display = $$row{'grade_id'} eq '0'?'K':$$row{'grade_id'};
			    $grade_display = $grade_display eq '9'?'HS':$grade_display;
				if (! $units_hash{$$row{'unit_id'}}) {
					$unit{'title'} = $$row{'unit_title'};
					$unit{'description'} = $$row{'unit_description'};
					$units_hash{$$row{'unit_id'}} = {%unit};
				}
				if ($current_lesson != $$row{'lesson_id'}) {
				    $sequence ++;
					%linked_standards = ();
					if ($in_lesson) {
						if ($no_children) {
							print STDERR $current_lesson . ': ' . scalar(@linked_standards_array) . ', ';
							if (scalar(@linked_standards_array) == 0 && $$row{'grade_id'} == $grade) {
								push @lessons_array, {%lesson};
							}
							@linked_standards_array = ();
						} else {
						    my $no_in_grade = 0;
						    if (scalar(@linked_standards_array) == 0) {
						        $no_in_grade = 1;
						    }
						    my $out_of_grade_counter = 0;
						    while (my $out_of_grade = shift(@linked_standards_out_of_grade)) {
						        push @linked_standards_array,{%$out_of_grade};
						        $out_of_grade_counter ++;
						    }
							if (scalar(@linked_standards_array) == 0) {
								push @linked_standards_array, {('item_type'=>"standard",
						                                'item_title'=>"No standards for this lesson",
						                                'leaf'=>"true",
						                                'id' => 0)};
							} else {
							    if ($no_in_grade) {
    								unshift @linked_standards_array, {('item_type'=>"standard",
						                                'item_title'=>"No on-grade standards for this lesson",
						                                'leaf'=>"true",
						                                'id' => 0)};
							    }
							}
							$lesson{'children'} = [@linked_standards_array];
							@linked_standards_array = ();
							@linked_standards_out_of_grade = ();
							push @lessons_array, {%lesson};
						}
					}
					$lessons_hash{$current_lesson} = {%lesson};
					%lesson = ();
					if($no_children) {
					    $lesson{'leaf'} = 'true';
					} else {
					    $lesson{'leaf'} = 'false';
					}
					$lesson{'item_type'} = "lesson";
					$lesson{'sequence'} = $sequence;
					$lesson{'unit_title'} = "(Gd $grade_display) " . $$row{'unit_title'};
					$lesson{'grade_id'} = $$row{'grade_id'};
					$lesson{'item_description'} = "(Gd $grade_display) " . $$row{'lesson_description'};
					$lesson{'item_title'} = "(Gd $grade_display) " . $$row{'lesson_title'};
					$lesson{'item_id'} = $$row{'lesson_id'};
					$current_lesson = $$row{'lesson_id'};
				} 
				if ($$row{'standard_id'}) {
					if (! $linked_standards{$$row{'standard_id'}}) {
					    
						my %standard = ('item_type' => "standard",
												'item_id' => $$row{'standard_id'},
												'item_title' => $$row{'standard_title'},
												'item_description' => $$row{'standard_description'},
												'leaf' => "true");
						if ($$row{'standard_grade'} != $grade) {
						    push @linked_standards_out_of_grade, {%standard};
						} else {
						    push @linked_standards_array, {%standard};
						}
					    $linked_standards{$$row{'standard_id'}} = 1;
					}
				}
			
				$in_lesson = 1;
			}
			if ($in_lesson) {
				if ($no_children) {
					if (scalar(@linked_standards_array) == 0) {
						push @lessons_array, {%lesson};
					}
					@linked_standards_array = ();
				} else {
				    my $no_in_grade = 0;
				    if (scalar(@linked_standards_array) == 0) {
				        $no_in_grade = 1;
				    }
				    
				    while (my $out_of_grade = shift(@linked_standards_out_of_grade)) {
	    		        push @linked_standards_array,{%$out_of_grade};
				    }
				    
					if (scalar(@linked_standards_array) == 0) {
						push @linked_standards_array, {('item_type'=>"standard",
						                                'item_title'=>"No standards for this lesson",
						                                'leaf'=>"true",
						                                'id' => 0)};
					} else {
					    if ($no_in_grade) {
							unshift @linked_standards_array, {('item_type'=>"standard",
				                                'item_title'=>"No on-grade standards for this lesson",
				                                'leaf'=>"true",
				                                'id' => 0)};
					    }
					}
					$lesson{'children'} = [@linked_standards_array];
					@linked_standards_array = ();
					push @lessons_array, {%lesson};
				}
			}
			if (! scalar(@lessons_array) && $no_children) {
				%lesson = ();
				$lesson{'leaf'} = 'true';
				$lesson{'sequence'} = $sequence;
				$lesson{'item_type'} = "lesson";
				$lesson{'grade_id'} = '99';
				$lesson{'item_description'} = 'Each lesson at selected grade-level has a standard or there are no lessons for the selected grade-level.';
				$lesson{'item_title'} = 'Each lesson at selected grade-level has a standard or there are no lessons for the selected grade-level.';
				$lesson{'item_id'} = '0';
				push @lessons_array, {%lesson};
				
			}
			$output{'children'} = [@lessons_array];
			my $out_scalar = JSON::XS::->new->pretty(0)->encode( \%output);
			print OUT $out_scalar;
			close OUT;
			print $r->header(-type => 'application/json',
	                    -expires => 'now');
			$r->print(JSON::XS::->new->pretty(0)->encode( \%output));			
		}
	}
    sub get_standard_array_nc {
		my ($r) = @_;
		my $curriculum_id = $r->param('curriculumid');
		my $class_id = $r->param('classid');
		my $qry = "SELECT grade from tj_classes WHERE class_id = ?";
		my $sth = $env{'dbh'}->prepare($qry);
		$sth->execute($class_id);
		my $row = $sth->fetchrow_hashref();
		my $grade = $$row{'grade'};
		my $file_name = '/var/www/html/curriculum_resources/gf_curriculum_id_' . $curriculum_id. "_grade_$grade.json";
		open(IN, '<' . $file_name);
		print $r->header(-type => 'application/json',
                    -expires => 'now');
		while(<IN>){
			$r->print($_);			
		}
		close IN;
		print
    }
    sub get_schools_by_zip {
        my ($r) = @_;
        my $zip = $r->param('zip');
        my $qry = 'SELECT id as school_id, school_name FROM all_schools
                   WHERE zip = ? ORDER BY school_name';
        my $rst = $env{'dbh'}->prepare($qry);
        $rst->execute($zip);
        my @schools;
        my %select_school = ('school_id'=>0,
                            'school_name'=>'Select School');
        push @schools,{%select_school};
        while (my $row = $rst->fetchrow_hashref()) {
            push @schools,{%$row};
        }
        my %output;
        $output{'children'} = [@schools];
		print $r->header(-type => 'application/json',
                    -expires => 'now');
		$r->print(JSON::XS::->new->pretty(0)->encode( \%output));			
        
    }	
	sub get_standard_array {
		my ($r) = @_;
		my $no_children;
		my $nc = '';
		if ($r->param('action') eq 'getstandardarraync') {
			$no_children = 1;
			$nc = 'nc';
		} else {
			$no_children = 0;
		}
		my $class_id = $r->param('classid');
		my $grade = &class_id_to_grade($class_id);
		my $grade_filter = '(grade = ' . $grade . ')';
		#if ($grade eq '0') {
		#	$grade_filter == '(grade = 0 OR grade = 1)'
		#} elsif ($grade eq '9') {
		#	$grade_filter = '(grade = 9 OR grade = 8)'
		#} else {
		#	$grade_filter = "(grade = $grade OR grade = " . ($grade - 1) . " OR grade = " . ($grade + 1) . ")";
		#}
		my $curriculum_id = $r->param('curriculumid');
		my $fh;
		my %output;
		my $file_name = "/var/www/html/static_queries/standards_". $curriculum_id . "grade_" . $grade . ".jsn";
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size) = stat $file_name;
		my @standards_array;

        if ($size > 0) {
			open(IN, '<' . $file_name);
			print $r->header(-type => 'application/json',
	                    -expires => 'now');
			while(<IN>){
				$r->print($_);			
			}
			close IN;
			
        } else {
			if (open(OUT, '>' . $file_name)) {
        	} else {
            	print STDERR "unable to open output file \n"
        	}
    		my $qry = "SELECT framework_items.id as standard_id, framework_items.title as standard_code,
    		 	framework_items.grade, framework_items.description, cc_themes.id as lesson_id, cc_themes.title as lesson_title,
    			cc_themes.description as lesson_description, cc_units.title as unit_title, cc_units.grade_id as unit_grade
    		FROM (framework_items, framework_strands)
    		LEFT JOIN (cc_themes, cc_pf_theme_tags, cc_units) 
    		ON cc_pf_theme_tags.pf_end_id = framework_items.id AND 
    		cc_pf_theme_tags.theme_id = cc_themes.id AND 
    		cc_units.id = cc_themes.unit_id AND
    		cc_themes.eliminated IS NULL AND
    		cc_units.curriculum_id = ?
    		WHERE framework_items.framework_id = 1 AND
    		(framework_items.title NOT LIKE '[%') AND
    		framework_items.title > ' ' AND
    		framework_strands.`code` = framework_items.`code` AND
    		$grade_filter
    		ORDER BY framework_strands.sequence, framework_items.sequence, cc_units.grade_id
    		";
    		my $rst = $env{'dbh'}->prepare($qry);
    		$rst->execute($curriculum_id);
    		my %output;
    		my @linked_lessons_array = ();
    		my @off_grade_lessons_array = ();
    		my %standards_hash;
    		my %standard;
    		my $current_standard = 0;
    		my $in_standard = 0;
    		my $lesson_title;
    		my $sequence = 10000;
    		my $offGradeSequence = 20000;
    		while (my $row = $rst->fetchrow_hashref()) {
    			my $display_grade = $$row{'unit_grade'} eq '0'?'K':$$row{'unit_grade'};
    			$display_grade = $display_grade eq '9'?'HS':$display_grade;
    			if ($grade != $$row{'unit_grade'}) {
    			    $lesson_title = $$row{'lesson_title'};
    			} else {
    			    $lesson_title = $$row{'lesson_title'};
    			}
    			if ($current_standard != $$row{'standard_id'}) {
    			    $sequence ++;
    				if ($in_standard) {
    					if ($no_children) {
    						if (scalar(@linked_lessons_array) == 0 && $grade == $$row{'grade'}) {
    							my @dummyChildren;
    							my %dummyChild = ('item_description'=>'No additional materials',
    										'leaf'=>'true');
    							push @dummyChildren, {%dummyChild};
    							$standard{'children'} = [@dummyChildren];
    							push @standards_array, {%standard};
    						}
    						@linked_lessons_array = ();
    						@off_grade_lessons_array = ();
    					} else {
    						if (scalar(@linked_lessons_array) == 0) {
    							push @linked_lessons_array, {
    							                            ('item_id'=>0,
    							                          'item_title'=>"No on-grade lessons address this standard",
    													'leaf' => 'true')};
    						}
    						push @linked_lessons_array, @off_grade_lessons_array;
    						$standard{'children'} = [@linked_lessons_array];
    						@linked_lessons_array = ();
    						@off_grade_lessons_array = ();
    						push @standards_array, {%standard};
    					}
    				}
    				$standards_hash{$current_standard} = {%standard};
    				$in_standard = 1;
    				%standard = ();
    				$standard{'item_type'} = "standard";
    				$standard{'sequence'} = $sequence;
    				$standard{'item_title'} = $$row{'standard_code'};
    				$standard{'item_description'} = $$row{'description'};
    				$standard{'item_id'} = $$row{'standard_id'};
    				$standard{'leaf'} = 'false';
    				if ($$row{'lesson_id'} && ($$row{'lesson_id'} > 0)) {
    				    if ($$row{'unit_grade'} eq $grade) { 
           					push @linked_lessons_array, {('item_type' => 'lesson',
        					                        'item_grade'=>$$row{'unit_grade'},
        					                        'unit_title'=>"(Gd $display_grade) " . $$row{'unit_title'},
        											'item_id'=>$$row{'lesson_id'},
        											'sequence'=>$sequence,
        											'leaf'=>'true',
        											'item_description'=>"(Gd $display_grade) " . $$row{'lesson_description'},
        											'item_title'=>"(Gd $display_grade) " . $lesson_title)};
        				} else {
        				    $offGradeSequence ++;
           					push @off_grade_lessons_array, {('item_type' => 'lesson',
        					                        'item_grade'=>$$row{'unit_grade'},
        					                        'unit_title'=>"(Gd $display_grade) " . $$row{'unit_title'},
        					                        'sequence'=>$offGradeSequence,
        											'item_id'=>$$row{'lesson_id'},
        											'leaf'=>'true',
        											'item_description'=>"(Gd $display_grade) " . $$row{'lesson_description'},
        											'item_title'=>"(Gd $display_grade) " . $lesson_title)};
        				
        				}
    				}
    			} else {
    			    $sequence ++;
    			    if ($$row{'unit_grade'} eq $grade) {
    			        
        				push @linked_lessons_array, {('item_type' => 'lesson',
        											'item_id'=>$$row{'lesson_id'},
        											'sequence'=>$sequence,
        											'item_grade'=>$$row{'unit_grade'},
        											'unit_title'=>"(Gd $display_grade) " . $$row{'unit_title'},
        											'leaf'=>'true',
        											'item_description'=>"(Gd $display_grade) " . $$row{'lesson_description'},
        											'item_title'=>"(Gd $display_grade) " . $lesson_title)};
        			} else {
        			    $offGradeSequence ++;
        				push @off_grade_lessons_array, {('item_type' => 'lesson',
        											'item_id'=>$$row{'lesson_id'},
        											'sequence'=>$offGradeSequence,
        											'item_grade'=>$$row{'unit_grade'},
        											'unit_title'=>"(Gd $display_grade) " . $$row{'unit_title'},
        											'leaf'=>'true',
        											'item_description'=>"(Gd $display_grade) " . $$row{'lesson_description'},
        											'item_title'=>"(Gd $display_grade) " . $lesson_title)};
        			}
    			}
    			$current_standard = $$row{'standard_id'};
    		}
    		if ($in_standard) {
    			if (scalar(@linked_lessons_array) > 0) {
    			    push @linked_lessons_array, @off_grade_lessons_array;
    				$standard{'children'} = [@linked_lessons_array];
    			}
    			push @standards_array,{%standard};
    		}
    		if (! scalar(@standards_array) && $no_children) {
    			%standard = ();
    			$standard{'item_type'} = "standard";
    			$standard{'item_title'} = 'Text covers all selected grade-level standards.';
    			$standard{'item_id'} = '99';
    			$standard{'leaf'} = 'false';
    			my @dummyChildren;
    			my %dummyChild = ('item_description'=>'No additional materials',
    						'leaf'=>'true');
    			push @dummyChildren, {%dummyChild};
    			$standard{'children'} = [%dummyChild];
    			
    		}

    		$output{'children'} = [@standards_array];
	    	my $out_scalar = JSON::XS::->new->pretty(0)->encode( \%output);
    		print OUT $out_scalar;
	    	close OUT;
		    print $r->header(-type => 'application/json',
	                    -expires => 'now');
		    $r->print($out_scalar);			
	    }
	}
	sub get_lesson_detail {
		my ($r) = @_;
		my $lesson_id = $r->param('lessonid');
		my $qry = "SELECT cc_curricula.unit_name, cc_curricula.lesson_name, cc_units.id as unit_id, cc_units.title as unit_title, 
							cc_units.description as unit_description,
							cc_themes.id as lesson_id, cc_math_ideas.idea, 
							cc_themes.title as lesson_title, cc_themes.description as lesson_description,
							framework_items.id as standard_id, framework_items.title as standard_title, 
							cc_materials.id as material_id, cc_materials.title as material_title
							FROM cc_themes
							INNER JOIN cc_units ON cc_themes.unit_id = cc_units.id
							INNER JOIN cc_curricula ON cc_curricula.id = cc_units.curriculum_id
							LEFT JOIN (cc_math_ideas, cc_lesson_ideas) on cc_math_ideas.id = cc_lesson_ideas.idea_id AND cc_lesson_ideas.lesson_id = cc_themes.id
							LEFT JOIN (cc_pf_theme_tags, framework_items) on cc_pf_theme_tags.theme_id = cc_themes.id AND cc_pf_theme_tags.pf_end_id = framework_items.id
							LEFT JOIN (cc_materials, cc_material_chunks) ON cc_materials.id = cc_material_chunks.material_id AND cc_material_chunks.theme_id = cc_themes.id 
							WHERE cc_themes.id = ?";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute($lesson_id);
		my %lesson;
		my @linked_standards_array;
		my %linked_ideas;
		my @linked_ideas_array;
		my %linked_standards; #used to remember what's been linked to avoid duplicates
		my $first_row = 1;
		my %output;
		%linked_standards = ();
		while (my $row = $rst->fetchrow_hashref()) {
			if ($first_row) {
				$output{'unit_name'} = $$row{'unit_name'};
				$output{'lesson_name'} = $$row{'lesson_name'};
				$output{'unit_title'} = $$row{'unit_title'};
				$output{'unit_id'} = $$row{'unit_id'};
				$output{'lesson_id'} = $$row{'lesson_id'};
				$output{'lesson_title'} = $$row{'lesson_title'};
				$output{'unit_description'} = $$row{'unit_description'};
				$output{'lesson_description'} = $$row{'lesson_description'};
				$first_row = 0;
			}
			if ($$row{'standard_id'}) {
				if (! $linked_standards{$$row{'standard_id'}}) {
					push @linked_standards_array, {('id' => $$row{'standard_id'},
												'title'=>$$row{'standard_title'})};
					$linked_standards{$$row{'standard_id'}} = 1;
				}
			}
			if ($$row{'idea'}) {
				if (! $linked_ideas{$$row{'idea'}}) {
					push @linked_ideas_array, {('idea' => $$row{'idea'})};
					$linked_ideas{$$row{'idea'}} = 1;
				}
			}
			
		}
		if (scalar(@linked_standards_array)) {
			$output{'standards'} = [@linked_standards_array];
		}
		if (scalar(@linked_ideas_array)) {
			$output{'ideas'} = [@linked_ideas_array];
		}
		
		print $r->header(-type => 'application/json',
	                    -expires => 'now');
		$r->print(JSON::XS::->new->pretty(1)->encode( \%output));			
		
	}
	sub get_lesson_nav {
		my ($r) = @_;
		my $grade = $r->param('grade');
		my $curriculum_id = $r->param('curriculumid');
		# Routine returns four or five data objects
		# Note: 3/24/13 RB - Still figuring out best way to send data
		# Must provide ordered list of lessons with related standards as 
		# well as an ordered list of standards with related lessons
		# it would be best not to send redundant information
		# however, it looks like we'll need to until we can better 
		# understand how Sencha Touch works.
		my $qry = "SELECT framework_items.id as standard_id, framework_items.title as standard_code,
		 	framework_items.grade, framework_items.description, cc_themes.id as lesson_id, cc_themes.title as lesson_title
		FROM (framework_items, framework_strands)
		LEFT JOIN (cc_themes, cc_pf_theme_tags, cc_units) 
		ON cc_pf_theme_tags.pf_end_id = framework_items.id AND 
		cc_pf_theme_tags.theme_id = cc_themes.id AND 
		cc_units.id = cc_themes.unit_id AND
		cc_themes.eliminated IS NULL AND
		cc_units.curriculum_id = ?
		WHERE framework_items.framework_id = 1 AND
		framework_items.title > ' ' AND
		framework_strands.`code` = framework_items.`code` AND
		grade = ?
		ORDER BY framework_strands.sequence, framework_items.sequence
		";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute($curriculum_id, $grade);
		my %output;
		my @linked_lessons_array;
		my %standards_hash;
		my @standards_array;
		my %standard;
		my $current_standard = 0;
		my $in_standard = 0;
		while (my $row = $rst->fetchrow_hashref()) {
			if ($current_standard != $$row{'standard_id'}) {
				if ($in_standard) {
					if (scalar(@linked_lessons_array) == 0) {
						push @linked_lessons_array, {('id'=> 0),
													'leaf' => 'true'};
					}
					$standard{'children'} = [@linked_lessons_array];
					@linked_lessons_array = ();
					push @standards_array, {%standard};
				}
				$standards_hash{$current_standard} = {%standard};
				$in_standard = 1;
				%standard = ();
				$standard{'code'} = $$row{'standard_code'};
				$standard{'id'} = $$row{'standard_id'};
				$standard{'leaf'} = 'false';
				if ($$row{'lesson_id'} && ($$row{'lesson_id'} > 0)) {
					push @linked_lessons_array, {('id'=>$$row{'lesson_id'},
											'title'=>$$row{'lesson_title'},
											'leaf' => 'true')};
				}
			} else {
				push @linked_lessons_array, {('id'=>$$row{'lesson_id'}),
											'title'=>$$row{'lesson_title'},
											'leaf' => 'true'};
			}
			$current_standard = $$row{'standard_id'};
		}
		if ($in_standard) {
			if (scalar(@linked_lessons_array) > 0) {
				$standard{'lessons'} = [@linked_lessons_array];
			}
		}
		$qry = "SELECT cc_curricula.unit_name, cc_curricula.lesson_name, cc_units.id as unit_id, cc_units.title as unit_title, 
					cc_units.description as unit_description,
					cc_themes.id as lesson_id, cc_math_ideas.idea, 
					cc_themes.title as lesson_title, cc_themes.description as lesson_description,
					framework_items.id as standard_id, framework_items.title as standard_title, 
					cc_materials.id as material_id, cc_materials.title as material_title
					FROM cc_curricula, cc_units, cc_themes
					LEFT JOIN (cc_math_ideas, cc_lesson_ideas) on cc_math_ideas.id = cc_lesson_ideas.idea_id AND cc_lesson_ideas.lesson_id = cc_themes.id
					LEFT JOIN (cc_pf_theme_tags, framework_items) on cc_pf_theme_tags.theme_id = cc_themes.id AND cc_pf_theme_tags.pf_end_id = framework_items.id
					LEFT JOIN (cc_materials, cc_material_chunks) ON cc_materials.id = cc_material_chunks.material_id AND cc_material_chunks.theme_id = cc_themes.id 
					WHERE cc_units.curriculum_id = ? AND
						cc_curricula.id = cc_units.curriculum_id AND
						cc_units.grade_id = ? AND
						cc_units.id = cc_themes.unit_id AND
						cc_themes.eliminated IS NULL
						ORDER BY cc_units.sequence, cc_themes.sequence";
		$rst = $env{'dbh'}->prepare($qry);
		$rst->execute($curriculum_id, $grade);
		my %units_hash;
		my %unit;
		my %lessons_hash;
		my @lessons_array;
		my %lesson;
		my @linked_standards_array;
		my %linked_standards; #used to remember what's been linked to avoid duplicates
		my $current_lesson = 0;
		my $in_lesson = 0;
		my $first_row = 1;
		while (my $row = $rst->fetchrow_hashref()) {
			if ($first_row) {
				$output{'unit_name'} = $$row{'unit_name'};
				$output{'lesson_name'} = $$row{'lesson_name'};
				$first_row = 1;
			}
			if (! $units_hash{$$row{'unit_id'}}) {
				$unit{'title'} = $$row{'unit_title'};
				$unit{'description'} = $$row{'unit_description'};
				$units_hash{$$row{'unit_id'}} = {%unit};
			}
			if ($current_lesson != $$row{'lesson_id'}) {
				%linked_standards = ();
				if ($in_lesson) {
					if (scalar(@linked_standards_array) == 0) {
						push @linked_standards_array, {('id' => 0,
													'leaf' => 'true')};
					}
					$lesson{'children'} = [@linked_standards_array];
					@linked_standards_array = ();
					push @lessons_array, {%lesson};
				}
				$lessons_hash{$current_lesson} = {%lesson};
				%lesson = ();
				$lesson{'leaf'} = 'false';
				$lesson{'title'} = $$row{'lesson_title'};
				$lesson{'id'} = $$row{'lesson_id'};
				$current_lesson = $$row{'lesson_id'};
			} 
			if ($$row{'standard_id'}) {
				if (! $linked_standards{$$row{'standard_id'}}) {
					push @linked_standards_array, {('id' => $$row{'standard_id'},
												'title'=>$$row{'standard_title'},
												'leaf' => 'true')};
					$linked_standards{$$row{'standard_id'}} = 1;
				}
			}
			
			$in_lesson = 1;
		}
		print $r->header(-type => 'application/json',
	                    -expires => 'now');
		$output{'units_assoc'} = {%units_hash};
	    $output{'standards_assoc'} = {%standards_hash};
		$output{'standards_array'} = [@standards_array];
	    $output{'lessons_assoc'} = {%lessons_hash};
		$output{'lessons_array'} = [@lessons_array];
		$r->print(JSON::XS::->new->pretty(1)->encode( \%output));			
	}
	sub get_welcome_letter {
		my($r) = @_;
		my $qry = "select invoice_id, message, NOW() from tj_invoices WHERE NOW() > date_available AND NOW() < date_due";
		my $sth = $env{'dbh'}->prepare($qry);
		$sth->execute();
		my $row = $sth->fetchrow_hashref();
		my @letters;
		my %letter = ('message'=>$$row{'message'},
		        'messageid'=>$$row{'invoice_id'});
		push @letters,{%letter};
		my %output = ('letter'=>@letters);
		$r->print(JSON::XS::->new->pretty(1)->encode( \%output));					
	}
	sub register_user {
		my ($r) = @_;
		my %messages;
		my $firstname = $r->param('firstname');
		my $lastname = $r->param('lastname');
		my $password = $r->param('password');
		my $email = $r->param('email');
		my $welcome_letter_id = $r->param('welcomeletterid');
		my $initials = $r->param('initials');
		my $username = $email;
		my $district_id = $r->param('districtid');
		my $altemail = $r->param('altemail');
		my $school_id = $r->param('schoolid');
		my $period_duration = $r->param('periodduration')?$r->param('periodduration'):0;
		my $number_students = $r->param('studentcount')?$r->param('studentcount'):0;
		my $teacher_type_id = $r->param('teachertypeid')?$r->param('teachertypeid'):11;
		my $role_id = $r->param('roleid')?$r->param('roleid'):7;
		my %fields = ('firstname'=>&Apache::Promse::fix_quotes($firstname),
					'lastname'=>&Apache::Promse::fix_quotes($lastname),
					'password'=>' MD5(' . &Apache::Promse::fix_quotes($password) . ') ',
					'email'=>&Apache::Promse::fix_quotes($email),
					'emailwork'=>&Apache::Promse::fix_quotes($altemail),
					'username'=>&Apache::Promse::fix_quotes($username),
					'subject'=>"'Math'",
					'active'=>0);
		my $user_id = &Apache::Promse::save_record('users',\%fields,1);
		if ($user_id == 0) {
			$messages{'success'} = "false";
			$messages{'message'} = 'User Exists';
		} else {
		    my $qry = "SELECT count(*) exist FROM tj_user_info WHERE user_id = ?";
		    my $sth = $env{'dbh'}->prepare($qry);
		    $sth->execute($user_id);
		    my $row = $sth->fetchrow_hashref();
		    if ($$row{'exist'}) {
		        $qry = "UPDATE tj_user_info SET default_curriculum = ? WHERE user_id = ?";
		        $sth = $env{'dbh'}->prepare($qry);
		        $sth->execute($r->param('textbookx'),$user_id);
		    } else {
		        $qry = "INSERT INTO tj_user_info (user_id, default_curriculum) VALUES (?,?)";
		        $sth = $env{'dbh'}->prepare($qry);
		        $sth->execute($user_id, $r->param('textbookx'));
		    }
			%fields = ('user_id'=>$user_id,
					'role_id'=>$role_id);
			&Apache::Promse::save_record('userroles',\%fields,0);
			my @class_ids = split(/,/, $r->param('classid'));
			foreach my $class_id(@class_ids) {
				%fields = ('user_id'=>$user_id,
						'class_id'=>$class_id,
						'duration'=>$period_duration);
				&Apache::Promse::save_record('tj_user_classes',\%fields,0);
				%fields = ('user_id'=>$user_id,
						'type_id'=>$teacher_type_id,
						'class_id'=>$class_id);
				&Apache::Promse::save_record('tj_teacher_type',\%fields,0);
			}
			%fields = ('user_id'=>$user_id,
				'loc_id'=>$school_id);
			&Apache::Promse::save_record('user_locs',\%fields,0);
			%fields = ('user_id'=>$user_id,
					'invoice_id'=>$welcome_letter_id,
					'status'=>&Apache::Promse::fix_quotes('accepted'));
					&Apache::Promse::save_record('tj_user_invoice',\%fields,0);
			my %status = ('success'=>'true');
			my $email_response = &email_activation($r);
			$messages{'success'} = "true";
			$messages{'message'} = "user_id: $user_id";
		}
		print $r->header(-type => 'application/json',
	                    -expires => 'now');
	    
		$r->print(JSON::XS::->new->pretty(1)->encode( \%messages));			
		#			'district_id'=>'',
		#			'school_id'=>'',
		#			'periodduration'=>'',
		#			'numberstudents'=>'');
		
	}
	sub email_activation {
	    my ($r) = @_;
	    my %mail;
	    
	    
	    my %fields;
	    my $sth;
		my $server_string;
        my $qry = "select password, email, username from users where email = '".$r->param('email')."'";
		print STDERR "\n $qry \n";
        $sth = $env{'dbh'}->prepare($qry);
        $sth->execute();
        my $msg;
		my $done_one = 0;
        while (my $row = $sth->fetchrow_hashref()) {
			my $url = $r->self_url();
			if ($url=~/vpd\./) {
				$server_string = 'http://vpd.educ.msu.edu/';
			} else {
				$server_string = 'http://csc.educ.msu.edu/';
			}
			$done_one ++;
            $msg = "Your user name is ".$$row{'username'}."\n";
            $msg .= $server_string . 'promse/journal?pwd='.$$row{'password'}.';username='.$$row{'username'}.';action=activateaccount' . "\n \n 
            Click the link above to activate your account. \n\n
            After you have activated your account, you may use the following link to visit the Textbook Navigator/Journal. \n\n
            http://csc.educ.msu.edu/Nav";
            $mail{'message'} = $msg;
            $mail{'subject'} = "Activate your account";
            $mail{'from'} = 'donotreply@csc.educ.msu.edu';
            $mail{'to'} = $r->param('email');
            sendmail(%mail);
        }
        
        $msg = "A new user just registered on the Navigator/J. This is the message that user received: \n\n" . $msg;
        $mail{'message'} = $msg;
        $mail{'subject'} = "Activate your Teacher Journal account";
        $mail{'from'} = 'donotreply@vpd.educ.msu.edu';
        $mail{'to'} = 'journal@vpdsupport.org';
        sendmail(%mail);
        
	    return;
	}


	sub get_tj_summary {
		my ($r) = @_;
		my $user_id = $env{'user_id'};
		my %tj_summary;
		my @journal_entries;
		my %journal_entry;
		my @topic_entries;
		my @topic_activities;
		my %topic_entry;
		my $topic_activity;
		my $qry = "SELECT t2.framework_id, t2.duration, t3.activity_id,
			t1.date_taught, t1.class_id
		FROM (tj_journal as t1, tj_journal_topic as t2, tj_topic_activity as t3)
		WHERE t1.journal_id = t2.journal_id AND
			t3.journal_id = t1.journal_id AND
			t1.user_id = $user_id
		ORDER BY t1.date_taught";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my $current_date_taught = '';
		my $current_topic;
		my $done_one = 0;
		while (my $row = $rst->fetchrow_hashref()) {
			if ($current_date_taught ne $$row{'date_taught'}) {
				if ($done_one) {
					$topic_entry{'activities'} = $topic_activity;
					push(@topic_entries, {%topic_entry});
					$journal_entry{'topics'} = [@topic_entries];
					push (@journal_entries, {%journal_entry});
				} else {
					$done_one = 1;
				}
				$current_date_taught = $$row{'date_taught'};
				$current_topic = $$row{'framework_id'};
				@topic_entries = ();
				$topic_activity = '';
				%journal_entry = ('date_taught'=>$current_date_taught,
									'class_id'=>$$row{'class_id'});
				%topic_entry = ('topic'=>$current_topic,
									'duration'=>$$row{'duration'});
				$topic_activity = $$row{'activity_id'};
				# start new date record
			} else {
				# continuing a date record
				if ($current_topic ne $$row{'framework_id'}) {
					#finish topic in progress
					$topic_entry{'activities'} = $topic_activity;
					push(@topic_entries, {%topic_entry});
					$current_topic = $$row{'framework_id'};
					$topic_activity = '';
					%topic_entry = ('topic'=>$current_topic,
										'duration'=>$$row{'duration'});
					$topic_activity = $$row{'activity_id'};
				} else {
					$topic_activity .= ',' . $$row{'activity_id'};
					# must be another activity in the same framework topic
				}
			}
		}
		if ($done_one) {
			$topic_entry{'activities'} = $topic_activity;
			push(@topic_entries, {%topic_entry});
			$journal_entry{'topics'} = [@topic_entries];
			push (@journal_entries, {%journal_entry});
			
			$tj_summary{'summary'} = [@journal_entries];
			my $output = JSON::XS::->new->pretty(1)->encode( \%tj_summary);
			$r->print($output);
		} else {
			$r->print('no summary produced');
		}
	}
	sub email_journal {
		my ($r) = @_;
		my $class_id = $r->param('classid');
		my $qry;
		my $rst;
		my $user_id = $env{'user_id'};
		$qry = "SELECT email FROM users WHERE users.id = $user_id";
		$rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my $rst_row = $rst->fetchrow_hashref();
		my $email = $$rst_row{'email'};
		my $journal_log;
		$qry = "SELECT DISTINCT tj_journal.date_taught, tj_classes.class_name, framework_items.description, tj_journal_topic.duration,
											tj_journal_topic.background, tj_journal_topic.pages, tj_journal_topic.notes,tj_activities.activity_name,
											cc_materials.title as material_name, tj_user_materials.material_name as user_material_name
											FROM (tj_journal, tj_journal_topic, tj_classes, framework_items)
											LEFT JOIN (tj_topic_materials, cc_materials) 
												ON (tj_topic_materials.journal_id = tj_journal.journal_id	
													AND tj_topic_materials.topic_id = tj_journal_topic.framework_id
													AND cc_materials.id = tj_topic_materials.material_id)
											LEFT JOIN tj_user_materials ON (tj_user_materials.journal_id = tj_journal.journal_id AND tj_user_materials.topic_id = tj_journal_topic.framework_id)
											LEFT JOIN (tj_topic_activity, tj_activities) ON (tj_topic_activity.journal_id = tj_journal.journal_id AND 
													tj_topic_activity.topic_id = tj_journal_topic.framework_id AND
													tj_activities.activity_id = tj_topic_activity.activity_id)
						WHERE tj_journal.user_id = $user_id AND tj_journal_topic.journal_id AND tj_journal.journal_id = tj_journal_topic.journal_id AND
									tj_journal_topic.framework_id = framework_items.id AND
									tj_classes.class_id = tj_journal.class_id AND
									tj_classes.class_id = $class_id AND
									tj_journal.deleted = 0 AND tj_journal_topic.deleted = 0
						ORDER BY tj_journal.date_taught DESC,tj_journal.class_id, tj_journal.time_stamp, tj_journal_topic.framework_id";
		$rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my $file_name = " /var/www/html/logs/emailjournal". $user_id . ".csv";
		my $first_row = 1;
		while (my $row = $rst->fetchrow_hashref()) {
			if ($first_row) {
				$first_row = 0;
				$journal_log .= 'Date,Class,Topic,Duration,"Background(0-weak, 3-strong)",Pages,Notes,Activity,Material,User Material' . "\n";
			}
			$journal_log .= $$row{'date_taught'} . ",";
			$journal_log .= $$row{'class_name'} . ",";
			my $edited_description = $$row{'description'};
			$edited_description =~ s/"/''/g;
			$edited_description = '"' . $edited_description . '"';
			$journal_log .= $edited_description . ",";
			$journal_log .= $$row{'duration'} . ",";
			$journal_log .= $$row{'background'} . ",";
			my $edited_pages = $$row{'pages'};
			$edited_pages =~ s/"/''/g;
			$edited_pages = '"' . $edited_pages . '"';
			$journal_log .= $edited_pages .  ",";
			my $edited_notes = $$row{'notes'};
			$edited_notes =~ s/"/''/g;
			$edited_notes = '"' . $edited_notes . '"';
			$journal_log .= $edited_notes . ",";
			$journal_log .= $$row{'activity_name'} . ",";
			$journal_log .= $$row{'material_name'} . ",";
			$journal_log .= $$row{'user_material_name'} . ",";
			$journal_log .= "\n";
		}
#		my $msg = MIME::Lite->new(
#		    From    => 'no_reply@vpd.msu.edu',
#		    To      => $email,
#		    Cc      => '',
#		    Subject => 'Your teacher journal',
#		    Type    => 'multipart/mixed',
#		);

#		$msg->attach(
#		    Type     => 'TEXT',
#		    Data     => "Attached is your teacher journal as a .CSV file (sent to $email). This can be viewed in Excel and other spreadsheet programs.\n",
#		);

#		$msg->attach(
#		    Type     => 'application/octet-stream',
#		    Data     => $journal_log,
#		    Filename => 'your_journal_log.csv',
#		);
#		$msg->send;
		my $output;
		my %status = ('status'=>'ok');
		$output = JSON::XS::->new->pretty(1)->encode( \%status);
		return($output);
	}
	sub get_user_log {
		my ($r,$passed_user_id,$get_all) = @_;
		my $start_record = $r->param('start')?$r->param('start'):0;
		my $limit_records = $r->param('limit')?$r->param('limit'):40;
		my $limit_string = "LIMIT $start_record, $limit_records";
		if ($get_all) {
			$limit_string = "";
		}
		my $course = $r->param('courseid');
		my $date_taught = $r->param('datetaught');
		my $user_id;
		if (! $passed_user_id) {
			$user_id = $env{'user_id'};
		} else {
			$user_id = $passed_user_id;
		}
		my $output;
		my $qry = "SELECT DISTINCT tj_journal.journal_id, tj_journal.date_taught, tj_journal.class_id,tj_journal.lnotes,
		                            tj_journal_topic.framework_id, tj_journal_topic.duration,
									tj_journal_topic.background,tj_journal_topic.priority, tj_journal_topic.pages, tj_journal_topic.notes,tj_activities.activity_name,
									tj_topic_materials.material_id, cc_materials.title as material_name, tj_user_materials.material_name as user_material_name,
									tj_topic_activity.activity_id, framework_items.description, tj_classes.class_name
									FROM (tj_journal, tj_journal_topic, tj_classes, framework_items)
									LEFT JOIN (tj_topic_materials, cc_materials) 
										ON (tj_topic_materials.journal_id = tj_journal.journal_id	
											AND tj_topic_materials.topic_id = tj_journal_topic.framework_id
											AND cc_materials.id = tj_topic_materials.material_id)
									LEFT JOIN tj_user_materials ON (tj_user_materials.journal_id = tj_journal.journal_id AND tj_user_materials.topic_id = tj_journal_topic.framework_id)
									LEFT JOIN (tj_topic_activity, tj_activities) ON (tj_topic_activity.journal_id = tj_journal.journal_id AND 
											tj_topic_activity.topic_id = tj_journal_topic.framework_id AND
											tj_activities.activity_id = tj_topic_activity.activity_id)
				WHERE tj_journal.user_id = $user_id AND tj_journal_topic.journal_id AND tj_journal.journal_id = tj_journal_topic.journal_id AND
							tj_journal_topic.framework_id = framework_items.id AND
							tj_classes.class_id = tj_journal.class_id AND
							tj_journal.deleted = 0 AND tj_journal_topic.deleted = 0
				ORDER BY tj_journal.date_taught DESC,tj_journal.class_id, tj_journal.time_stamp, tj_journal_topic.framework_id
				$limit_string";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my %retro_report;
		my $current_journal_id = 0;
		my $current_topic_id = 0;
		my @journal_entries;
		my %journal_entry;
		my @topics;
		my $topic;
		my @activities;
		my %activity;
		my @materials;
		my %material;
		my @user_materials;
		my %user_material;
		my $first_row = 1;
		my $row_counter = 0;
		my $has_activity = 0;
		my $has_material = 0;
		my $has_user_materials = 0;
		my $did_one = 0;
		while (my $row = $rst->fetchrow_hashref()) {
			$did_one = 1;
			$row_counter ++;
			if ($current_journal_id ne $$row{'journal_id'}) {
				if (! $first_row) {
					if ($has_activity) {
						$journal_entry{'activity'} = [@activities];
					}
					@activities = ();
					$has_activity = 0;
					push (@journal_entries, {%journal_entry});
				}
				$current_journal_id = $$row{'journal_id'};
				$current_topic_id = $$row{'framework_id'};
				# here begin the journal entry
				%journal_entry=('journalid'=>$$row{'journal_id'},
								'datetaught'=>$$row{'date_taught'},
								'classid'=>$$row{'class_id'},
								'classname'=>$$row{'class_name'},
								'lnotes'=>$$row{'lnotes'},
								'framework_id'=>$current_topic_id,
								'priority'=>$$row{'priority'},
								'frameworktitle'=>$$row{'description'},
								'duration'=>$$row{'duration'},
								'background' => $$row{'background'},
								'pages' => $$row{'pages'},
								'notes' => $$row{'notes'});
								
				# every journal entry must have at least one topic
				# now need to check for activity and materials
				if ($$row{'activity_id'}) {
					%activity = ('activity_id'=>$$row{'activity_id'},
								'activity_name' => $$row{'activity_name'});
					push(@activities, {%activity});	
					$has_activity = 1;
				}
				if ($$row{'user_material_name'}) {
					$journal_entry{'usermaterials'} = $$row{'user_material_name'};
				}
				if ($$row{'material_id'}) {
					$journal_entry{'materialid'} = $$row{'material_id'};
					$journal_entry{'materialname'} = $$row{'material_name'};
				}
			} elsif ($current_topic_id ne $$row{'framework_id'})  {
				# new topic in existing journal - so store previous
				$current_topic_id = $$row{'framework_id'};
				if ($has_activity) {
					$journal_entry{'activity'} = [@activities];
				}
				push (@journal_entries, {%journal_entry});
				@activities = ();
				$has_activity = 0;
				%journal_entry=('journalid'=>$$row{'journal_id'},
								'datetaught'=>$$row{'date_taught'},
								'classid'=>$$row{'class_id'},
								'classname'=>$$row{'class_name'},
								'framework_id'=>$current_topic_id,
								'frameworktitle'=>$$row{'description'},
								'duration'=>$$row{'duration'},
								'background' => $$row{'background'},
								'pages' => $$row{'pages'},
								'notes' => $$row{'notes'});
				if ($$row{'activity_id'}) {
					%activity = ('activity_id'=>$$row{'activity_id'},
								'activity_name' => $$row{'activity_name'});
					push(@activities, {%activity});	
					$has_activity = 1;
				}
				if ($$row{'user_material_name'}) {
					$journal_entry{'usermaterials'} = $$row{'user_material_name'};
				}
				if ($$row{'material_id'}) {
					$journal_entry{'materialid'} = $$row{'material_id'};
					$journal_entry{'materialname'} = $$row{'material_name'};
				}
			} else {
				if ($$row{'activity_id'}) {
					%activity = ('activity_id'=>$$row{'activity_id'},
								'activity_name' => $$row{'activity_name'});
					push(@activities, {%activity});	
					$has_activity = 1;				
				}
			}
			$first_row = 0;
		}
		if ($did_one) {
			if ($has_activity) {
				$journal_entry{'activity'} = [@activities];
			}
			push(@journal_entries,{%journal_entry});
		}
		$retro_report{'userlog'} = [@journal_entries];
		if ($passed_user_id) {
			return(\%retro_report);
		} else {
			$output = JSON::XS::->new->pretty(1)->encode( \%retro_report);
			return($output);
		}
	}
	sub get_user_log14 {
		my ($r,$passed_user_id,$get_all) = @_;
		my $start_record = $r->param('start')?$r->param('start'):0;
		my $limit_records = $r->param('limit')?$r->param('limit'):40;
		my $limit_string = "LIMIT $start_record, $limit_records";
		$get_all = 1;
		if ($get_all) {
			$limit_string = "";
		}
		my $course = $r->param('courseid');
		my $date_taught = $r->param('datetaught');
		my $user_id;
		if (! $passed_user_id) {
			$user_id = $env{'user_id'};
		} else {
			$user_id = $passed_user_id;
		}
		my $output;
		my $qry = "SELECT DISTINCT tj_journal.journal_id, tj_journal.date_taught, tj_journal.class_id, tj_journal.lnotes,
									tj_journal.duration as lesson_duration, tj_journal_topic.framework_id, tj_journal_topic.duration,
									tj_journal_topic.duration_mask,tj_journal_topic.priority,
									tj_journal_topic.background, tj_journal_topic.pages, tj_journal_topic.notes,tj_activities.activity_name,
									tj_topic_materials.material_id, cc_materials.title as material_name, tj_user_materials.material_name as user_material_name,
									tj_topic_activity.activity_id, framework_items.description, framework_items.title as fullcode, tj_classes.class_name,
									math_practices.practice_name, math_practices.practice_id, tj_journal_results.results,
									tj_journal_studresults.studresults
									FROM (tj_journal, tj_journal_topic, tj_classes, framework_items)
									LEFT JOIN (tj_topic_materials, cc_materials) 
										ON (tj_topic_materials.journal_id = tj_journal.journal_id	
											AND tj_topic_materials.topic_id = tj_journal_topic.framework_id
											AND cc_materials.id = tj_topic_materials.material_id
											AND tj_topic_materials.deleted = 0)
									LEFT JOIN tj_user_materials ON (tj_user_materials.journal_id = tj_journal.journal_id AND tj_user_materials.topic_id = tj_journal_topic.framework_id)
									LEFT JOIN (tj_topic_activity, tj_activities) ON (tj_topic_activity.journal_id = tj_journal.journal_id AND 
											tj_topic_activity.topic_id = tj_journal_topic.framework_id AND
											tj_activities.activity_id = tj_topic_activity.activity_id
											AND tj_topic_activity.deleted = 0)
									LEFT JOIN (tj_journal_math_practices, math_practices) ON 
												tj_journal_math_practices.journal_id = tj_journal.journal_id AND
												tj_journal_math_practices.math_practice_id = math_practices.practice_id AND
												tj_journal_math_practices.deleted = 0
								    LEFT JOIN tj_journal_results ON tj_journal_results.journal_id = tj_journal.journal_id
								    LEFT JOIN tj_journal_studresults ON tj_journal_studresults.journal_id = tj_journal.journal_id
				WHERE tj_journal.user_id = $user_id AND tj_journal_topic.journal_id AND tj_journal.journal_id = tj_journal_topic.journal_id AND
							tj_journal_topic.framework_id = framework_items.id AND
							
							tj_classes.class_id = tj_journal.class_id AND
							tj_journal.deleted = 0 AND tj_journal_topic.deleted = 0
				ORDER BY tj_journal.date_taught DESC,tj_journal.class_id, tj_journal.time_stamp, tj_journal_topic.framework_id
				$limit_string";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my %retro_report;
		my $current_journal_id = 0;
		my $current_topic_id = 0;
		my @journal_entries;
		my %journal_entry;
		my @topics;
		my $topic;
		my @standards;
		my %standards;
		my %standard;
		my $current_standard;
		my @activities;
		my %activities;
		my $activities_csv;
		my $practices_csv;
		my $results_csv;
		my $studresults_csv;
		my %activity;
		my @practices;
		my %practice;
		my %practices;
		my @results;
		my %results;
		my @studresults;
		my %studresults;
		my @materials;
		my %material;
		my @user_materials;
		my %user_material;
		my $first_row = 1;
		my $row_counter = 0;
		my $has_activity = 0;
		my $has_practice = 0;
		my $has_material = 0;
		my $has_results = 0;
		my $has_studresults = 0;
		my $has_user_materials = 0;
		my $did_one = 0;
		while (my $row = $rst->fetchrow_hashref()) {
			$did_one = 1;
			$row_counter ++;
			if ($current_journal_id ne $$row{'journal_id'}) {
				if (! $first_row) {
					$journal_entry{'standards'} = [@standards];
					if ($has_activity == 1) {
						$activities_csv =~ /(.*)(,$)/;
						$activities_csv = $1;
						$journal_entry{'activity'} = [@activities];
						$journal_entry{'activitycsv'} = $activities_csv;
					}
					if ($has_practice == 1) {
						$practices_csv =~ /(.*)(,$)/;
						$practices_csv = $1;
						$journal_entry{'math_practices'} = [@practices];
						$journal_entry{'practicescsv'} = $practices_csv
					}
					if ($has_results == 1) {
						$results_csv =~ /(.*)(,$)/;
						$results_csv = $1;
						#$journal_entry{'math_practices'} = [@practices];
						$journal_entry{'resultscsv'} = $results_csv
					}
					if ($has_studresults == 1) {
						$studresults_csv =~ /(.*)(,$)/;
						$studresults_csv = $1;
						#$journal_entry{'math_practices'} = [@practices];
						$journal_entry{'studresultscsv'} = $studresults_csv;
						$studresults_csv = '';
						
					}
					
					@standards = ();
					%standard = ();
					%standards = ();
					@activities = ();
					@practices = ();
					%activities = ();
					%practices = ();
            		@results = ();
		            %results = ();
		            @studresults = ();
		            %studresults = ();
					$results_csv = '';
					$studresults_csv = '';
					$activities_csv = '';
					$practices_csv = '';
					$has_activity = 0;
					$has_practice = 0;
					$has_results = 0;
					$has_studresults = 0;
					push (@journal_entries, {%journal_entry});
				}
				$studresults_csv = '';
				$activities_csv = '';
				$current_journal_id = $$row{'journal_id'};
				$current_topic_id = $$row{'framework_id'};
				# here begin the journal entry
				%journal_entry=('journalid'=>$$row{'journal_id'},
								'datetaught'=>$$row{'date_taught'},
								'start'=>$$row{'date_taught'},
								'end'=>$$row{'date_taught'},
								'classid'=>$$row{'class_id'},
								'classname'=>$$row{'class_name'},
								'duration'=>$$row{'lesson_duration'},
								'lnotes'=>$$row{'lnotes'},
								'background' => $$row{'background'},
								'pages' => $$row{'pages'}								
								);
								
				# every journal entry must have at least one topic
				# now need to check for activity and materials and results and studresults
				%standard = ('standard_id'=>$current_topic_id,
						'percent'=>$$row{'duration'},
						'priority'=> $$row{'priority'},
						'duration_mask'=>$$row{'duration_mask'},
						'notes' => $$row{'notes'},
						'code'=>$$row{'fullcode'},
						'description'=>$$row{'description'});
				push(@standards,{%standard});
				if ($$row{'activity_id'} && (! $activities{$$row{'activity_id'}})) {
					$activities{$$row{'activity_id'}} = 1;
					$activities_csv .= $$row{'activity_id'} . ',';
					%activity = ('activity_id'=>$$row{'activity_id'},
								'activity_name' => $$row{'activity_name'});
					push(@activities, {%activity});	
					$has_activity = 1;
				}
				if ($$row{'practice_id'} && (! $practices{$$row{'practice_id'}})) {
					$practices{$$row{'practice_id'}} = 1;
					$practices_csv .= $$row{'practice_id'} . ',';
					%practice = ('math_practice_id'=>$$row{'practice_id'},
								'math_practice_name' => $$row{'practice_name'});
					push(@practices, {%practice});	
					$has_practice = 1;
				}
				if ($$row{'user_material_name'}) {
					$journal_entry{'usermaterials'} = $$row{'user_material_name'};
				}
				if ($$row{'material_id'}) {
					$journal_entry{'materialid'} = $$row{'material_id'};
					$journal_entry{'materialname'} = $$row{'material_name'};
				}
				if (($$row{'results'} || ($$row{'results'} == 0)) && (! $results{$$row{'results'}})) {
					$results{$$row{'results'}} = 1;
					$results_csv .= $$row{'results'} . ',';
					push(@results, {%results});	
					$has_results = 1;				
				}
				if ($$row{'studresults'} && (! $studresults{$$row{'studresults'}})) {
					$studresults{$$row{'studresults'}} = 1;
					
					$studresults_csv .= $$row{'studresults'} . ',';
					push(@studresults, {%studresults});	
					$has_studresults = 1;				
				}
			} elsif ($current_topic_id ne $$row{'framework_id'})  {
				# new topic in existing journal - so store previous
				$current_topic_id = $$row{'framework_id'};
				%standard=('standard_id'=>$current_topic_id,
								'percent'=>$$row{'duration'},
								'priority'=> $$row{'priority'},
								'duration_mask'=>$$row{'duration_mask'},
								'notes' => $$row{'notes'},
								'code'=>$$row{'fullcode'},
								'description'=>$$row{'description'});
				push(@standards,{%standard});
				if ($$row{'pages'}) {
					$journal_entry{'pages'} .= $$row{'pages'};
				}
				if ($$row{'background'}) {
					$journal_entry{'background'} .= $$row{'background'};
				}
				if ($$row{'activity_id'} && (! $activities{$$row{'activity_id'}})) {
					$activities{$$row{'activity_id'}} = 1;
					$activities_csv .= $$row{'activity_id'} . ',';
					%activity = ('activity_id'=>$$row{'activity_id'},
								'activity_name' => $$row{'activity_name'});
					push(@activities, {%activity});	
					$has_activity = 1;
				}
				if ($$row{'practice_id'} && (! $practices{$$row{'practice_id'}})) {
					$practices{$$row{'practice_id'}} = 1;
					$practices_csv .= $$row{'practice_id'} . ',';
					%practice = ('math_practice_id'=>$$row{'practice_id'},
								'math_practice_name' => $$row{'practice_name'});
					push(@practices, {%practice});	
					$has_practice = 1;
				}
				if ($$row{'user_material_name'}) {
					$journal_entry{'usermaterials'} = $$row{'user_material_name'};
				}
				if ($$row{'material_id'}) {
					$journal_entry{'materialid'} = $$row{'material_id'};
					$journal_entry{'materialname'} = $$row{'material_name'};
				}
				if ($$row{'results'} && (! $results{$$row{'results'}})) {
					$results{$$row{'results'}} = 1;
					$results_csv .= $$row{'results'} . ',';
					push(@results, {%results});	
					$has_results = 1;				
				}
				if ($$row{'studresults'} && (! $studresults{$$row{'studresults'}})) {
					$studresults{$$row{'studresults'}} = 1;
					$studresults_csv .= $$row{'studresults'} . ',';
					push(@studresults, {%studresults});	
					$has_studresults = 1;				
				}
			} else {
				if ($$row{'activity_id'} && (! $activities{$$row{'activity_id'}})) {
					$activities{$$row{'activity_id'}} = 1;
					$activities_csv .= $$row{'activity_id'} . ',';
					%activity = ('activity_id'=>$$row{'activity_id'},
								'activity_name' => $$row{'activity_name'});
					push(@activities, {%activity});	
					$has_activity = 1;				
				}
				if ($$row{'practice_id'} && (! $practices{$$row{'practice_id'}})) {
					$practices{$$row{'practice_id'}} = 1;
					$practices_csv .= $$row{'practice_id'} . ',';
					%practice = ('math_practice_id'=>$$row{'practice_id'},
								'math_practice_name' => $$row{'practice_name'});
					push(@practices, {%practice});	
					$has_practice = 1;
				}
				if ($$row{'results'} && (! $results{$$row{'results'}})) {
					$results{$$row{'results'}} = 1;
					$results_csv .= $$row{'results'} . ',';
					push(@results, {%results});	
					$has_results = 1;				
				}
				if ($$row{'studresults'} && (! $studresults{$$row{'studresults'}})) {
					$studresults{$$row{'studresults'}} = 1;
					$studresults_csv .= $$row{'studresults'} . ',';
					push(@studresults, {%studresults});	
					$has_studresults = 1;				
				}
			}
			$first_row = 0;
		}
		if ($did_one) {
			$journal_entry{'standards'} = [@standards];
			if ($has_activity == 1) {
				$activities_csv =~ /(.*)(,$)/;
				$activities_csv = $1;
				$journal_entry{'activitycsv'} = $activities_csv;
				$journal_entry{'activity'} = [@activities];
			}
			if ($has_practice == 1) {
				$practices_csv =~ /(.*)(,$)/;
				$practices_csv = $1;
				$journal_entry{'practicescsv'} = $practices_csv;
				$journal_entry{'math_practices'} = [@practices];
			}
			if ($has_results == 1) {
				$results_csv =~ /(.*)(,$)/;
				$results_csv = $1;
				$journal_entry{'resultscsv'} = $results_csv;
				$journal_entry{'results'} = [@results];
			}
			if ($has_studresults == 1) {
				$studresults_csv =~ /(.*)(,$)/;
				$studresults_csv = $1;
				$journal_entry{'studresultscsv'} = $studresults_csv;
				#$journal_entry{'studresults'} = [@studresults];
				$studresults_csv = '';
			}
			
			push(@journal_entries,{%journal_entry});
		}
		$retro_report{'userlog'} = [@journal_entries];
		if ($passed_user_id) {
			return(\%retro_report);
		} else {
			$output = JSON::XS::->new->pretty(1)->encode( \%retro_report);
			return($output);
		}
	}
	
	sub update_journal_topic {
		# update must include existing journal_entry_id and 
		# existing journal_topic 
		# update does not change anything in tj_journal, and
		# does not change the classID, datetaught, or framework_id
		# ************ updates following fields *************
		# tj_journal_topics.duration
		# tj_journal_topics.background
		# tj_journal_topics.pages
		# tj_journal_topics.notes
		# tj_topic_activity.activity_id
		# tj_topic_materials.material_id **  possibly delete existing records in tj_topic_materials
		# tj_user_materials.material_name
		my ($r) = @_;
		my $response;
		my $qry;
		my $rst;
		my %fields;
		my %ids;
		my @activities = [];
		my $journal_id = $r->param('journalid');
		my $duration = $r->param('duration');
		my $background = $r->param('background') gt 0?$r->param('background'):0;
		if ($r->param('activity')) {
			@activities = split(/,/,$r->param('activity'));
		}
		my $framework_id = $r->param('framework_id');
		my $pages = &Apache::Promse::fix_quotes($r->param('pages'));
		my $material_id = $r->param('materialid');
		my $material_name = &Apache::Promse::fix_quotes($r->param('usermaterials'));
		my $notes = &Apache::Promse::fix_quotes($r->param('notes'));
		%fields = ('duration'=>$duration,
				'background'=>$background,
				'pages'=>$pages,
				'notes'=>$notes);
		%ids = ('journal_id'=>$journal_id,
				'framework_id'=>$framework_id);
		&Apache::Promse::update_record('tj_journal_topic', \%ids, \%fields );
		$qry = "DELETE FROM tj_topic_activity WHERE journal_id = $journal_id AND topic_id = $framework_id";
		$rst = $env{'dbh'}->do($qry);
		%fields = ('journal_id'=>$journal_id,
				'topic_id'=>$framework_id);
		foreach my $activity (@activities) {
			$fields{'activity_id'} = $activity;
			&Apache::Promse::save_record('tj_topic_activity',\%fields);
		}
		$qry = "DELETE FROM tj_topic_materials WHERE journal_id = $journal_id AND topic_id = $framework_id";
		$env{'dbh'}->do($qry);
		%fields = ('journal_id'=>$journal_id,
				'topic_id'=>$framework_id,
				'material_id'=>$material_id);
		&Apache::Promse::save_record('tj_topic_materials',\%fields);
		$qry = "SELECT journal_id, topic_id FROM tj_user_materials WHERE journal_id = $journal_id AND topic_id = $framework_id";
		$rst=$env{'dbh'}->prepare($qry);
		$rst->execute();
		if (my $row = $rst->fetchrow_hashref()) {
			$qry = "UPDATE tj_user_materials SET material_name = $material_name WHERE journal_id = $journal_id AND topic_id = $framework_id";
			$env{'dbh'}->do($qry);
		} else {
			%fields = ('journal_id'=>$journal_id,
						'topic_id'=>$framework_id,
						'material_name'=>$material_name);
			&Apache::Promse::save_record('tj_user_materials',\%fields);
		}
		$r->print('{"success": "updated"}');
	}
	sub update_user_info {
	    my ($r) = @_;
	    # authagree, authinitial, messageid
	    my $user_id = $env{'user_id'};
	    my $invoice_id = $r->param('invoice_id');
	    my $initials = $r->param('authinitial');
	    my $status = $r->param('authagree');
	    $status = $status eq 'true'?'agree':'false';
	    my %fields = ('user_id' => $user_id,
	                'invoice_id' => $invoice_id,
	                'status' => &Apache::Promse::fix_quotes($status),
	                'initials' => &Apache::Promse::fix_quotes($initials));
	    my $result = &Apache::Promse::save_record('tj_user_invoice',\%fields);
	    my %output;
	    if ($result) {
	        %output = ('success' =>'false ' . $result);
	    } else {
	        %output = ('success'=>'true');
	    }
	    $r->print(JSON::XS::encode_json \%output); 
	}
	sub get_materials {
		my ($r) = @_;
		my $district_id = $r->param('district_id');
		my $profile = &Apache::Promse::get_user_profile($env{'user_id'});
		$district_id = $$profile{'district_id'};
		print STDERR "\n the user id is: $env{'user_id'} and district id is $district_id \n";
		my $qry = "SELECT cc_materials.id as materialid, cc_materials.title as materialname
				FROM cc_materials WHERE id IN (
					SELECT cc_district_materials.material_id
						FROM cc_district_materials
						WHERE cc_district_materials.district_id = $district_id)
							AND cc_materials.`subject` = 'Math'
							AND cc_materials.material_type = 1
		 			ORDER BY title";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my @materials;
		my %make_selection = ('materialid'=>'na',
							'materialname'=>'- Select Textbook -');
		push (@materials,{%make_selection});
		my %no_book = ('materialid'=>'0',
					'materialname'=>'No Book');
		push (@materials,{%no_book});
		while (my $row = $rst->fetchrow_hashref) {
			push (@materials, {%$row});
		}
		my %materials = ('materials' => \@materials);
		my $coder = JSON::XS->new->ascii->pretty->allow_nonref;
		my $output = JSON::XS::encode_json \%materials;
		$r->print($output);
	}
	sub insert_journal_topic {
		my($r) = @_;
		my $response;
		my %fields;
		my $class_id = $r->param('classid');
		my $date_taught = $r->param('datetaught');
		my $background = $r->param('background');
		my $duration_mask = $r->param('duration_mask');
		$background =~ s/\s//g;
		$background = $background?$background:0;
		my @activities;
		
		if ($r->param('activity')) {
			@activities = split(/,/,$r->param('activity'));
		}
		$date_taught =~ /(.*)T.*/;
		$date_taught = $1;
		my $framework_id = $r->param('frameworkitemid');
		my $journal_entry_id;
		my $material_id = $r->param('materialid');
		my $material_name = $r->param('materialname');
		my $qry = "SELECT journal_id FROM tj_journal
				WHERE class_id = $class_id AND date_taught = '$date_taught' AND user_id = $env{'user_id'}";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my @responses;
		if (my $row = $rst->fetchrow_hashref()) {
			$journal_entry_id = $$row{'journal_id'};
		} else {
			%fields = ('user_id'=>$env{'user_id'},
					'date_taught'=> &Apache::Promse::fix_quotes($date_taught),
					'class_id'=>$r->param('classid')
					);
			$journal_entry_id = &Apache::Promse::save_record('tj_journal', \%fields,1);
		}
		$qry = "SELECT journal_id, deleted FROM tj_journal_topic
				WHERE journal_id = $journal_entry_id AND
				 	framework_id = $framework_id";
		$rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		if (my $row = $rst->fetchrow_hashref()) {
#			if ($$row{'deleted'}) {
#				print STDERR "\n undeleting here \n";
#				$qry = 'update tj_journal_topic set deleted = 0, duration = ' . $r->param('duration') .
#				 ", background = $background, pages = " . &Apache::Promse::fix_quotes($r->param('pages')) .
#				', notes = ' . &Apache::Promse::fix_quotes($r->param('notes')) .
#				"WHERE journal_id = $journal_entry_id AND framework_id = " . $r->param('frameworkitemid');
#				$env{'dbh'}->do($qry);
#				push @responses, {'journal_topic'=>'undeleted'};
#			} else {
			push @responses, {'journal_entry'=>'duplicate key'};
			push @responses, {'journal_topic'=>'duplicate key'};
#			}
			#duplicate key
		} else {
			%fields = ('journal_id' => $journal_entry_id,
					'framework_id' => $r->param('frameworkitemid'),
					'duration' => $r->param('duration'),
					'duration_mask' => &Apache::Promse::fix_quotes($duration_mask),
					'background' => $background,
					'pages'=> &Apache::Promse::fix_quotes($r->param('pages')),
					'notes' => &Apache::Promse::fix_quotes($r->param('notes'))
					);
			&Apache::Promse::save_record('tj_journal_topic',\%fields,1);
			push @responses, {'journal_entry'=>'inserted'};
			if (scalar(@activities) > 0) {
				foreach my $activity(@activities) {
			
					%fields = ('journal_id'=>$journal_entry_id,
					'topic_id'=>$framework_id,
					'activity_id'=>$activity);
					&Apache::Promse::save_record('tj_topic_activity', \%fields);
				}
			}
			if ($material_id)  {
				# A material has been selected from the list
				%fields = ('journal_id'=>$journal_entry_id,
					'topic_id'=>$framework_id,
					'material_id'=>$material_id);
				if (&Apache::Promse::save_record('tj_topic_materials',\%fields,1)) {
					push @responses, {'topic material'=>'inserted'};
				} else {
					push @responses, {'topic material'=>'error'};
				}
			
			}
			if ($material_name ne 'none') {
				# A material name has by typed in by the user
				%fields=('material_name'=>&Apache::Promse::fix_quotes($material_name),
						'journal_id'=>$journal_entry_id,
						'topic_id'=>$framework_id);
				if (&Apache::Promse::save_record('tj_user_materials',\%fields,1)) {
					push @responses, {'user material'=>'inserted'};
				} else {
					push @responses, {'user material'=>'error'};
				}
			}
		}
		my %responses_hash = ('success'=>\@responses);
		my $output = JSON::XS::encode_json \%responses_hash;
		$r->print($output);
	}
	sub insert_lesson {
		my($r) = @_;
		my $response;
		my %fields;
		my $class_id = $r->param('classid');
		my $date_taught = $r->param('datetaught');
		my $background = $r->param('background');
		my $duration = $r->param('duration')?$r->param('duration'):0;
		my $pages = $r->param('pages1')?$r->param('pages1'):$r->param('pages2');
		$background =~ s/\s//g;
		$background = $background?$background:0;
		my @activities;
		if ($r->param('activity')) {
			@activities = split(/,/,$r->param('activity'));
		}
		if ($date_taught =~ /T/ ) {
			$date_taught =~ /(.*)T.*/;
			$date_taught = $1;
		}
		my @standards = split(/,/, $r->param('standardids'));
		my @times = split(/,/, $r->param('times'));
		my @notes = split(/\|/, $r->param('notes'));
		print STDERR "\n Notes has " . scalar(@notes) . " elements \n";
		my @priorities = split(/,/, $r->param('priority'));
		my @duration_masks = split(/,/, $r->param('duration_mask'));
		my @math_practices = split(/,/, $r->param('math'));
		my @results = split(/,/, $r->param('results'));
		my @studresults = split(/,/, $r->param('studresults'));
		my $journal_entry_id;
		my $material_id = $r->param('materialid');
		my $material_name = $r->param('materialname')?$r->param('materialname'):'';
		# first check if there is a journal entry for this user with this class and date
		my $qry = "SELECT journal_id FROM tj_journal
				WHERE class_id = $class_id AND date_taught = '$date_taught' AND user_id = $env{'user_id'}";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my @responses;
		if (my $row = $rst->fetchrow_hashref()) {
			$journal_entry_id = $$row{'journal_id'};
			$qry = "UPDATE tj_journal SET duration = ?, deleted = 0, lnotes = ? WHERE journal_id  = ?";
			my $rst2 = $env{'dbh'}->prepare($qry);
			$rst2->execute($duration,$r->param('lnotes'),$journal_entry_id);
			# found existing entry, so need to blow away all related records
			$qry = "DELETE FROM tj_journal_topic WHERE journal_id = $journal_entry_id";
			$env{'dbh'}->do($qry);
			$qry = "DELETE FROM tj_topic_activity WHERE journal_id = $journal_entry_id";
			$env{'dbh'}->do($qry);
			$qry = "DELETE FROM tj_journal_math_practices WHERE journal_id = $journal_entry_id";
			$env{'dbh'}->do($qry);
			$qry = "DELETE FROM tj_topic_materials WHERE journal_id = $journal_entry_id";
			$env{'dbh'}->do($qry);
			$qry = "DELETE FROM tj_user_materials WHERE journal_id = $journal_entry_id";
			$env{'dbh'}->do($qry);
			$qry = "DELETE FROM tj_journal_results WHERE journal_id = $journal_entry_id";
			$env{'dbh'}->do($qry);
			$qry = "DELETE FROM tj_journal_studresults WHERE journal_id = $journal_entry_id";
			$env{'dbh'}->do($qry);
			push @responses, {'journal_entry'=>'found existing ' . $journal_entry_id};
		} else {
			%fields = ('user_id'=>$env{'user_id'},
					'duration'=>$duration,
					'date_taught'=> &Apache::Promse::fix_quotes($date_taught),
					'class_id'=>$r->param('classid'),
					'lnotes'=>&Apache::Promse::fix_quotes($r->param('lnotes'))
					);
			$journal_entry_id = &Apache::Promse::save_record('tj_journal', \%fields,1);
			if ($journal_entry_id) {
			    push @responses, {'journal_entry'=>'inserted id ' . $journal_entry_id};
			} else {
			    push @responses, {'journal_entry'=>'error'};
			}
		}
	# there will be at least one tj_journal_topic to save
		my $standard_id = shift(@standards);
		my $duration = shift(@times);
		my $note = shift(@notes);
		my $priority = shift(@priorities);
		my $duration_mask = shift(@duration_masks);
		# save the first standard
		%fields = ('journal_id' => $journal_entry_id,
				'framework_id' => $standard_id,
				'duration' => $duration,
				'duration_mask'=>&Apache::Promse::fix_quotes($duration_mask),
				'background' => $background,
				'priority' => $priority,
				'pages'=> &Apache::Promse::fix_quotes($pages),
				'notes' => &Apache::Promse::fix_quotes($note)
						);
		my $result = "" . &Apache::Promse::save_record('tj_journal_topic',\%fields);
		if ($result) {
		    push @responses, {'journal_topic'=>'error'};
		} else {
		    push @responses, {'journal_topic'=>'inserted'};
		}
		# loop through all activities, assign them to first standard
		while (scalar(@results)) {
		    my $sresult = shift(@results);
			%fields = ('journal_id'=>$journal_entry_id,
			'results'=>$sresult);
			&Apache::Promse::save_record('tj_journal_results', \%fields);
		}
		while (scalar(@studresults)) {
		    my $result = shift(@studresults);
			%fields = ('journal_id'=>$journal_entry_id,
			'studresults'=>$result);
			&Apache::Promse::save_record('tj_journal_studresults', \%fields);
		}
		
		while (scalar(@activities)) {
		    my $activity = shift(@activities);
			%fields = ('journal_id'=>$journal_entry_id,
			'topic_id'=>$standard_id,
			'activity_id'=>$activity);
			&Apache::Promse::save_record('tj_topic_activity', \%fields);
		}
		while (my $math_practice = shift(@math_practices)) {
			%fields = ('journal_id'=>$journal_entry_id,
					'math_practice_id'=>$math_practice
			);
			my $result = &Apache::Promse::save_record('tj_journal_math_practices', \%fields, 0);
			if ($result) {
			    push @responses, {'math_practices'=>'error ' . $result};
			} else {
			    push @responses, {'math_practices'=>'inserted'};
			}
		}
		if ($material_id)  {
			# A material has been selected from the list
			%fields = ('journal_id'=>$journal_entry_id,
				'topic_id'=>$standard_id,
				'material_id'=>$material_id);
			my $result = &Apache::Promse::save_record('tj_topic_materials',\%fields,0); 
			if ($result) {
				push @responses, {'topic_material'=>'error ' . $result};
			} else {
				push @responses, {'topic_material'=>'inserted'};
			}
		}
		if ($material_name ne '') {
			# A material name has by typed in by the user
			%fields=('material_name'=>&Apache::Promse::fix_quotes($material_name),
					'journal_id'=>$journal_entry_id,
					'topic_id'=>$standard_id);
	        my $result = &Apache::Promse::save_record('tj_user_materials',\%fields,0);
			if ($result) {
				push @responses, {'user material'=>'error ' . $result};
			} else {
				push @responses, {'user material'=>'inserted'};
			}
		}
		
		# now loop through remaining standards
		
		while ($standard_id = shift(@standards)) {
			$duration = shift(@times);
			$priority = shift(@priorities);
			$note = shift(@notes);
			$duration_mask = shift(@duration_masks);
			%fields = ('journal_id' => $journal_entry_id,
					'framework_id' => $standard_id,
					'priority' => $priority,
					'duration_mask'=>&Apache::Promse::fix_quotes($duration_mask),
					'duration' => $duration,
					'notes' => &Apache::Promse::fix_quotes($note)
			);
			my $result = &Apache::Promse::save_record('tj_journal_topic',\%fields,0);
			if ($result) {
			    push @responses, {'journal_topic_mult'=>'error ' . $result};
			} else {
			    push @responses, {'journal_topic_mult'=>'inserted'};
			}			
		}
			my %responses_hash = ('success'=>\@responses);
			my $output = JSON::XS::encode_json \%responses_hash;
			$r->print($output);
		}
    sub insert_journal_entry {
		my ($r) = @_;
		my $response = '';
		my $qry = "SELECT journal_id FROM tj_journal WHERE class_id = $r->param('classid') AND date_taught = $r->param('datetaught')";
		my $rst = $env{'dbh'}->prepare($qry);
		my $inserted_id;
		$rst->execute();
		if (my $row = $rst->fetchrow_hashref()) {
			$inserted_id = $$row{'journal_id'};
			$response = <<END
			{"inserted_id": "$inserted_id"
			}
END
		} else {
			my %fields = ('user_id' => $env{'user_id'},
							'date_taught'=>$r->param('datetaught'),
							'class_id' => $r->param('classid')
							);
			$inserted_id = &Apache::Promse::save_record('tj_journal',\%fields,1);
			if ($inserted_id) {
				$response = <<END
					{"inserted_id": "$inserted_id"
					}
END
			} else {
				$response = <<END
				{"inserted_id": "failed"}
END
			}
		}
		return($response)
	}
	sub insert_proposed_school {
	    my ($r) = @_;
	    my $output;
	    my %fields = ('school'=>&Apache::Promse::fix_quotes($r->param('schoolname')),
	                    'district'=>&Apache::Promse::fix_quotes($r->param('districtname')),
	                    'zip'=>$r->param('schoolzip'),
	                    'email'=>&Apache::Promse::fix_quotes($r->param('personemail')));
	    my $school_id = &Apache::Promse::save_record('proposed_schools',\%fields,1);
	    my %response = ('status'=>$school_id);
	    $output = JSON::XS::encode_json \%response;
	    $r->print($output);
	}
	sub insert_proposed_text {
	    my ($r) = @_;
	    my $output;
	    my %fields = ('title'=>&Apache::Promse::fix_quotes($r->param('nonlistedTextbook')),
	                    'year'=>$r->param('nonlistedTextbookYearPublished'),
	                    'publisher'=>&Apache::Promse::fix_quotes($r->param('nonlistedTextbookPublisher')),
	                    'isbn'=>&Apache::Promse::fix_quotes($r->param('nonlistedTextbookISBN')),
	                    'email'=>&Apache::Promse::fix_quotes($r->param('email')));
	    my $book_id = &Apache::Promse::save_record('proposed_texts',\%fields,1);
	    my %response = ('status'=>$book_id);
	    $output = JSON::XS::encode_json \%response;
	    $r->print($output);
	}
	sub get_user_info {
		my($r) = @_;
		my $qry;
		my $rst;
		my $output;
		my $user_id = $env{'user_id'};
		$qry = "SELECT count(*) as count FROM tj_journal WHERE user_id = $user_id AND
				tj_journal.date_taught > '2012-01-02' AND
				tj_journal.date_taught < '2012-01-13'";
		$rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my $count_row = $rst->fetchrow_hashref();
		my $invoice_check = $$count_row{'count'} gt 8 ?'ok':'not_ok';
		$qry = "SELECT users.firstname, users.lastname, users.email, tj_types.type_id, tj_types.type_name,
					tj_classes.class_id, tj_classes.class_name, districts.district_id, 
					tj_user_classes.duration as periodduration, tj_user_info.default_curriculum
							FROM (users, tj_classes, tj_user_classes)
							LEFT JOIN (tj_teacher_type, tj_types) ON tj_teacher_type.type_id = tj_types.type_id AND 
								tj_teacher_type.user_id = users.id AND tj_teacher_type.class_id = tj_classes.class_id
							LEFT JOIN tj_user_info on tj_user_info.user_id = users.id
							LEFT JOIN user_locs ON user_locs.user_id = users.id
							LEFT JOIN locations ON locations.location_id = user_locs.loc_id
							LEFT JOIN districts ON (districts.district_id = user_locs.loc_id OR districts.district_id = locations.district_id)
							WHERE users.id = tj_user_classes.user_id AND
								tj_classes.class_id = tj_user_classes.class_id AND
								users.id = $user_id
							ORDER BY users.lastname, users.firstname";
		$rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		print STDERR "\n $qry \n ";
		my %output;
		if (my $row  = $rst->fetchrow_hashref()) {
			my %user;
			$user{'name'} = $$row{'firstname'}.' ' . $$row{'lastname'};
			$user{'email'} = $$row{'email'};
			$user{'invoice1'} = $invoice_check;
			$user{'district_id'} = $$row{'district_id'};
			$user{'textbook'} = $$row{'default_curriculum'};
			my @classes;
			my $type_id = $$row{'type_id'}?$$row{'type_id'}:0;
			my $type_name = $$row{'type_name'}?$$row{'type_name'}:'none';
			my %class = ('classid'=> $$row{'class_id'},
						'classname'=> $$row{'class_name'},
						'periodduration'=>$$row{'periodduration'},
						'typeid'=> $type_id,
						'typename'=> $type_name);
			push @classes, {%class};
			while ($row = $rst->fetchrow_hashref()) {
				my $periodduration = $$row{'periodduration'}?$$row{'periodduration'}:'NA';
				$type_id = $$row{'type_id'}?$$row{'type_id'}:$type_id;
				$type_name = $$row{'type_name'}?$$row{'type_name'}:$type_name;
				%class = ('classid' => $$row{'class_id'},
						'classname'=>$$row{'class_name'},
						'periodduration'=>$periodduration,
						'typeid'=> $type_id,
						'typename'=>$type_name);
				push @classes, {%class};
			}
			$user{'classes'} = \@classes;
			$qry = "SELECT t1.invoice_id, t1.message, t2.initials, t2.`status`, t2.time_stamp
			        FROM tj_invoices t1
			        LEFT JOIN tj_user_invoice t2 ON t1.invoice_id = t2.invoice_id AND t2.user_id = ?  
                    WHERE t1.date_available < NOW() AND
	                t1.date_due > NOW() ORDER BY t2.time_stamp DESC";
	        $rst = $env{'dbh'}->prepare($qry);
	        $rst->execute($env{'user_id'});
	        my @notices;
	        my %returned_ids;
	        while (my $notice = $rst->fetchrow_hashref()) {
	            if (! $returned_ids{$$notice{'invoice_id'}}) {
	                push @notices,{%$notice};
	                $returned_ids{$$notice{'invoice_id'}} = 1;
	            }
	        }
	        $user{'notices'} = [\@notices];
			$output{'user'} = [\%user];
			my $json_output = JSON::XS::encode_json \%output;
			$r->print($json_output);
		} else {
			$r->print('{"response": "fail"}');
		}
		# return email, name, classes,
		# more to be added

	}
	sub get_user_summary {
		my ($r,$passed_user_id,$get_all) = @_;
		my $output;
		my $qry = "SELECT tj_journal.class_id as cls_id, tj_journal.user_id as usr_id, 
			tj_journal_topic.framework_id as topic, framework_items.`code`, framework_items.description, tj_journal_topic.duration,
			count(tj_journal_topic.framework_id) as num_lsns, sum(tj_journal_topic.duration) as tot_dur
		FROM tj_journal, tj_journal_topic, tj_topic_activity, framework_items
		WHERE tj_journal.journal_id = tj_journal_topic.journal_id AND
			tj_topic_activity.journal_id = tj_journal.journal_id AND
			framework_items.id = tj_journal_topic.framework_id AND
			tj_journal.user_id = $passed_user_id AND
			tj_journal.deleted <> 1 AND
			tj_journal_topic.deleted <> 1
		GROUP BY cls_id, tj_journal_topic.framework_id
		";
		my $rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		$output .= "_______Class________topic________Num Lessons_______Duration______<BR>";
		
		while (my $row = $rst->fetchrow_hashref()) {
			$output .= $$row{'cls_id'} . "_____" . $$row{'topic'} . "________" . $$row{'num_lsns'} . "_______" . $$row{'tot_dur'} . "<br>";
		}
		return($output);
	}
	sub update_user_curriculum {
	    my ($r) = @_;
	    my $curriculum_id = $r->param('curriculumid');
	    my $user_id = $env{'user_id'};
	    # need to check if record exists
	    my $qry = "SELECT user_id, gender, years_experience,default_curriculum FROM tj_user_info WHERE user_id = ?";
	    my $rst = $env{'dbh'}->prepare($qry);
	    $rst->execute($env{'user_id'});
	    my $row = $rst->fetchrow_hashref();
	    if ($$row{'user_id'}) {
	        if ($$row{'default_curriculum'} ne $curriculum_id) {
    	        my %fields = ('user_id'=>$$row{'user_id'},
    	                    'gender'=>$$row{'gender'},
    	                    'years_experience'=>$$row{'years_experience'},
    	                    'default_curriculum'=>$$row{'default_curriculum'});
    	        my $table = 'tj_user_info_history';
    	        Apache::Promse::insert_record ($table, \%fields);
    	        $qry = "UPDATE tj_user_info SET default_curriculum = ? WHERE user_id = ?";
    	        $rst = $env{'dbh'}->prepare($qry);
    	        $rst->execute($curriculum_id,$user_id);
    	    }
	    } else {
	        $qry = "INSERT INTO tj_user_info (user_id, default_curriculum) VALUES (?,?)";
	        $rst = $env{'dbh'}->prepare($qry);
	        $rst->execute($env{'user_id'},$curriculum_id);
	    }
	}
	sub get_user_info_old {
		my($r) = @_;
		my $qry;
		my $rst;
		my $fh;
		my $output;
		my $user_id = $env{'user_id'};
		my $file_name = " /var/www/logs/userinfo". $user_id . ".jsn";
        if (open($fh, '>' . $file_name)) {
        } else {
            print STDERR "output returned false \n"
        }
        my $json_out;
        my $jsonw = '';
		$qry = "SELECT count(*) as count FROM tj_journal WHERE user_id = $user_id AND
				tj_journal.date_taught > '2012-01-02' AND
				tj_journal.date_taught < '2012-01-13'";
		$rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		my $count_row = $rst->fetchrow_hashref();
		my $invoice_check = $$count_row{'count'} gt 8?'ok':'not_ok';
		$qry = "SELECT users.firstname, users.lastname, users.email, tj_types.type_id, tj_types.type_name,
								tj_classes.class_id, tj_classes.class_name
							FROM (users, tj_classes, tj_user_classes)
							LEFT JOIN (tj_teacher_type, tj_types) ON tj_teacher_type.type_id = tj_types.type_id AND 
								tj_teacher_type.user_id = users.id AND tj_teacher_type.class_id = tj_classes.class_id
							WHERE users.id = tj_user_classes.user_id AND
								tj_classes.class_id = tj_user_classes.class_id AND
								users.id = $user_id
							ORDER BY users.lastname, users.firstname";
		$rst = $env{'dbh'}->prepare($qry);
		$rst->execute();
		if (my $row  = $rst->fetchrow_hashref()) {
        #$jsonw =  JSON::Streaming::Writer->for_stream($fh);
        $jsonw->pretty_output(1);
		$jsonw->start_object();
			$jsonw->start_property('user');
				$jsonw->start_array();
					$jsonw->start_object();
						$jsonw->add_property('name', $$row{'firstname'}.' ' . $$row{'lastname'});
						$jsonw->add_property('email', $$row{'email'});
						$jsonw->add_property('invoice1', $invoice_check);
						$jsonw->start_property('classes');
							$jsonw->start_array();
								$jsonw->start_object();
									$jsonw->add_property('classid', $$row{'class_id'});
									$jsonw->add_property('classname', $$row{'class_name'});
									my $type_id = $$row{'type_id'}?$$row{'type_id'}:0;
									my $type_name = $$row{'type_name'}?$$row{'type_name'}:'none';
									$jsonw->add_property('typeid', $type_id);
									$jsonw->add_property('typename', $type_name);
								$jsonw->end_object();
			while ($row = $rst->fetchrow_hashref()) {
								$jsonw->start_object();
									$jsonw->add_property('classid', $$row{'class_id'});
									$jsonw->add_property('classname', $$row{'class_name'});
									$type_id = $$row{'type_id'}?$$row{'type_id'}:0;
									$type_name = $$row{'type_name'}?$$row{'type_name'}:'none';
									$jsonw->add_property('typeid', $type_id);
									$jsonw->add_property('typename', $type_name);
								$jsonw->end_object();
			}
							$jsonw->end_array();
						$jsonw->end_property();
					$jsonw->end_object();
				$jsonw->end_array();
			$jsonw->end_property();
		$jsonw->end_object();
			close ($fh);
			open (IN, '<' . $file_name);
			while (<IN>) {
				$output .= $_;
			}
			$r->print($output);
		} else {
			$r->print('{"response": "fail"}');
		}
		# return email, name, classes,
		# more to be added

	}
	sub xml_header {
        my($r) = @_;
        print $r->header(-type => 'text/xml');
        $r->print('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n");
    }
	sub get_framework2_file {
		my ($r) = @_;
		open (FRAMEWORK, "/var/www/html/framework1.jsn"); 
		my $line;
		while ($line = <FRAMEWORK>) {
			$r->print($line);
		}
	}
	sub get_framework_file {
		my ($r) = @_;
		open (FRAMEWORK, "/var/www/html/framework1.jsn");
		my $line;
		while ($line = <FRAMEWORK>) {
			$r->print($line);
		}
	}
    sub get_framework {
        my ($r) = @_;
        my %fields;
        my $framework_id = 1; #$r->param('frameworkid');
        #my $curriculum_id = $r->param('curriculumid');
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
        my $fh;
		my @field_names;
		$field_names[0] = "id";
		$field_names[1] = "code";
		$field_names[2] = "levelname";
		$field_names[3] =  "text";
		$field_names[4] = "description";
        if (open($fh,">/var/www/logs/output.jsn")) {
        } else {
            print STDERR "output returned false \n"
        }
        my $json_out;
        my $jsonw = '';
        my $object_counter = 0;
		
        #$jsonw =  JSON::Streaming::Writer->for_stream($fh);
        $jsonw->pretty_output(1);

		%fields = ('text'=>'Topic Selector',
				'levelname'=>'root',
				'code'=>'root',
				'id'=>'root',
				'description' => 'Root for topic selector');
		&start_json_object($jsonw, \%fields); #starts root 	
		$object_counter ++;	
		$jsonw->start_property('children');
		$jsonw->start_array();


        %fields = ('text'=>$framework_title,
                    'levelname'=>'Framework',
					'code'=>'CC',
                    'id'=>$framework_id,
                    'description'=>$framework_description
                    );
        $jsonw = &start_json_object($jsonw, \%fields);#starts the framework
        $object_counter ++;
        $jsonw->start_property('children');
        my @framework_levels;
        my $depth = 0;
        my %depth_is_leaf;
        my $current_grade = -1;
        my $current_strand = '';
        # need to wrap strands in a grade
        my $grade_object;
        my $strand_object;
        my $grade_open = 0;
        my $counter = 0;

        foreach my $framework_item (@framework) {
            $counter ++;
			my $code = '';
			$$framework_item{'description'} =~ /(.*?\.) (.*)/;
			$code = $1;
			$code = $code?$code:'';
            if ($$framework_item{'grade'} ne $current_grade) {
                $current_grade = $$framework_item{'grade'};
                if ($grade_open) { # check if we have a grade in process
                    $jsonw->add_property('leaf','true');
                    $jsonw->end_object();
                    $object_counter --;
                    $jsonw->end_array();
                    $jsonw->end_property();
                    $jsonw->end_object();
                    $object_counter --;
                    if ($current_parent eq $$framework_item{'parent_id'}) {
                        #$depth --;
                    }
                    while ($depth > 0) {
                        $jsonw->end_array();
                        $jsonw->end_property();
                        $jsonw->end_object();
                        $object_counter --;
                        # $framework_levels[$current_level - 1] -> appendChild($framework_levels[$current_level]);
                        $depth --;
                    }
                } else {
                    $grade_open = 1;
                    $jsonw->start_array();
                }
                my $displayGrade = $current_grade eq 0?'K':$current_grade;
				$displayGrade = $current_grade eq 9?'HS':$current_grade;
                %fields = ('id'=>$current_grade,
                        'levelname'=>'Grade',
						'description' => 'Grade ' . $displayGrade,
						'code'=>'.$current_grade',
                        'text'=>'Grade ' . $displayGrade);
                $jsonw = &start_json_object($jsonw, \%fields, @field_names);
                $object_counter ++;
				$jsonw->start_property('children');
				$jsonw->start_array();
				%fields = ('id'=>$$framework_item{'code'},
				            'text'=>$level_names{'0'},
				        'code'=>$$framework_item{'code'},
				        'levelname'=>$level_names{$depth},
				        'description'=>$$framework_item{'strand_description'});
				$jsonw = &start_json_object($jsonw, \%fields, @field_names);
				$object_counter ++;
				$jsonw->start_property('children');
				$jsonw->start_array(); # array will be a bunch of clusters
				$depth ++; # for common core we are now at cluster level (1)
				%fields = ('id' => $$framework_item{'id'},
				            'code'=>$code,
				            'text' => substr($$framework_item{'description'},0,140),
				            'levelname'=>$level_names{$depth},
				            'description' => $$framework_item{'description'}
				            );
                $item_levels{$$framework_item{'id'}} = $depth;
				$jsonw = &start_json_object($jsonw, \%fields, @field_names);
				$object_counter ++;
                $current_strand = $$framework_item{'code'};
                $current_parent = $$framework_item{'parent_id'};
            } elsif ($$framework_item{'code'} ne $current_strand) {
                $jsonw->add_property('leaf','true');
                $jsonw->end_object();
                $object_counter --;
                $current_strand = $$framework_item{'code'};
                while ($depth > 0) {
                    $jsonw->end_array();
                    $jsonw->end_property();
                    $jsonw->end_object();
                    $object_counter --;
                    $depth --;
                }
				%fields = ('id'=>$$framework_item{'code'},
				            'text'=>substr($$framework_item{'strand_description'},0,140),
				        'code'=>$$framework_item{'code'},
						'levelname'=>$level_names{$depth},
				        'description'=>$$framework_item{'strand_description'});
				$jsonw = &start_json_object($jsonw, \%fields, @field_names);
				$object_counter ++;
				$jsonw->start_property('children');
				$jsonw->start_array(); # array will be a bunch of clusters
				$depth ++; # for common core we are now at cluster level (1)
				%fields = ('id' => $$framework_item{'id'},
				            'text' => substr($$framework_item{'description'},0,140),
							'code' => $code,
				            'description' => $$framework_item{'description'},
				            'levelname'=>$level_names{$depth}
				            );
				$jsonw = &start_json_object($jsonw, \%fields, @field_names);
				$object_counter ++;
                $item_levels{$$framework_item{'id'}} = $depth;
                # at depth 2 now (standard) might have children, don't know
            } elsif ($$framework_item{'parent_id'} eq 0) {
                # maybe a new cluster here. cluster has children, but not all descendents
                # WRONG MD has no children *****
                if ($current_strand eq $$framework_item{'code'}) {
                    #$jsonw->add_property('depth',$depth);
                    $jsonw->add_property('leaf','true');
                    $jsonw->end_object();
                    $object_counter --;
                } else {
                    $jsonw->end_object();
                    $object_counter --;
                }
                # top level of hierarchy, so have dispense with lower levels under construction
                while ($depth > 1) {
                    $jsonw->end_array();
                    $jsonw->end_property();
                    $jsonw->end_object();
                    $object_counter --;
                    $depth --;
                }
                # we save this so if this has children we know its level
                $item_levels{$$framework_item{'id'}} = $depth;
				%fields = ('id' => $$framework_item{'id'},
				            'text' => substr($$framework_item{'description'},0,140),
							'code' => $code,
				            'description' => $$framework_item{'description'},
				            'levelname'=>$level_names{$depth}
				            );
				$jsonw = &start_json_object($jsonw, \%fields, @field_names);
				$object_counter ++;
                #started the object, don't know yet if children or leaf property
            } else {
                if ($current_parent eq $$framework_item{'parent_id'}) {
                    $jsonw->add_property('leaf','true');
                    $jsonw->end_object();
                    $object_counter --;
    				%fields = ('id' => $$framework_item{'id'},
    				            'text' => substr($$framework_item{'description'},0,140),
								'code' => $code,
    				            'levelname'=>$level_names{$depth},
    				            'description' => $$framework_item{'description'}
    				            );
    				$jsonw = &start_json_object($jsonw, \%fields, @field_names);
    				$object_counter ++;
                    $item_levels{$$framework_item{'id'}} = $depth;
    				# need to set children property or leaf property
                } else {
                    # we're changing parent - need to know if we've already created any children
                    # of that parent
                    if ($existing_parents{$$framework_item{'parent_id'}}) {
                        # here if we've seen this parent before it means we're
                        # creating a node at a higher level and it means
                        # that the current level has no children
                        $jsonw->add_property('leaf','true');
                        #$jsonw->add_property('depth'=>$depth);
                        $jsonw->end_object();
                        $object_counter --;
                        # ended the object, so up a level
                        # every higher level must have children
                        while ($depth > $item_levels{$$framework_item{'parent_id'}} + 1) {
                            $jsonw->end_array();
                            $jsonw->end_property();
                            $jsonw->end_object();
                            $object_counter --;
                            $depth --;
                        }
                        $item_levels{$$framework_item{'id'}} = $depth;
        				%fields = ('id' => $$framework_item{'id'},
        				            'text' => substr($$framework_item{'description'},0,140),
        				            'code' => $code,
        				            'levelname'=>$level_names{$depth},
        				            'description' => $$framework_item{'description'}
        				            );
        				$jsonw = &start_json_object($jsonw, \%fields, @field_names);
                        $object_counter ++;
                    } else {
                        # here if we find out that parent has children
                        # that is we've discovered a new parent
                        $jsonw->start_property('children');
                        $jsonw->start_array();
                        $depth ++;
        				%fields = ('id' => $$framework_item{'id'},
									'code'=>$code,
        				            'text' => substr($$framework_item{'description'},0,140),
        				            'levelname'=>$level_names{$depth},
        				            'description' => $$framework_item{'description'}
        				            );
        				$jsonw = &start_json_object($jsonw, \%fields, @field_names);
        				$object_counter ++;
                        # save this item in lists of parents
                        $existing_parents{$$framework_item{'parent_id'}} = 1;
                        $item_levels{$$framework_item{'id'}} = $depth;
                        # deeper into the hierarchy
                    }
                    # print STDERR $framework_levels[$current_level]->toString();
                    $current_parent = $$framework_item{'parent_id'};
                }
            }
        } # end loop for row
        $jsonw->add_property('leaf','true');
        $jsonw->end_object();
        $object_counter --;
        $jsonw->end_array();
        $jsonw->end_property();
        $jsonw->end_object();
        while ($depth > 0) {
            $jsonw->end_array();
            $jsonw->end_property();
            $jsonw->end_object();
            $object_counter --;
            $depth --;
        }
        $jsonw->end_array();
        $jsonw->end_property();
        $jsonw->end_object(); #ends framework
        $object_counter --;

		

		%fields = ('text'=>'Other Topics',
				'levelname'=>'Other',
				'code'=>'O',
				'id'=>'10001',
				'description'=>'Topics not in framework.');
		&start_json_object($jsonw,\%fields);
		$object_counter ++;
		$jsonw->start_property('children');
		$jsonw->start_array();
		
		my @other_topics = ('Snow Day', 'Fire Drill', 'PD Day', 'Inservice Day', 'Vacation Day', 'Sick Day',
		 'Half day school - no math class', 'MEAP Prep Day', 'Conferences','Testing Day');
		my $id_number = 10002;
		foreach my $other (@other_topics) {
			%fields = ('text'=> $other,
				'levelname'=>'Other Topics',
				'code'=>'OTHER',
				'id'=> $id_number,
				'description'=> $other);
			&start_json_object($jsonw, \%fields, @field_names);
			$object_counter ++;
			$jsonw->add_property('leaf','true' );
			$jsonw->end_object();
			$object_counter --;
			$id_number ++;
		}
		$jsonw->end_array();
		$jsonw->end_property(); #ends 'children' property of 'Other topics'
		$jsonw->end_object(); #ends the 'Other topics' level of selector
		$jsonw->end_array(); #ends array of objects under root
		$jsonw->end_property(); #ends 'children' property of Root
		$jsonw->end_object(); #ends root object
#        &xml_header($r);
#        $r->print($framework_root->toString);
    }
    sub start_json_object {
        my ($json, $fields, @field_names) = @_;
        $json->start_object();
        foreach my $name (@field_names) {
            $json->add_property($name, $$fields{$name});
        }
        return($json);
    }
sub top_of_page {
    my $r = @_;
    my $output = '';
    $output = <<'ENDHTML';
    <!DOCTYPE HTML>
    <html>
    <head>
    <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.6.4/jquery.min.js"></script>
    <script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.16/jquery-ui.min.js"></script>
    <script type="text/javascript" src="../_scripts/jquery.mapAttributes.js"></script>
    <script type="text/javascript" src="../_scripts/jquery.listAttributes.js"></script>
    <script type="text/javascript" src="../_scripts/hierarchicalSelector.js"></script>
    <style type="text/css" media="all">@import "../_stylesheets/teacherJournal.css";</style>
    <script type="text/javascript">
ENDHTML
    $output .= 'var token = "' . $env{'token'} . '";' . "\n";
    $output .= 'var frameworkid = 1;' . "\n";
    $output .= <<ENDHTML;
        var ajaxData = {token: token,
                        action: "getframework",
                        frameworkid: frameworkid
        };

    var frameworkXML;
    var frameworkSelector;
    $(document).ready(function(){
        var ajaxData = {token: token,
                        action: "getframework",
                        frameworkid: frameworkid
        };
        var pageOutput = '';
        var strandArray = {};
        var counter = 0;
        var rowClass = 'rowAltLight';
        var jqxhr = $.ajax({
            url: "http://vpddev.educ.msu.edu/promse/flash",
            data: ajaxData,
            dataType: "xml",
            success: function(xml) {
                frameworkXML = $(xml);
				frameworkSelector = new hierarchicalSelector(frameworkXML);
                //$(xml).find('node').filter('[title=Domain]').each(function(){
                $(xml).find('grade').each(function(){
                    var thisID = $(this).attr('gradelevel');
                    if (! (thisID in strandArray)) {
                        rowClass = rowClass=='rowAltLight'?'rowAltDark':'rowAltLight';
                    }
                })
            }
        })
 });
</script>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<title>Teacher's Journal</title>
</head>

<body>
<div id="hsContainer">
    <div id="headerContainer">
    </div>
    <div id="scrollContainer">
        <div id="scrollingRows">
			<!--- listItems go here -->
        </div>
    </div>
	<div id="animationLayer">
	</div>
</div>
</body>
</html>
ENDHTML
return ($output);
}
1;