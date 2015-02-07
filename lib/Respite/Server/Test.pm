package Respite::Server::Test;

use strict;
use warnings;
use Test::More;
use POSIX qw(tmpnam);
use Throw qw(throw import);
use End;
#use Data::Debug;

sub setup_test_server {
    my $args  = shift || {};
    my $verbose = exists($args->{'verbose'}) ? $args->{'verbose'} : 1;

    # setup some defaults
    my $port = $args->{'port'} || do {
        require IO::Socket;
        my $sock = IO::Socket::INET->new;
        $sock->configure({
            LocalPort => 0,
            Listen    => 1,
            Proto     => 'tcp',
            ReuseAddr => 1,
        }) || throw "Could not create temp socket", {msg => $!};
        my $port = $sock->sockport || throw "Could not generate random usable sockport";
    };
    my $tmpnam      = tmpnam();
    my $pid_file    = $args->{'pid_file'}    || "$tmpnam.$$.pid";
    my $access_file = $args->{'access_file'} || "$tmpnam.$$.access";
    my $error_file  = $args->{'error_file'}  || "$tmpnam.$$.error";
    my $no_brand    = exists($args->{'no_brand'}) ? 1 : 0;
    my $no_ssl      = exists($args->{'no_ssl'})   ? 1 : 0;
    #$no_ssl = 1;
    my $flat        = exists($args->{'flat'})     ? 1 : 0;

    my $server = $args->{'server'} || do {
        my $pkg = $args->{'server_class'} || 'Respite::Server';
        (my $file = "$pkg.pm") =~ s|::|/|g;
        eval { require $file } || throw "Could not require client library", {msg => $@};
        $pkg->new({
            no_brand        => $no_brand,
            ($args->{'service'}  ? (server_name => $args->{'service'})  : ()),
            ($args->{'api_meta'} ? (api_meta    => $args->{'api_meta'}) : ()),
            port            => $port,
            server_type     => $args->{'server_type'} || 'Fork',
            no_ssl          => $no_ssl,
            flat            => $flat,
            host            => $args->{'host'} || 'localhost',
            pass            => $args->{'pass'} || '123qwe',
            pid_file        => $pid_file,
            access_log_file => $access_file,
            log_file        => $error_file,
            user            => defined($args->{'user'})  ? $args->{'user'} : $<,
            group           => defined($args->{'group'}) ? $args->{'group'} : $(,
        });
    };
    #debug $server;
    my $service = $server->server_name;
    $service =~ s/_server$//;

    my $encoded = exists($args->{'utf8_encoded'}) ? 1 : 0;
    my $client = $args->{'client'} || do {
        my $pkg = $args->{'client_class'} || 'Respite::Client';
        (my $file = "$pkg.pm") =~ s|::|/|g;
        eval { require $file } || throw "Could not require client library", {msg => $@};
        $pkg->new({
            no_brand     => $no_brand,
            service      => $service,
            port         => $port,
            host         => $server->{'host'},
            pass         => $args->{'pass'} || '123qwe',
            no_ssl       => $no_ssl,
            flat         => $flat,
            utf8_encoded => $encoded,
            ($args->{'brand'} ? (brand => $args->{'brand'}) : ()),
        });
    };
    #debug $client;

    ###----------------------------------------------------------------###
    # start the server in a child, block the parent until ready

    my $pid = fork;
    die "Could not fork during test\n" if ! defined $pid;
    if (!$pid) { # child
        local @ARGV;
        $server->run_server(setsid => 0, background => 0); # allow a kill term to close the server too
        exit;
    }

    $client->{'_test_ender'} = end {
        diag("Process list") if $verbose;
        $server->__ps;

        diag("Stop server");
        $server->__stop;
        # get some info - then tear down

        diag("Tail of the error_log") if $verbose;
        $server->__tail_error(1000) if $verbose;

        diag("Tail of the access_log") if $verbose;
        $server->__tail_access($server->{'tail_access'} || 20) if $verbose;

        diag("Shut down server") if $verbose;
        unlink $_ for $pid_file, $access_file, $error_file; # double check
    };

    # block the parent (that will run client tests) until the child running the server is fully setup
    my $connected;
    for (1 .. 30) {
        select undef, undef, undef, .1;
        my $class = 'IO::Socket::INET';
        if (!$no_ssl) {
            require IO::Socket::SSL;
            $class = 'IO::Socket::SSL';
        }
        my $sock = $class->new(PeerHost => "localhost", PeerPort => $port, SSL_verify_mode => 0) || next;
        print $sock "GET /waited_until_child HTTP/1.0\n\n";
        $connected = 1;
        last;
    }
    if (! $connected) {
        diag("Tail of the error_log");
        $server->__tail_error($server->{'tail_error'} || 20) if $verbose;
        die "Failed to connect to the server: $!";
    }

    return wantarray ? ($client, $server) : $client;
}

1;

__END__

=head1 SYNOPSIS

    use Test::More tests => 2;
    use Respite::Server::Test qw(setup_test_server);

    my $client = setup_test_server({
        service  => 'bam', # necessary because we directly subclassed Respite::Server
        api_meta => 'Bam',    # ditto
        client_utf8_encoded => 1,
        flat => 1,
    });

    ok(1, "Test");

    my $resp = $client->some_api_method({
        some_key => 'some_val',
    });
    is($resp->{'some_return_key'}, 'some_return_val', 'A test');

=head1 DESCRIPTION

Returns a client and optional configured server.  Tests can then
be run against the client.

=head1 OPTIONS

The main function is setup_test_server.  It accepts a hashref with the
following options.

=over 4

=item server

Optional - if not passed, it will try and use server_class to create the
object.

=item server_class

Optional - if not passed it will try and use api_meta and service.

=item service

Name of the service - typically only used if Respite::Server is used
directly - otherwise it will default to the server_name of the server
with _server removed.

=item api_meta

Only used if Respite::Server is used - information about the API itself.

=item client_utf8_encoded

If your libraries are always working with utf8 encoded data - set this
(not necessary for some APIs).

=item no_ssl

Test the API without using ssl

=item no_brand

This API does not require Brand.

=item flat

Make the client return flat data results.

=item host

Default localhost - what hostname to bind.

=item pass

API password - defaults to 123qwe

=item port

Randomly chosen.

=item pid_file, access_file, log_file

File locations of the server files, defautls to tmpnam'ed files.  Auto
cleaned up.

=item server_type

Default to Fork.  Could use PreFork or Single too.

=item client

Default undef.  Can pass in your own client object.

=item client_class

Default Respite::Class.  What API client to use.

=item user

Which user to run the server as - defaults to current user.

=item group

Which group to run the server as - defaults to current group.

=back

=cut
