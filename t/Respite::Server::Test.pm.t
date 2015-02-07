#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
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
});

ok($client, 'Got client');
ok($server, 'Got server');

my $resp = $client->foo;
is($resp->{'BAR'}, 1, 'Call api method foo') or diag(explain($resp));
done_testing(6);

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
