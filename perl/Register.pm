package Apache::Register;
# File: Apache/Register.pm
#!/usr/bin/perl 
use strict;
use Apache::Promse;
use vars qw(%env);
use CGI;
sub handler {
    my $r = new CGI ();
	&Apache::Promse::validate_user($r);
    &Apache::Promse::top_of_page($r);
    my %fields;
    my $email = $r->param("email");
    my $target = $r->param("target");
    # my $username = $r->param("username");
    if ($target eq 'new') {
        # this gives user the form to enter new user information   
        &Apache::Promse::add_user_form($r);    
    } elsif ($target eq 'addemail') {
		my $email = $r->param('email');
		$email =~ /(.*)@(.*)/;
		my $email_name = $1;
		my $domain = $2;
		my $qry = "SELECT count(*) as count FROM ok_domains
					WHERE domain_name = ?";
		my $dbh = &Apache::Promse::db_connect();
		$dbh = $env{'dbh'};
		my $rst = $dbh->prepare($qry);
		$rst->execute($domain);
		my $row = $rst->fetchrow_hashref();
		if ($$row{'count'}) {
			# user entered a valid domain name
			$r->print("<br />Found domain <br />");
			$qry = "SELECT count(*) as count FROM users WHERE username = ?";
			$rst = $dbh->prepare($qry);
			$rst->execute($email);
			$row = $rst->fetchrow_hashref();
			if($$row{'count'}) {
				#user is already in database just send the login email
				$r->print("The email address you entered is already registered.");
			} else {
				# new user
				%fields = ('firstname'=>&Apache::Promse::fix_quotes($r->param('firstname')),
							'lastname'=>&Apache::Promse::fix_quotes($r->param('lastname')),
							'username'=>"'" . $email . "'",
							'email'=>"'" . $email . "'");
				&Apache::Promse::save_record('users',\%fields,0);
			}
			&Apache::Promse::email_password_reset($r);
		} else {
			$r->print("<br />The domain portion of the email address ($domain) was not found in our records. <br />
					Registration is available only for email addresses in invited domains.<br />");
		}
		#&Apache::Promse::email_password_reset($r);
    } elsif ($target eq 'addrecord') {
		my $username = $r->param('username');
        #first, better be sure that email address isn't already in 
        $fields{'llab_cn'} = "'".$username."'";
        my $name_status = &Apache::Promse::user_name_exist($username);
        if (&Apache::Promse::user_name_exist($username)==0) {
            $r->print('<br>Adding new user<br>');
            undef %fields;
            $fields{'email'} = $r->param("email");
            $fields{'username'} = $r->param("email");
            $fields{'firstname'} = $r->param("firstname");
            $fields{'lastname'} = $r->param("lastname");
            $fields{'password'} = "MD5('mypass')";
            my ($status,$message) = &Apache::Authenticate::register(\%fields);
            if ($status ne '0') {
                $r->print('Tech note: LDAP returned '.$message);
            }
            my $results = &Apache::Promse::add_new_user($r);
            $r->print('Welcome to VPD! You have successfully registered as a member of the VPD user group!');
            $r->print('<span style="content">You may <a href="promse">login</a> with your user name and password you selected.</span>');
        } else {
            $r->print('<br />The user name you selected is already in the database.<br />');
            $r->print('Tech note: status = '.$name_status.'<br />');
        }
    } else {
        print 'Please <a href="promse">Login</a>';
    }
    &Apache::Promse::footer;
    return 'OK';
}
1;
