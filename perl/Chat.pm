package Apache::Chat;
# File: Apache/Authenticate.pm
use strict;
use Apache::Constants qw(:common);
#!/usr/bin/perl 
use CGI;
use Apache::Promse;
use Apache::Design;
use DBI;

sub chat_root {
    my ($r) = @_;
    $r->print('<div id="interiorHeader">');
    $r->print('<h2>PROM/SE Live Chat</h2>');
    
    # $r->print('<h3>Great ideas are just a click away...</h3>');
    $r->print('</div>');
    $r->print('here it is');
    return 'ok';
}
1;
__END__
