#!/usr/bin/perl

use lib qw(../lib);
use strict;
use warnings;
use JSON;
use English;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use TestCGI;
use IO::Socket::SSL;
use LWP::UserAgent;

#Log::Log4perl->easy_init($DEBUG);
Log::Log4perl->easy_init($ERROR);

use Test::More tests => 4;

package main;

# Create the pkcs10
my $pkcs10 = `openssl req -new -subj "/CN=entity-rpc.openxpki.org" -nodes -keyout /tmp/oxi-test/entity-rpc.key 2>/dev/null`;

ok( $pkcs10  , 'csr present') || die;

my $ua = LWP::UserAgent->new;
$ua->timeout(10);

$ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS} = "IO::Socket::SSL";

my $ssl_opts = {
    verify_hostname => 0,
    SSL_key_file => '/tmp/oxi-test/pkiclient.key',
    SSL_cert_file => '/tmp/oxi-test/pkiclient.crt',
    SSL_ca_file => '/tmp/oxi-test/chain.pem',
};
$ua->ssl_opts( %{$ssl_opts} );

my $response = $ua->post('https://localhost/rpc/enroll', [
    method => 'RequestCertificate',
    pkcs10 => $pkcs10,
    comment => 'Automated request',
    ]
);

ok $response->is_success, 'HTTP request successful' or diag explain $response;

my $json = JSON->new->decode($response->decoded_content);

ok($json->{result}->{data}->{cert_identifier});

note 'Workflow Id ' . $json->{result}->{id};

note 'Cert Identifier' . $json->{result}->{data}->{cert_identifier};

is($json->{result}->{state}, 'SUCCESS');

open(CERT, ">", "/tmp/oxi-test/entity-rpc.id");
print CERT $json->{result}->{data}->{cert_identifier};
close CERT;
