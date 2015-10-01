package Apache::Hello;
# File: Apache/Hello.pm

use strict;
use Apache::Constants qw(:common);

sub handler {
    my $r=shift;
    $r->content_type('text/html');
    $r->send_http_header;
    my $host = $r->get_remote_host;
    $r->print(<<END);
<HTML>
<HEAD>
<TITLE>Hello There</TITLE>
</HEAD>
<BODY>
<h1>Hello $host</h1>
Who would take this book seriously if the first example didn't say "hello world"?
</body>
</html>
END
    return OK;
}

1;