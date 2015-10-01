package Apache::Llabpage;
# File: Apache/Login.pm

use strict;
use Apache::Constants qw(:common);
#!/usr/bin/perl 

use CGI;
use Apache::Promse;
use Apache::Authenticate;
use Apache::Design;
my $r = new CGI;
&Apache::Promse::logthis('llab pages showing');
sub handler {
    #&Apache::Design::top_of_page($r);
    #return 'ok';
    &Apache::Promse::top_of_page($r);
    $r->print('testing for llab');
    
    &Apache::Promse::footer($r);
}
1;
__END__

