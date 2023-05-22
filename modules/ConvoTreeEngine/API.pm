package ConvoTreeEngine::API;

use strict;
use warnings;

use JSON;

use ConvoTreeEngine::Config;
use ConvoTreeEngine::Exceptions;
use ConvoTreeEngine::Validation;
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

		if ($uri =~ m@/element/get/(.*)$@i) {
			my $id = $1;
			my $elements = ConvoTreeEngine::Object::Element->searchWithNested_hashRefs($id);
			$response = $elements;
		}
		elsif ($uri =~ m@/element/get/?$@i) {
			my $ids = $body->{id} || $body->{ids};
			my $elements = ConvoTreeEngine::Object::Element->searchWithNested_hashRefs($ids);
			$response = $elements;
		}

		if (!$response && $ConvoTreeEngine::Config::modification_over_api) {
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

		if (!$response && $ConvoTreeEngine::Config::validation_over_api) {
			if ($uri =~ m@/element/validate/?@i) {
				eval {
					ConvoTreeEngine::Validation->validateElementJson($body->{json}, $body->{type});
				};
				##### TODO: I feel like we can expand on what's being returned here
				if ($@) {
					return {validated => 0};
				}
				return {validated => 1};
			}
			elsif ($uri =~ m@/validate/?@i) {
				eval {
					ConvoTreeEngine::Validation->validateValue($body->{value}, $body->{validator}, @{$body->{additional} || []});
				};
				##### TODO: I feel like we can expand on what's being returned here
				if ($@) {
					return {validated => 0};
				}
				return {validated => 1};
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

=head1 ConvoTreeEngine::API::TestRequest

Mocks the functions that we use from L<Plack::Request> in order to allow testing for the c<api> method.

=cut

{ package ConvoTreeEngine::API::TestRequest;
	require ConvoTreeEngine::Object;

	sub new {
		my $invocant = shift;
		my $args     = ConvoTreeEngine::Object->_prep_args(@_);

		ConvoTreeEngine::Exception::Input->throw(
			error => "expects arguments 'request_uri' and 'body' to be passed",
			code  => 500,
		) unless $args->{request_uri} && (!exists $args->{body} || (ref $args->{body} || '') eq 'HASH');

		my $class = ref $invocant || $invocant;

		return bless $args, $class;
	}

	sub request_uri {
		return shift->{request_uri};
	}

	sub raw_body {
		my $self = shift;
		return JSON::encode_json($self->{body});
	}
}

1;