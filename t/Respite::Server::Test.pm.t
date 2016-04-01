#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 12;
use Sub::Override;

use Respite::Base;   # Loading this here so we can override _configs
use Respite::Server; # Loading this here so we can override _configs
use Respite::Client; # Loading this here so we can override _configs

use Respite::Server::Test qw(setup_test_server);

sub _configs_mock {
    return {
        server_type => 'moo',
        provider => 'me',
    }
}

my %override;
foreach my $key (qw(Base Server Client)) {
    my $module_sub = "Respite::$key\::_configs";
    ok($override{$key} = Sub::Override->new($module_sub => \&_configs_mock), "Override $module_sub")
}

my ($client, $server) = setup_test_server({
    service  => 'bam', # necessary because we directly subclassed Respite::Server
    api_meta => 'Bam',    # ditto
    client_utf8_encoded => 1,
    flat => 1,
    no_ssl => 1,
    # no password
});

my ($client2, $server2) = setup_test_server({
    service  => 'bam', # necessary because we directly subclassed Respite::Server
    api_meta => 'Bam',    # ditto
    client_utf8_encoded => 1,
    flat => 1,
    no_ssl => 1,
    allow_auth_basic => 1,
    pass => 'fred',
});

ok($client, 'Got client');
ok($server, 'Got server');
ok($client2, 'Got client2');
ok($server2, 'Got server2');

my $resp = eval {$client->foo };
is($resp->{'BAR'}, 1, 'Call api method foo, server no pass, client no pass') or diag(explain($resp));

$client->{'pass'} = 'fred';
$resp = eval {$client->foo };
is($resp->{'BAR'}, 1, 'Call api method foo, server no pass, client uses pass') or diag(explain($resp));

$resp = eval {$client2->foo };
my $e = $@;
warn $e;
is($resp->{'BAR'}, 1, 'Call api method foo, server uses pass, client uses pass') or diag(explain($resp));

delete $client2->{'pass'};
$resp = eval {$client2->foo };
$e = $@;
cmp_ok($e, '=~', 'Invalid client auth', 'Call api method foo, server uses pass, client no pass') or diag(explain($resp));

$client2->{'pass'} = 'not correct';
$resp = eval {$client2->foo };
$e = $@;
cmp_ok($e, '=~', 'Invalid client auth', 'Call api method foo, server uses pass, client bad pass') or diag(explain($resp));

{
    package Bam;
    use strict;
    use Throw qw(throw);
    use base qw(Respite::Base);
    sub api_meta {
        return shift->{'api_meta'} ||= {
            methods => {
                foo => 'bar',
            },
        };
    }

    sub bar { {BAR => 1} }
    sub bar__meta {} # { {desc => 'Bar desc'} }
}

__END__

=head1 NAME

Respite::Base.pm.t

=head1 DEVEL

If anything, this is more of an example of setup_test_server that is packaged in Respite::Server::Test.
However, it is used for basic testing to see if the sub works or not.
Typically, you should not override _configs. That may likely go away in this unit tests sometime in the future.

=cut
