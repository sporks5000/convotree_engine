#!/usr/bin/env /home/username/perl5/bin/plackup

BEGIN {
	push @INC, "$ENV{HOME}/perl5/lib/perl5", "$ENV{HOME}/convotree_engine/modules";
};

use strict;
use warnings;

use Plack::Request;
use JSON;

my $app = sub {
	my $env = shift;

	my $request = Plack::Request->new($env);
	my $body = eval {
		JSON::decode_json($request->raw_body || '{}');
	} || {};
	my $html = $request->request_uri . ": ";
	if ($body->{pid}) {
		$html .= $$;
	}
	else {
		my $name = $body->{name} || $request->raw_body;
		$html .= "Hello $name\n";
	}

	return [
		'200',
		['Content-Type' => 'text/html; charset=utf8'],
		[$html],
	];
};

