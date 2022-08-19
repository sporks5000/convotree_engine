#!/usr/bin/env /home/username/perl5/bin/plackup

BEGIN {
	push @INC, "$ENV{HOME}/perl5/lib/perl5", "$ENV{HOME}/convotree_engine/modules";
};

use strict;
use warnings;

use Plack::Request;
use JSON;

use ConvoTreeEngine::Exceptions;
use ConvoTreeEngine::Mysql;
use ConvoTreeEngine::Object::Element; ##### TODO: Temporary

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

	my $response;
	eval {
		my $request = Plack::Request->new($env);
		my $body = eval {
			JSON::decode_json($request->raw_body || '{}');
		} || {};
		$response = $request->request_uri . ": ";
		if ($body->{pid}) {
			$response .= $$;
		}
		else {
			my $name = $body->{name} || $request->raw_body;
			$response .= "Hello $name\n";
		}

##### TODO: Temporary

		my $element = ConvoTreeEngine::Object::Element->find({id => 6});
		$element->update({
			json => {html => '<div>Raw Fishes</div>'}
		});

		$response = JSON::encode_json([
			$element->asHashRef,
		]);

##### TODO: End temporary

	};
	if (my $ex = $@) {
		ConvoTreeEngine::Exception::Unexpected->promote($ex);
		return [
			($ex->code || $ex->HTTPCode),
			['Content-Type' => 'application/json; charset=utf8'],
			[JSON::encode_json({
				error       => $ex->output,
				error_class => ref($ex),
			})],
		];
	}

	return [
		'200',
		['Content-Type' => 'application/json; charset=utf8'],
		[JSON::encode_json({
			response => $response,
		})],
	];
};