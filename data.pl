#!/usr/bin/env /home/username/perl5/bin/plackup

BEGIN {
	push @INC, "$ENV{HOME}/perl5/lib/perl5", "$ENV{HOME}/convotree_engine/modules";
};

use strict;
use warnings;

use JSON;
use Plack::Request;

use ConvoTreeEngine::Exceptions;
use ConvoTreeEngine::Mysql;
use ConvoTreeEngine::API;

my $connection_exception;
eval {
	ConvoTreeEngine::Mysql->getConnection;
};
if ($connection_exception = $@) {
	ConvoTreeEngine::Exception::Unexpected->promote($connection_exception);
}

my $app = sub {
	my $env = shift;

	if ($connection_exception) {
		return [
			($connection_exception->code || $connection_exception->HTTPCode),
			['Content-Type' => 'application/json; charset=utf8'],
			[JSON::encode_json({
				error       => $connection_exception->output,
				error_class => ref($connection_exception),
			})],
		];
	}

	my $request = Plack::Request->new($env);
	return ConvoTreeEngine::API->api($request);
};