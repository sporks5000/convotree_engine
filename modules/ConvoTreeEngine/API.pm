package ConvoTreeEngine::API;

use strict;
use warnings;

use JSON;

use ConvoTreeEngine::Config;
use ConvoTreeEngine::Exceptions;
use ConvoTreeEngine::Object::Element;

=head2 api

perform API actions. Expects a L<Plack::Request> object to be passed in.

=cut

sub api {
	my $class   = shift;
	my $request = shift;

	my $response;
	eval {
		my $body = eval {
			JSON::decode_json($request->raw_body || '{}');
		} || {};
		my $uri = $request->request_uri;

		if ($uri =~ m@/element/get/?@i) {
			my $ids = $body->{id} || $body->{ids};
			my $elements = ConvoTreeEngine::Object::Element->searchWithNested_hashRefs($ids);
			$response = $elements;
		}
		elsif ($ConvoTreeEngine::Config::modification_over_api) {
			if ($uri =~ m@/element/create/?@i) {
				my $element = ConvoTreeEngine::Object::Element->create($body);
				$response = $element->asHashRef;
			}
			elsif ($uri =~ m@/element/update/?@i) {
				my %searchArgs;
				foreach my $arg (qw/id name category namecat/) {
					$searchArgs{$arg} = delete $body->{$arg} if exists $body->{$arg};
				}
				my $element = ConvoTreeEngine::Object::Element->findOrDie(\%searchArgs);
				$element->update($body);
				$response = $element->asHashRef;
			}
			elsif ($uri =~ m@/element/delete/?@i) {
				my %searchArgs;
				foreach my $arg (qw/id name category namecat/) {
					$searchArgs{$arg} = delete $body->{$arg} if exists $body->{$arg};
				}
				my $element = ConvoTreeEngine::Object::Element->findOrDie(\%searchArgs);
				$element->delete;
				$response = {deleted => 1};
			}
		}

		ConvoTreeEngine::Exception::Input->throw(
			error => "API endpoint not found: '$uri'",
			code  => 404,
		) unless $response;

		$response = JSON::encode_json({
			response => $response,
		});
	};
	if (my $ex = $@) {
		ConvoTreeEngine::Exception::Unexpected->promote($ex);
		return [
			($ex->code || $ex->HTTPCode || 500),
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
		[$response],
	];
}

1;