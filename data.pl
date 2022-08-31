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
use ConvoTreeEngine::Object::Element;

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
		my $uri = $request->request_uri;

		if ($uri =~ m@/element/create/?@i) {
			my $element = ConvoTreeEngine::Object::Element->create($body);
			$response = $element->asHashRef;
		}
		elsif ($uri =~ m@/element/update/?@i) {
			my %searchArgs;
			$searchArgs{id} = delete $body->{id} if $body->{id};
			$searchArgs{namecat} = delete $body->{namecat} if $body->{namecat};
			my $element = ConvoTreeEngine::Object::Element->findOrDie(\%searchArgs);
			$element->update($body);
			return $element->asHashRef;
		}
		elsif ($uri =~ m@/element/delete/?@i) {
			my %searchArgs;
			$searchArgs{id} = delete $body->{id} if $body->{id};
			$searchArgs{namecat} = delete $body->{namecat} if $body->{namecat};
			my $element = ConvoTreeEngine::Object::Element->findOrDie(\%searchArgs);
			$element->delete;
			return {deleted => 1};
		}
		elsif ($uri =~ m@/element/get/?@i) {
			my $ids = $body->{id} || $body->{ids};
			my $elements = ConvoTreeEngine::Object::Element->searchWithNested($ids);
			return $elements;
		}
		else {
			ConvoTreeEngine::Exception::Input->throw(
				error => "API endpoint not found: '$uri'",
				code  => 404,
			);
		};
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