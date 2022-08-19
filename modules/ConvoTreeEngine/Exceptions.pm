package ConvoTreeEngine::Exceptions;

use strict;
use warnings;

our %meta;
BEGIN {
	%meta = (
		'ConvoTreeEngine::Exception' => {
			### Not designed to be used directly
			description => 'Base class from which other exception classes will inherit',
			fields      => [qw/code/],
		},
		'ConvoTreeEngine::Exception::Configuration' => {
			isa         => 'ConvoTreeEngine::Exception',
			description => 'A configuration is incorrect or undefined',
			fields      => [qw/setting value/],
		},
		'ConvoTreeEngine::Exception::Unexpected' => {
			isa         => 'ConvoTreeEngine::Exception',
			description => 'An otherwise unanticipated error',
		},
		'ConvoTreeEngine::Exception::Internal' => {
			isa         => 'ConvoTreeEngine::Exception',
			description => 'An internal, but otherwise unclassified error',
		},
		'ConvoTreeEngine::Exception::Connectivity' => {
			isa         => 'ConvoTreeEngine::Exception',
			description => 'A connection issue has occurred',
			fields      => [qw/service/],
		},
		'ConvoTreeEngine::Exception::RecordNotFound' => {
			isa         => 'ConvoTreeEngine::Exception',
			description => 'An attempt to find a record has failed',
			fields      => [qw/args/],
		},
		'ConvoTreeEngine::Exception::DuplicateRecord' => {
			isa         => 'ConvoTreeEngine::Exception::RecordNotFound',
			description => 'An attempt to find a single record has returned more than one record, or a matching record already exists',
		},
		'ConvoTreeEngine::Exception::SQL' => {
			isa         => 'ConvoTreeEngine::Exception',
			description => 'An issue with mysql syntax',
			fields      => [qw/sql args/],
		},
	);
}

use Exception::Class(%meta);

{
	package ConvoTreeEngine::Exception;

	__PACKAGE__->mk_classdata('HTTPCode');
	__PACKAGE__->HTTPCode(500);

	sub throw {
		my $self = shift;
		$self->rethrow if ref $self;
		die $self->new(@_);
	}

	sub new {
		my $self = shift->SUPER::new(@_);
		return $self;
	}

	sub promote {
		return $_[1] if ref $_[1];
		my $ex = $_[0]->new("$_[1]");
		$_[1] = $ex;
		return $ex;
	}

	sub output {
		my $self = shift;

		my $error = $self->error || 'An error has occurred';
		return $error;
	}
}

{
	package ConvoTreeEngine::Exception::Configuration;

	sub output {
		my $self = shift;

		my $setting = $self->setting;
		my $value   = $self->value;

		my $error = $self->error || 'A configuration error has occurred';
		if ($setting) {
			$error .= ": Setting '$setting' should not have a value of '$value'";
		}

		return $error;
	}
}

{
	package ConvoTreeEngine::Exception::Unexpected;

	sub output {
		my $self = shift;

		my $error = 'An unexpected error has occurred';
		if (my $text = $self->error) {
			$error .= ": $text";
		}

		return $error;
	}
}

{
	package ConvoTreeEngine::Exception::Internal;

	sub output {
		my $self = shift;

		my $error = 'An error has occurred';
		if (my $text = $self->error) {
			$error .= ": $text";
		}

		return $error;
	}
}

{
	package ConvoTreeEngine::Exception::Connectivity;

	sub output {
		my $self = shift;

		my $service = $self->service;
		my $error = "An error occurred when attempting to make an external connection";
		if (my $service = $self->service) {
			$error = "An error occurred when attempting to connect to $service";
		}

		if (my $text = $self->error) {
			$error .= ": $text";
		}

		return $error;
	}
}

{
	package ConvoTreeEngine::Exception::RecordNotFound;

	sub output {
		my $self = shift;

		my $error = $self->error || 'Record not found';
		my $args  = $self->args;
		if ($args && ref $args) {
			require JSON;
			$args = eval {JSON::encode_json($args)} || '';
		}
		if ($args) {
			$error .= ". Arguments: $args";
		}

		return $error;
	}
}

{
	package ConvoTreeEngine::Exception::DuplicateRecord;

	sub output {
		my $self = shift;

		my $error = $self->error || 'A duplicate record exists';
		my $args  = $self->args;
		if ($args && ref $args) {
			require JSON;
			$args = eval {JSON::encode_json($args)} || '';
		}
		if ($args) {
			$error .= ". Arguments: $args";
		}

		return $error;
	}
}

{
	package ConvoTreeEngine::Exception::SQL;

	sub output {
		my $self = shift;

		my $error = $self->error || 'There is an issue with SQL syntax';
		my $sql   = $self->sql;
		if ($sql) {
			$error .= " SQL: $sql";
			my $args = $self->args;
			if ($args && ref $args) {
				require JSON;
				$args = eval {JSON::encode_json($args)} || '';
			}
			if ($args) {
				$error .= ". Arguments: $args";
			}
		}

		return $error;
	}
}

1;